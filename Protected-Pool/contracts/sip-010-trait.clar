;; SIP-010: Fungible Token Standard
;; This trait defines the standard interface for fungible tokens on Stacks

(define-trait sip-010-trait
  (
    ;; Transfer tokens to a specified principal
    ;; @param amount: the amount of tokens to transfer
    ;; @param sender: the principal sending the tokens
    ;; @param recipient: the principal receiving the tokens
    ;; @param memo: an optional memo for the transfer
    ;; @returns: Result with success status or error code
    (transfer (uint principal principal (optional (buff 34))) (response bool uint))

    ;; Get the token balance for a specified principal
    ;; @param who: the principal to check balance for
    ;; @returns: the balance as an uint
    (get-balance (principal) (response uint uint))

    ;; Get the total supply of tokens
    ;; @returns: the total supply as an uint
    (get-total-supply () (response uint uint))

    ;; Get the human-readable name of the token
    ;; @returns: the name as a UTF-8 string
    (get-name () (response (string-utf8 32) uint))

    ;; Get the symbol/ticker of the token
    ;; @returns: the symbol as a UTF-8 string
    (get-symbol () (response (string-utf8 32) uint))

    ;; Get the number of decimals used by the token
    ;; @returns: the number of decimals as an uint
    (get-decimals () (response uint uint))

    ;; Get the token URI for metadata
    ;; @returns: the URI as an optional string
    (get-token-uri () (response (optional (string-utf8 256)) uint))
  )
)