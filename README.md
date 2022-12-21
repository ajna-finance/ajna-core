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

## Licensing
Ajna is under [BUSL license](https://github.com/ajna-finance/contracts/blob/develop/LICENSE) with the 
following exceptions:
- To facilitate integrations, public-facing interfaces are licensed under `MIT`, as indicated in their SPDX headers.
- As a derivative work of [ds-math](https://github.com/dapphub/ds-math/), `Maths.sol` is licensed under `GPL-3.0-or-later`, as indicated in its SPDX header.
- As a derivative work of [SafeERC20Namer](https://github.com/Uniswap/solidity-lib/blob/master/contracts/libraries/SafeERC20Namer.sol), `SafeTokenNamer.sol` is licensed under `GPL-3.0-or-later`, as indicated in its SPDX header.
- Unit and integration tests under `tests` folder remain unlicensed, unless their file header specifies otherwise.

Ajna Labs, LLC shall retain rights to this BUSL license until dissolution, at which point the license shall be 
transferred to the Ajna Foundation.  Licensor reserves the right to specify Additional Use Grants at their discretion 
and to facilitate changes enacted by the Grant Coordination process.

The Change License is hereby specified as _GNU Affero General Public License v3.0 or later_ (`AGPL-3.0-or-later`).
Licensor may modify this change license prior to the change date by updating this file in the `master` branch of [source control](https://github.com/ajna-finance/contracts/tree/master).

The Change Date is hereby specified as April 1, 2026.  Licensor may modify this change date by updating this file in the `master` branch of [source control](https://github.com/ajna-finance/contracts/tree/master).

## Deployment

A deployment script has been created to automate deployment of libraries and factory contracts.
To use it, set up an environment with the following:
- **AJNA_TOKEN** - address of the AJNA token on your target chain
- **ETH_RPC_URL** - node pointing to the target chain
- **DEPLOY_KEY** - path to the JSON keystore file for your deployment account

Ensure your deployment account is funded with some ETH for gas.

The deployment script takes no arguments, and interactively prompts for your keystore password:
```
./deploy.sh
```

Upon completion, contract addresses will be printed to `stdout`:
```
Deploying to chain with AJNA token address 0xDD576260ed60AaAb798D8ECa9bdBf33D70E077F4
Enter keystore password: 
Deploying libraries...
Deployed             Auctions to 0xDD576260ed60AaAb798D8ECa9bdBf33D70E077F4
Deployed        LenderActions to 0x4c08A2ec1f5C067DC53A5fCc36C649501F403b93
Deployed          PoolCommons to 0x8BBCA51044d00dbf16aaB8Fd6cbC5B45503B898b
Deploying factories...
Deployed     ERC20PoolFactory to 0xED625fbf62695A13d2cADEdd954b23cc97249988
Deployed    ERC721PoolFactory to 0x775D30918A42160bC7aE56BA1660E32ff50CF6dC
Deploying PoolInfoUtils...
Deployed        PoolInfoUtils to 0xd8A51cE16c7665111401C0Ba2ABEcE03B847b4e6
```

Record the factory addresses.

### Validation

Validate the deployment by creating a pool.  Set relevant environment variables, and run the following:
```
cast send ${ERC20_POOLFACTORY} "deployPool(address,address,uint256)(address)" \
	${WBTC_TOKEN} ${DAI_TOKEN} 50000000000000000 \
	--from ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY}
```

Where did it deploy the pool?  Let's find out:
```
export ERC20_NON_SUBSET_HASH=0x2263c4378b4920f0bef611a3ff22c506afa4745b3319c50b6d704a874990b8b2
cast call ${ERC20_POOLFACTORY} "deployedPools(bytes32,address,address)(address)" \
	${ERC20_NON_SUBSET_HASH} ${WBTC_TOKEN} ${DAI_TOKEN}
```
Record the pool address.

Run an approval to let the contract spend some of your quote token, and then add some liquidity:
```
cast send ${DAI_TOKEN} "approve(address,uint256)" ${WBTC_DAI_POOL} 50000ether \
	--from ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY}
cast send ${WBTC_DAI_POOL} "addQuoteToken(uint256,uint256)" 100ether 3232 \
	--from ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY}
```
