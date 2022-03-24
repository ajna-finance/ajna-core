# Open `brownie console` with SDK
```bash
brownie console

from sdk import *

sdk = create_default_sdk()

sdk = create_sdk_for_mkr_dai_pool()

mkr_dai_pool = sdk.get_pool(MKR_ADDRESS, DAI_ADDRESS)
```

## Create custom SDK
```bash
brownie console

sdk = create_sdk(
        MKR_ADDRESS,
        MKR_RESERVE_ADDRESS,
        10 * 10**18,
        DAI_ADDRESS,
        DAI_RESERVE_ADDRESS,
        10_000 * 10**18,
        number_of_lenders,
        number_of_borrowers,
    )


protocol_definition = (
    AjnaProtocolStateDefinitionBuilder()
    .add_token(DAI_ADDRESS, DAI_RESERVE_ADDRESS)
    .add_token(COMP_ADDRESS, COMP_RESERVE_ADDRESS)
    .deploy_pool(COMP_ADDRESS, DAI_ADDRESS)
)

protocol_definition.with_borrowers(10).with_token(COMP_ADDRESS, 20_000 * 10**18).add()
protocol_definition.with_lenders(5).with_token(DAI_ADDRESS, 600_000 * 10**18).add()

sdk = AjnaSdk(protocol_definition.build())
```

# Deploy ERC20 pool using SDK
```bash
collateral_address = MKR_ADDRESS
quote_token_address = DAI_ADDRESS

pool = sdk.deploy_erc20_pool(collateral_address, quote_token_address)
```

# Get ERC20 pool wrapper using SDK
```bash
collateral_address = MKR_ADDRESS
quote_token_address = DAI_ADDRESS

pool = sdk.get_pool(collateral_address, quote_token_address)

# or you can force deploy if pool is not deployed
pool = sdk.get_pool(collateral_address, quote_token_address, force_deploy=True)
```

# Get ERC20 pool contract from pool wrapper
```bash
pool_contract = pool.get_contract()
```

# Interact with ERC20 pool using SDK
## Deposit quote token from lender
```bash
pool = sdk.get_pool(collateral_address, quote_token_address)
pool.deposit_quote_token(amount, price, lender_index)
```

## Withdraw quote token from pool as lender
```bash
pool = sdk.get_pool(collateral_address, quote_token_address)
pool.withdraw_quote_token(amount, price, lender_index)
```

## Deposit collateral token from pool as borrower
```bash
pool = sdk.get_pool(collateral_address, quote_token_address)
pool.deposit_collateral(amount, price, borrower_index)
```

## Withdraw collateral token from pool as borrower
```bash
pool.withdraw_collateral(amount, borrower_index)
```

## Borrow from pool as borrower
```bash
pool = sdk.get_pool(collateral_address, quote_token_address)
pool.borrow(amount, price, borrower_index)
```

## Repay to pool as borrower
```bash
pool = sdk.get_pool(collateral_address, quote_token_address)
pool.repay(amount, price, borrower_index)
```

# Token wrapper
## Get token wrapper
```bash
collateral_token = sdk.get_token(pool.collateral)
quote_token = sdk.get_token(pool.quoteToken)
```

## Add new token to the SDK:
```bash
token_address = "0x6b175474e89094c44da98b954eedeac495271d0f"
address_that_have_loads_of_tokens = "0xbebc44782c7db0a1a60cb6fe97d0b483032ff1c7"

token = sdk.add_token(token_address, address_that_have_loads_of_tokens)
```

## Top up token to borrower/lender
```bash
borrower = sdk.get_borrower(0)
token = sdk.get_token(pool.collateral)

token.top_up(borrower, 100 * 10**18)
token.approve_max(pool, borrower)
```

