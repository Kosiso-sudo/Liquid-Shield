;; LiquidShield - Automated Market Maker with Impermanent Loss Protection
;; A decentralized exchange protocol providing time-based protection against impermanent loss

;; Import SIP-010 trait
(use-trait ft-trait .sip-010-trait.sip-010-trait)

;; Error and validation constants
(define-constant ERR-UNAUTHORIZED-ACCESS u1)
(define-constant ERR-POOL-ALREADY-EXISTS u2)
(define-constant ERR-POOL-NOT-FOUND u3)
(define-constant ERR-INSUFFICIENT-LIQUIDITY u4)
(define-constant ERR-EXCESSIVE-SLIPPAGE u5)
(define-constant ERR-ZERO-QUANTITY u6)
(define-constant ERR-PROTECTION-PERIOD-ACTIVE u7)
(define-constant ERR-INVALID-PARAMETER u8)
(define-constant ERR-MATH-ERROR u9)

(define-constant PRECISION-FACTOR u10000)
(define-constant INITIAL-LIQUIDITY-TOKENS (pow u10 u18))
(define-constant BLOCKS-PER-DAY u144) ;; Approximately 144 blocks per day in Stacks

;; Protocol configuration
(define-data-var protocol-fee-basis-points uint u30) ;; 0.3% fee (30 basis points)
(define-data-var full-protection-weeks uint u9)      ;; 9 weeks for full protection

;; Data structures
(define-map liquidity-pools { token-a: principal, token-b: principal } 
  { 
    total-liquidity: uint,
    reserve-a: uint,
    reserve-b: uint,
    token-a-decimals: uint,
    token-b-decimals: uint,
    creation-height: uint
  }
)

(define-map liquidity-positions 
  { 
    pool-id: { token-a: principal, token-b: principal }, 
    provider: principal 
  } 
  {
    shares-owned: uint,
    initial-price-ratio: uint,
    entry-block-height: uint,
    token-a-contributed: uint,
    token-b-contributed: uint
  }
)

;; LiquidShield LP token
(define-fungible-token liquidity-shares)

;; Administrative functions
(define-data-var protocol-admin principal tx-sender)

(define-read-only (get-protocol-admin)
  (var-get protocol-admin)
)

;; Helper function for min comparison
(define-read-only (get-min (a uint) (b uint))
  (if (<= a b) a b)
)

(define-public (transfer-admin-rights (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-admin)) (err ERR-UNAUTHORIZED-ACCESS))
    (var-set protocol-admin new-admin)
    (ok new-admin)
  )
)

(define-public (update-protocol-fee (new-fee-basis-points uint))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-admin)) (err ERR-UNAUTHORIZED-ACCESS))
    (asserts! (< new-fee-basis-points u100) (err ERR-INVALID-PARAMETER))  ;; Fee must be less than 1%
    (var-set protocol-fee-basis-points new-fee-basis-points)
    (ok new-fee-basis-points)
  )
)

(define-public (update-protection-period (new-weeks-period uint))
  (begin
    (asserts! (is-eq tx-sender (var-get protocol-admin)) (err ERR-UNAUTHORIZED-ACCESS))
    (asserts! (> new-weeks-period u0) (err ERR-INVALID-PARAMETER))
    (var-set full-protection-weeks new-weeks-period)
    (ok new-weeks-period)
  )
)

;; Math helper functions
(define-read-only (square-root-iter-helper (num uint) (guess uint) (iterations-left uint))
  (let
    (
      (new-guess (/ (+ guess (/ num guess)) u2))
    )
    {
      new-guess: new-guess,
      should-continue: (and (> iterations-left u0) (not (is-eq new-guess guess)))
    }
  )
)

;; Square-root-integer function that returns a consistent type
(define-read-only (square-root-integer (n uint))
  (if (is-eq n u0)
    u0
    (get new-guess (square-root-manual-iterate n))
  )
)

;; Manually iterate the square root calculation to avoid recursion
(define-read-only (square-root-manual-iterate (num uint))
  (let
    (
      (initial-guess (/ (+ num u1) u2))
      (iter-1 (square-root-iter-helper num initial-guess u20))
      (should-continue-1 (get should-continue iter-1))
      (guess-1 (get new-guess iter-1))

      (iter-2 (if should-continue-1 
                (square-root-iter-helper num guess-1 u19) 
                { new-guess: guess-1, should-continue: false }))
      (should-continue-2 (get should-continue iter-2))
      (guess-2 (get new-guess iter-2))

      (iter-3 (if should-continue-2 
                (square-root-iter-helper num guess-2 u18) 
                { new-guess: guess-2, should-continue: false }))
      (should-continue-3 (get should-continue iter-3))
      (guess-3 (get new-guess iter-3))

      (iter-4 (if should-continue-3 
                (square-root-iter-helper num guess-3 u17) 
                { new-guess: guess-3, should-continue: false }))
      (should-continue-4 (get should-continue iter-4))
      (guess-4 (get new-guess iter-4))

      (iter-5 (if should-continue-4 
                (square-root-iter-helper num guess-4 u16) 
                { new-guess: guess-4, should-continue: false }))
      (guess-5 (get new-guess iter-5))
    )
    { new-guess: guess-5 }
  )
)

(define-read-only (calculate-normalized-price-ratio (amount-a uint) (amount-b uint) (decimals-a uint) (decimals-b uint))
  (/ (* amount-a (pow u10 decimals-b)) (* amount-b (pow u10 decimals-a)))
)

;; Pool management functions
(define-public (initialize-pool 
    (token-a <ft-trait>) 
    (token-b <ft-trait>) 
    (initial-amount-a uint) 
    (initial-amount-b uint)
    (decimals-a uint)
    (decimals-b uint))
  (let 
    (
      (token-a-address (contract-of token-a))
      (token-b-address (contract-of token-b))
      (pool-exists (is-some (map-get? liquidity-pools { token-a: token-a-address, token-b: token-b-address })))
      (current-block-height block-height)
    )
    
    ;; Check conditions
    (asserts! (not pool-exists) (err ERR-POOL-ALREADY-EXISTS))
    (asserts! (> initial-amount-a u0) (err ERR-ZERO-QUANTITY))
    (asserts! (> initial-amount-b u0) (err ERR-ZERO-QUANTITY))
    
    ;; Transfer tokens to contract
    (try! (contract-call? token-a transfer initial-amount-a tx-sender (as-contract tx-sender) none))
    (try! (contract-call? token-b transfer initial-amount-b tx-sender (as-contract tx-sender) none))
    
    ;; Set up pool
    (map-set liquidity-pools { token-a: token-a-address, token-b: token-b-address }
      { 
        total-liquidity: INITIAL-LIQUIDITY-TOKENS,
        reserve-a: initial-amount-a,
        reserve-b: initial-amount-b,
        token-a-decimals: decimals-a,
        token-b-decimals: decimals-b,
        creation-height: current-block-height
      }
    )
    
    ;; Record liquidity position
    (map-set liquidity-positions 
      { pool-id: { token-a: token-a-address, token-b: token-b-address }, provider: tx-sender }
      {
        shares-owned: INITIAL-LIQUIDITY-TOKENS,
        initial-price-ratio: (calculate-normalized-price-ratio initial-amount-a initial-amount-b decimals-a decimals-b),
        entry-block-height: current-block-height,
        token-a-contributed: initial-amount-a,
        token-b-contributed: initial-amount-b
      }
    )
    
    ;; Mint LP tokens to provider
    (ft-mint? liquidity-shares INITIAL-LIQUIDITY-TOKENS tx-sender)
  )
)

;; Liquidity provider functions
(define-public (provide-liquidity 
    (token-a <ft-trait>) 
    (token-b <ft-trait>)
    (amount-a uint)
    (amount-b uint)
    (minimum-shares uint))
  (let
    (
      (token-a-address (contract-of token-a))
      (token-b-address (contract-of token-b))
      (pool (default-to 
        { 
          total-liquidity: u0, 
          reserve-a: u0, 
          reserve-b: u0, 
          token-a-decimals: u0,
          token-b-decimals: u0,
          creation-height: u0
        } 
        (map-get? liquidity-pools { token-a: token-a-address, token-b: token-b-address })))
      (provider-key { pool-id: { token-a: token-a-address, token-b: token-b-address }, provider: tx-sender })
      (existing-position (map-get? liquidity-positions provider-key))
      (current-block-height block-height)
    )
    
    ;; Check conditions
    (asserts! (> (get total-liquidity pool) u0) (err ERR-POOL-NOT-FOUND))
    (asserts! (> amount-a u0) (err ERR-ZERO-QUANTITY))
    (asserts! (> amount-b u0) (err ERR-ZERO-QUANTITY))
    
    ;; Calculate proportional values
    (let
      (
        (reserve-a (get reserve-a pool))
        (reserve-b (get reserve-b pool))
        (pool-liquidity (get total-liquidity pool))

        ;; Calculate square roots for geometric mean
        (sqrt-product-amounts (square-root-integer (* amount-a amount-b)))
        (sqrt-product-reserves (square-root-integer (* reserve-a reserve-b)))
        
        ;; Using geometric mean for balanced incentives
        (new-shares (/ (* pool-liquidity sqrt-product-amounts) sqrt-product-reserves))
        
        ;; Calculate current price ratio
        (current-price-ratio (calculate-normalized-price-ratio 
                               amount-a amount-b 
                               (get token-a-decimals pool) 
                               (get token-b-decimals pool)))
        
        ;; Update provider position
        (updated-position (if (is-some existing-position)
          {
            shares-owned: (+ new-shares (get shares-owned (unwrap-panic existing-position))),
            initial-price-ratio: current-price-ratio,  ;; Update to new entry price
            entry-block-height: current-block-height,  ;; Reset protection clock
            token-a-contributed: (+ amount-a (get token-a-contributed (unwrap-panic existing-position))),
            token-b-contributed: (+ amount-b (get token-b-contributed (unwrap-panic existing-position)))
          }
          {
            shares-owned: new-shares,
            initial-price-ratio: current-price-ratio,
            entry-block-height: current-block-height,
            token-a-contributed: amount-a,
            token-b-contributed: amount-b
          }
        ))
      )
      
      ;; Check minimum shares requirement
      (asserts! (>= new-shares minimum-shares) (err ERR-EXCESSIVE-SLIPPAGE))
      
      ;; Transfer tokens to contract
      (try! (contract-call? token-a transfer amount-a tx-sender (as-contract tx-sender) none))
      (try! (contract-call? token-b transfer amount-b tx-sender (as-contract tx-sender) none))
      
      ;; Update pool
      (map-set liquidity-pools { token-a: token-a-address, token-b: token-b-address }
        { 
          total-liquidity: (+ pool-liquidity new-shares),
          reserve-a: (+ reserve-a amount-a),
          reserve-b: (+ reserve-b amount-b),
          token-a-decimals: (get token-a-decimals pool),
          token-b-decimals: (get token-b-decimals pool),
          creation-height: (get creation-height pool)
        }
      )
      
      ;; Update provider position
      (map-set liquidity-positions provider-key updated-position)
      
      ;; Mint LP tokens to provider
      (ft-mint? liquidity-shares new-shares tx-sender)
    )
  )
)

(define-public (withdraw-liquidity
    (token-a <ft-trait>)
    (token-b <ft-trait>)
    (shares-to-burn uint)
    (minimum-token-a uint)
    (minimum-token-b uint))
  (let
    (
      (token-a-address (contract-of token-a))
      (token-b-address (contract-of token-b))
      (pool (default-to 
        { 
          total-liquidity: u0, 
          reserve-a: u0, 
          reserve-b: u0, 
          token-a-decimals: u0,
          token-b-decimals: u0,
          creation-height: u0
        } 
        (map-get? liquidity-pools { token-a: token-a-address, token-b: token-b-address })))
      (provider-key { pool-id: { token-a: token-a-address, token-b: token-b-address }, provider: tx-sender })
      (provider-position (default-to 
        {
          shares-owned: u0,
          initial-price-ratio: u0,
          entry-block-height: u0,
          token-a-contributed: u0,
          token-b-contributed: u0
        }
        (map-get? liquidity-positions provider-key)))
      (pool-total-shares (get total-liquidity pool))
      (provider-total-shares (get shares-owned provider-position))
      (current-block-height block-height)
    )
    
    ;; Check conditions
    (asserts! (> pool-total-shares u0) (err ERR-POOL-NOT-FOUND))
    (asserts! (<= shares-to-burn provider-total-shares) (err ERR-INSUFFICIENT-LIQUIDITY))
    
    ;; Calculate withdrawal amounts with impermanent loss protection
    (let
      (
        (withdraw-percentage (/ (* shares-to-burn PRECISION-FACTOR) provider-total-shares))
        (base-token-a (/ (* (get token-a-contributed provider-position) withdraw-percentage) PRECISION-FACTOR))
        (base-token-b (/ (* (get token-b-contributed provider-position) withdraw-percentage) PRECISION-FACTOR))
        
        ;; Calculate current pool values
        (pool-reserve-a (get reserve-a pool))
        (pool-reserve-b (get reserve-b pool))
        (pool-proportion (/ (* shares-to-burn PRECISION-FACTOR) pool-total-shares))
        (current-token-a (/ (* pool-reserve-a pool-proportion) PRECISION-FACTOR))
        (current-token-b (/ (* pool-reserve-b pool-proportion) PRECISION-FACTOR))
        
        ;; Calculate impermanent loss protection
        (weeks-held (/ (- current-block-height (get entry-block-height provider-position)) 
                      (* BLOCKS-PER-DAY u7)))  ;; Convert blocks to weeks
        (protection-percentage (get-min PRECISION-FACTOR 
                                   (/ (* weeks-held PRECISION-FACTOR) (var-get full-protection-weeks))))
        
        ;; Entry price vs current price
        (entry-price-ratio (get initial-price-ratio provider-position))
        (current-price-ratio (calculate-normalized-price-ratio 
                               pool-reserve-a pool-reserve-b 
                               (get token-a-decimals pool) (get token-b-decimals pool)))
        
        ;; Calculate compensation for impermanent loss
        (token-a-shortfall (if (< current-token-a base-token-a) 
                             (/ (* (- base-token-a current-token-a) protection-percentage) PRECISION-FACTOR) 
                             u0))
        (token-b-shortfall (if (< current-token-b base-token-b) 
                             (/ (* (- base-token-b current-token-b) protection-percentage) PRECISION-FACTOR) 
                             u0))
        
        (final-token-a (+ current-token-a token-a-shortfall))
        (final-token-b (+ current-token-b token-b-shortfall))
        
        ;; Flag indicating if protection was applied
        (protection-applied (> (+ token-a-shortfall token-b-shortfall) u0))
      )
      
      ;; Check minimum amounts
      (asserts! (>= final-token-a minimum-token-a) (err ERR-EXCESSIVE-SLIPPAGE))
      (asserts! (>= final-token-b minimum-token-b) (err ERR-EXCESSIVE-SLIPPAGE))
      
      ;; Burn LP tokens
      (try! (ft-burn? liquidity-shares shares-to-burn tx-sender))
      
      ;; Update pool
      (map-set liquidity-pools { token-a: token-a-address, token-b: token-b-address }
        { 
          total-liquidity: (- pool-total-shares shares-to-burn),
          reserve-a: (- pool-reserve-a final-token-a),
          reserve-b: (- pool-reserve-b final-token-b),
          token-a-decimals: (get token-a-decimals pool),
          token-b-decimals: (get token-b-decimals pool),
          creation-height: (get creation-height pool)
        }
      )
      
      ;; Update provider position
      (if (is-eq shares-to-burn provider-total-shares)
        (map-delete liquidity-positions provider-key)
        (map-set liquidity-positions provider-key
          {
            shares-owned: (- provider-total-shares shares-to-burn),
            initial-price-ratio: (get initial-price-ratio provider-position),
            entry-block-height: (get entry-block-height provider-position),
            token-a-contributed: (- (get token-a-contributed provider-position) base-token-a),
            token-b-contributed: (- (get token-b-contributed provider-position) base-token-b)
          }
        )
      )
      
      ;; Transfer tokens to user
      (as-contract (begin
        (try! (contract-call? token-a transfer final-token-a (as-contract tx-sender) tx-sender none))
        (try! (contract-call? token-b transfer final-token-b (as-contract tx-sender) tx-sender none))
        (ok { 
          token-a-amount: final-token-a, 
          token-b-amount: final-token-b, 
          protection-applied: protection-applied 
        })
      ))
    )
  )
)

;; Swap functions
(define-public (swap-token-a-for-b
    (token-a <ft-trait>)
    (token-b <ft-trait>)
    (input-amount uint)
    (minimum-output-amount uint))
  (let
    (
      (token-a-address (contract-of token-a))
      (token-b-address (contract-of token-b))
      (pool (default-to 
        { 
          total-liquidity: u0, 
          reserve-a: u0, 
          reserve-b: u0, 
          token-a-decimals: u0,
          token-b-decimals: u0,
          creation-height: u0
        } 
        (map-get? liquidity-pools { token-a: token-a-address, token-b: token-b-address })))
      (reserve-a (get reserve-a pool))
      (reserve-b (get reserve-b pool))
      (fee-basis-points (var-get protocol-fee-basis-points))
      (input-after-fee (- input-amount (/ (* input-amount fee-basis-points) u1000)))
      (invariant-k (* reserve-a reserve-b))
      (new-reserve-a (+ reserve-a input-amount))
      (new-reserve-b (/ invariant-k new-reserve-a))
      (output-amount (- reserve-b new-reserve-b))
    )
    
    ;; Check conditions
    (asserts! (> (get total-liquidity pool) u0) (err ERR-POOL-NOT-FOUND))
    (asserts! (> input-amount u0) (err ERR-ZERO-QUANTITY))
    (asserts! (>= output-amount minimum-output-amount) (err ERR-EXCESSIVE-SLIPPAGE))
    
    ;; Transfer token-a from user to contract
    (try! (contract-call? token-a transfer input-amount tx-sender (as-contract tx-sender) none))
    
    ;; Update pool reserves
    (map-set liquidity-pools { token-a: token-a-address, token-b: token-b-address }
      { 
        total-liquidity: (get total-liquidity pool),
        reserve-a: new-reserve-a,
        reserve-b: new-reserve-b,
        token-a-decimals: (get token-a-decimals pool),
        token-b-decimals: (get token-b-decimals pool),
        creation-height: (get creation-height pool)
      }
    )
    
    ;; Transfer token-b to user
    (as-contract 
      (begin
        (try! (contract-call? token-b transfer output-amount (as-contract tx-sender) tx-sender none))
        (ok { input-amount: input-amount, output-amount: output-amount })
      )
    )
  )
)

(define-public (swap-token-b-for-a
    (token-a <ft-trait>)
    (token-b <ft-trait>)
    (input-amount uint)
    (minimum-output-amount uint))
  (let
    (
      (token-a-address (contract-of token-a))
      (token-b-address (contract-of token-b))
      (pool (default-to 
        { 
          total-liquidity: u0, 
          reserve-a: u0, 
          reserve-b: u0, 
          token-a-decimals: u0,
          token-b-decimals: u0,
          creation-height: u0
        } 
        (map-get? liquidity-pools { token-a: token-a-address, token-b: token-b-address })))
      (reserve-a (get reserve-a pool))
      (reserve-b (get reserve-b pool))
      (fee-basis-points (var-get protocol-fee-basis-points))
      (input-after-fee (- input-amount (/ (* input-amount fee-basis-points) u1000)))
      (invariant-k (* reserve-a reserve-b))
      (new-reserve-b (+ reserve-b input-amount))
      (new-reserve-a (/ invariant-k new-reserve-b))
      (output-amount (- reserve-a new-reserve-a))
    )
    
    ;; Check conditions
    (asserts! (> (get total-liquidity pool) u0) (err ERR-POOL-NOT-FOUND))
    (asserts! (> input-amount u0) (err ERR-ZERO-QUANTITY))
    (asserts! (>= output-amount minimum-output-amount) (err ERR-EXCESSIVE-SLIPPAGE))
    
    ;; Transfer token-b from user to contract
    (try! (contract-call? token-b transfer input-amount tx-sender (as-contract tx-sender) none))
    
    ;; Update pool reserves
    (map-set liquidity-pools { token-a: token-a-address, token-b: token-b-address }
      { 
        total-liquidity: (get total-liquidity pool),
        reserve-a: new-reserve-a,
        reserve-b: new-reserve-b,
        token-a-decimals: (get token-a-decimals pool),
        token-b-decimals: (get token-b-decimals pool),
        creation-height: (get creation-height pool)
      }
    )
    
    ;; Transfer token-a to user
    (as-contract 
      (begin
        (try! (contract-call? token-a transfer output-amount (as-contract tx-sender) tx-sender none))
        (ok { input-amount: input-amount, output-amount: output-amount })
      )
    )
  )
)

;; Utility and view functions
(define-read-only (get-pool-details (token-a principal) (token-b principal))
  (map-get? liquidity-pools { token-a: token-a, token-b: token-b })
)

(define-read-only (get-liquidity-position (token-a principal) (token-b principal) (provider principal))
  (map-get? liquidity-positions { pool-id: { token-a: token-a, token-b: token-b }, provider: provider })
)

(define-read-only (get-protection-vesting-period)
  (var-get full-protection-weeks)
)

(define-read-only (get-current-fee)
  (var-get protocol-fee-basis-points)
)

(define-read-only (calculate-swap-a-to-b-output (token-a principal) (token-b principal) (input-amount uint))
  (let
    (
      (pool (default-to 
        { 
          total-liquidity: u0, 
          reserve-a: u0, 
          reserve-b: u0, 
          token-a-decimals: u0,
          token-b-decimals: u0,
          creation-height: u0
        } 
        (map-get? liquidity-pools { token-a: token-a, token-b: token-b })))
      (reserve-a (get reserve-a pool))
      (reserve-b (get reserve-b pool))
      (fee-basis-points (var-get protocol-fee-basis-points))
      (input-after-fee (- input-amount (/ (* input-amount fee-basis-points) u1000)))
      (invariant-k (* reserve-a reserve-b))
      (new-reserve-a (+ reserve-a input-after-fee))
      (new-reserve-b (/ invariant-k new-reserve-a))
      (output-amount (- reserve-b new-reserve-b))
      (price-impact-bps (/ (* (- new-reserve-b reserve-b) PRECISION-FACTOR) reserve-b))
    )
    (if (> (get total-liquidity pool) u0)
      (ok { output-amount: output-amount, price-impact-bps: price-impact-bps })
      (err ERR-POOL-NOT-FOUND)
    )
  )
)