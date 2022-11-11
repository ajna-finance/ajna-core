## Run testnet setup

- start brownie console from root dir of the repo
```bash
brownie console
```
- in brownie console run setup script
```bash
run('ajna_setup')
```

Running setup script will create a basic setup for testing basic interaction with pools by:
- deploying ERC20 and ERC721 pool factories and generating `.env` file with deployed addresses, lender and borrower addresses and private keys and collateral / quote addresses
- funding test addresses with DAI, COMP and Bored Apes NFTs. Addresses and balances to fund are set in `ajna-setup.json` file.
Tokens configuration section contains addresses of DAI contract and reserve, COMP contract and reserve and Bored Ape contract. (sample provided for mainnet)
Accounts configuration section contains test addresses and balances to fund.
For ERC20 tokens the number of tokens to be funded should be provided.
For ERC721 tokens the id of token to be funded should be provided.
```
{
    "0x66aB6D9362d4F35596279692F0251Db635165871": {
        "DAI": 11000,
        "COMP": 100,
        "BAYC": [5, 6, 7]
    },
    "0x33A4622B82D4c04a53e170c638B944ce27cffce3": {
        "DAI": 22000,
        "COMP": 50,
        "BAYC": [8, 9, 10]
    }
}
```

- in a different window (do not close brownie console) create the ERC20 pool by running
```bash
npm install
node erc20PoolCreation.js
```
then run basic pool interactions scenario:
```bash
npm install
node erc20PoolInteractions.js
```
- lender lends 10000 quote tokens
- borrower pledge 100 collateral and borrows 1000 quote tokens
- borrow repay and pull collateral
- lender removes all their quote tokens
