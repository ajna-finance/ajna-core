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
