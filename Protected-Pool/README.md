# LiquidShield: Automated Market Maker with Impermanent Loss Protection

LiquidShield is a decentralized exchange protocol built on the Stacks blockchain that provides liquidity providers with time-based protection against impermanent loss.

## Overview

LiquidShield is an innovative automated market maker (AMM) that addresses one of the primary concerns for liquidity providers in decentralized finance: impermanent loss. By implementing a time-based protection mechanism, LiquidShield encourages longer-term liquidity provision and creates a more sustainable DeFi ecosystem.

## Key Features

- **Impermanent Loss Protection**: Protection against impermanent loss that grows over time, reaching 100% after the full protection period (default: 9 weeks)
- **Geometric Mean Pricing**: Uses geometric mean for calculating liquidity shares, providing balanced incentives
- **Low Fee Structure**: 0.3% swap fee by default (configurable by protocol admin)
- **Fungible Liquidity Tokens**: Standard SIP-010 compliant tokens representing liquidity positions

## Smart Contract Functions

### Administrative Functions

- `transfer-admin-rights`: Transfers protocol admin rights to a new address
- `update-protocol-fee`: Updates the protocol fee (basis points)
- `update-protection-period`: Updates the full protection period (in weeks)

### Liquidity Provider Functions

- `initialize-pool`: Creates a new token pair liquidity pool
- `provide-liquidity`: Adds liquidity to an existing pool
- `withdraw-liquidity`: Removes liquidity with impermanent loss protection

### Swap Functions

- `swap-token-a-for-b`: Swaps token A for token B
- `swap-token-b-for-a`: Swaps token B for token A

### Utility and View Functions

- `get-pool-details`: Returns details about a specific pool
- `get-liquidity-position`: Returns details about a liquidity provider's position
- `get-protection-vesting-period`: Returns the full protection period in weeks
- `get-current-fee`: Returns the current protocol fee in basis points
- `calculate-swap-a-to-b-output`: Calculates the expected output amount for a token swap

## Impermanent Loss Protection

LiquidShield's core innovation is its impermanent loss protection mechanism:

1. When a user provides liquidity, the system records:
   - The initial price ratio between tokens
   - The entry block height (for time calculation)
   - Amount of each token contributed

2. When withdrawing liquidity:
   - The system calculates how long the liquidity has been provided (in weeks)
   - Protection percentage increases linearly, reaching 100% after the full protection period
   - Any shortfall in token value compared to the initial contribution is compensated proportionally to the protection percentage

3. The longer liquidity remains in the pool, the greater the protection against impermanent loss.

## Technical Implementation

- Built on the Stacks blockchain
- Uses SIP-010 fungible token trait for token operations
- Implements square root calculations for geometric mean pricing
- Utilizes precision factors for decimal calculations

## Error Codes

- `ERR-UNAUTHORIZED-ACCESS`: Access denied for non-admin operations
- `ERR-POOL-ALREADY-EXISTS`: Pool for the token pair already exists
- `ERR-POOL-NOT-FOUND`: Pool for the token pair doesn't exist
- `ERR-INSUFFICIENT-LIQUIDITY`: Insufficient liquidity for the operation
- `ERR-EXCESSIVE-SLIPPAGE`: Slippage exceeds specified limit
- `ERR-ZERO-QUANTITY`: Zero quantity provided
- `ERR-PROTECTION-PERIOD-ACTIVE`: Protection period still active
- `ERR-INVALID-PARAMETER`: Invalid parameter provided
- `ERR-MATH-ERROR`: Math calculation error

## Usage Examples

1. **Initialize a new pool**:
   ```clarity
   (contract-call? .liquidshield initialize-pool .token-a .token-b u1000000 u1000000 u6 u6)
   ```

2. **Add liquidity to an existing pool**:
   ```clarity
   (contract-call? .liquidshield provide-liquidity .token-a .token-b u500000 u500000 u450000)
   ```

3. **Swap tokens**:
   ```clarity
   (contract-call? .liquidshield swap-token-a-for-b .token-a .token-b u100000 u95000)
   ```

4. **Withdraw liquidity**:
   ```clarity
   (contract-call? .liquidshield withdraw-liquidity .token-a .token-b u750000 u700000 u700000)
   ```

## Configuration Constants

- `PRECISION-FACTOR`: 10000 (for decimal calculations)
- `INITIAL-LIQUIDITY-TOKENS`: 10^18 (initial liquidity token supply)
- `BLOCKS-PER-DAY`: 144 (approximate blocks per day in Stacks)
- Default protocol fee: 0.3% (30 basis points)
- Default full protection period: 9 weeks

## Security Considerations

- Calculations use precision factors to handle decimal values
- Square root calculations use an iterative approach to avoid recursion limitations
- Price ratio normalization accounts for different token decimals