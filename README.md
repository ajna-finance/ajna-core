# Ajna contracts

## Development
### Requirements
- `python` 3.0+
- `eth-brownie` 1.18.1+
- `ganache` 7.0+ is required.
- `foundry` aka `forge` 0.2.0+ is required.

## Foundry aka forge integration
Install Foundry [instructions](https://github.com/gakonst/foundry/blob/master/README.md#installation)

Install the [foundry](https://github.com/gakonst/foundry) toolchain installer (`foundryup`) with:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

To get the latest `forge` or `cast` binaries, run:

```bash
foundryup
```

### Project Setup

```bash
make all
```

### Run Tests

`Forge test` without the gas load tests (good for checking validity)
```bash
make test
```

Gas tests, used for gas comparison of changes:
```bash
forge test -vv --gas-report
```

## Run Brownie
- Install Brownie [instructions](https://eth-brownie.readthedocs.io/en/stable/install.html)
- Make a copy of .env.example and name it .env. Add the values for ETHERSCAN_TOKEN and WEB3_INFURA_PROJECT_ID
- Run `brownie console`
- Install ganache `npm i -g ganache`

### Brownie with Hardhat
- Install Hardhat `npm install --save-dev hardhat`
- To use `hardhat` instead of `ganache`, add `--network hardhat-fork` to override the configured network

Caveats:
- Brownie does not support mining empty blocks using `chain.mine`
- Brownie does not report custom errors raised by the contract when using Hardhat

### Brownie tests

Integration:
```bash
brownie test
```

Contract size:
```bash
brownie compile --size
```
To view `stdout` on long-running tests, use `brownie test -s`.

### Debugging Brownie integration tests

To drop into the console upon test failure:
```bash
brownie test --interactive
```

From there, you can pull the last transaction using `tx=history[-1]`, followed by `tx.events` to debug.


## Run Slither Analyzer

- Install Slither
```bash
pip install slither-analyzer
```
- Make sure the default `solc` version is set to the same version as contracts (currently 0.8.14). This can be done by installing and using `solc-select`:
```bash
pip install solc-select && solc-select install 0.8.14 && solc-select use 0.8.14
```
- Run `analyze`

```bash
make analyze
```


## Run SDK testnet setup

- start brownie console
```bash
brownie console
```
- in brownie console run SDK setup script
```bash
run('sdk_setup')
```

Running SDK setup script will create a basic setup for testing SDK by:
- deploying ERC20 and ERC721 pool factories and generating `brownie-out/ajna-sdk.json` config file with deployed addresses
```
{
    "erc20factory": "0x8b1B440724DCe2EE9779B58af841Ec59F545838B",
    "erc721factory": "0xC6D563d5c2243b27e7294511063f563ED701EA2C"
}
```
- funding test addresses with DAI, MKR and Bored Apes NFTs. Addresses and balances to fund are set in `sdk-setup.json` file.
Tokens configuration section contains addresses of DAI contract and reserve, MKR contract and reserve and Bored Ape contract. (sample provided for mainnet)
Accounts configuration section contains test addresses and balances to fund.
For ERC20 tokens the number of tokens to be funded should be provided.
For ERC721 tokens the id of token to be funded should be provided.
```
{
    "0x66aB6D9362d4F35596279692F0251Db635165871": {
        "DAI": 11000,
        "MKR": 100,
        "BAYC": [5, 6, 7]
    },
    "0x33A4622B82D4c04a53e170c638B944ce27cffce3": {
        "DAI": 22000,
        "MKR": 50,
        "BAYC": [8, 9, 10]
    }
}
```
