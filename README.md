# ajna contracts

Ajna contracts

# Development

Install Foundry [instructions](https://github.com/gakonst/foundry/blob/master/README.md#installation)  then, install the [foundry](https://github.com/gakonst/foundry) toolchain installer (`foundryup`) with:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

To get the latest `forge` or `cast` binaries, tun

```bash
foundryup
```

#### Project Setup

```bash
make all
```

#### Run Tests

```bash
make test
```

## Brownie integration

`eth-brownie` 1.18.1+ and `ganache` 7.0+ is required.
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

### Brownie integration tests

```bash
brownie test
```
  - To view `stdout` on long-running tests, use `brownie test -s`.

#### Debugging Brownie integration tests

To drop into the console upon test failure:
```bash
brownie test --interactive
```

From there, you can pull the last transaction using `tx=history[-1]`, followed by `tx.events` to debug.
