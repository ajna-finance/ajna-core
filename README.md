# Ajna contracts

## Development
### Requirements
- `python` 3.0+
- `eth-brownie` 1.18.1+
- `ganache` 7.0+ is required.
- `foundry` aka `forge` 0.2.0+ is required.

### Foundry setup
- Install Foundry [instructions](https://github.com/gakonst/foundry/blob/master/README.md#installation)
- Install the [foundry](https://github.com/gakonst/foundry) toolchain installer (`foundryup`):
```bash
curl -L https://foundry.paradigm.xyz | bash
```
- To get the latest `forge` binaries, run:
```bash
foundryup
```

### Brownie setup
- Install Brownie [instructions](https://eth-brownie.readthedocs.io/en/stable/install.html)

#### Brownie with Ganache
- Install Ganache
```bash
npm i -g ganache
```

#### Brownie with Hardhat
- Install Hardhat
```bash
npm install --save-dev hardhat
```
- To use `hardhat` instead of `ganache`, add `--network hardhat-fork` to override the configured network

Caveats:
- Brownie does not support mining empty blocks using `chain.mine`
- Brownie does not report custom errors raised by the contract when using Hardhat

### Project Setup
- Make a copy of .env.example and name it .env. Add the values for
  - `ETHERSCAN_TOKEN` - required by brownie to verify contract sources
  - `WEB3_INFURA_PROJECT_ID` - required by brownie to fork chain
  - `ETH_RPC_URL` - required by forge to fork chain
- run
```bash
make all
```

## Tests
### Forge tests
- run tests without the gas load tests (good for checking validity)
```bash
make test
```
- run tests with gas report, used for gas comparison of changes:
```bash
make test-with-gas-report
```
- run load tests with gas report, used for gas comparison of changes (takes longer to execute):
```bash
make test-load
```
- generate code coverage report:
```bash
make coverage
```

### Brownie tests
- run integration tests:
```bash
brownie test
```
- to view `stdout` on long-running tests, use `brownie test -s`.
#### Debugging Brownie integration tests
- to drop into the console upon test failure:
```bash
brownie test --interactive
```
- From there, you can pull the last transaction using `tx=history[-1]`, followed by `tx.events` to debug.


## Contract size
To display contract code sizes run:
```bash
forge build --sizes
```
or
```bash
brownie compile --size
```


## Slither Analyzer

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
