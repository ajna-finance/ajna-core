# Ajna contracts

The Ajna protocol is a non-custodial, peer-to-peer, permissionless lending, borrowing and trading system that requires no governance or external price feeds to function. The protocol consists of pools: pairings of quote tokens provided by lenders and collateral tokens provided by borrowers. Ajna is capable of accepting fungible tokens as quote tokens and both fungible and non-fungible tokens as collateral tokens.

## Limitations
- The following types of tokens are incompatible with Ajna, and no countermeasures exist to explicitly prevent creating a pool with such tokens:
	- Fungible tokens whose balance rebases.
	- NFTs which charge a fee on transfer.
	- Fungible tokens with more than 18 decimals or 0 decimals.
- Special considerations have been made to support specific NFTs with nonstandard ERC721 implementations, including _CryptoPunks_ and _CryptoKitties_.  This support is limited to Ethereum mainnet.
- Borrowers cannot draw debt from a pool in the same block as when the pool was created.
- With the exception of quantized prices, pool inputs and most accumulators are not explicitly limited.  The pool will stop functioning when the bounds of a `uint256` need to be exceeded to process a request.


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

### Implementation notes
Pool external calls carry the `nonReentrant` modifier to prevent invocation from `flashLoan` and `take` callbacks.

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

## Code Coverage
- generate basic code coverage report:
```bash
make coverage
```
- exclude tests from code coverage report:
```
apt-get install lcov
bash ./check-code-coverage.sh
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
For purposes of the Business Service License: (i) the term “Licensor” means Ajna Labs, LLC, (ii) the term Licensed Work means Licensor’s proprietary software marketed under the name _The Ajna Protocol™_ and useful for purposes of facilitating the lending and borrowing of digital assets, (iii) the term “Additional Use Grants” means a grant of rights in the Licensed Work that are not included in the Business Service License and are granted by Licensor pursuant to a separate agreement between Licensor and one or more third parties, and (iv) the term “Change Date” means April 1, 2026 or such other date as Licensor may specify on or before April 1, 2026.

The licnesed work is under the [Business Service License](https://github.com/ajna-finance/contracts/blob/develop/LICENSE) ("BUSL license") with but not limited to the following exceptions:
- To facilitate integrations, public-facing interfaces are licensed under `MIT`, as indicated in their SPDX headers.
- As a derivative work of [ds-math](https://github.com/dapphub/ds-math/), `Maths.sol` is licensed under `GPL-3.0-or-later`, as indicated in its SPDX header.
- As a derivative work of [SafeERC20Namer](https://github.com/Uniswap/solidity-lib/blob/master/contracts/libraries/SafeERC20Namer.sol), `SafeTokenNamer.sol` is licensed under `GPL-3.0-or-later`, as indicated in its SPDX header.
- Unit and integration tests under `tests` folder remain unlicensed, unless their file header specifies otherwise.

Prior to the Change Date, Licensor intends to transfer ownership of the Licensed Work to a to-be-organized not-for-profit foundation or similar public benefit focused entity (the “Ajna Foundation”), whereupon the rights, duties and obligations of Licensor under the BUSL License shall, without further act or deed of the parties, be assigned to Ajna Foundation, which entity shall thereafter be, and assume all rights, duties and obligations of (but not the liabilities, if any, of), the Licensor under the Business Service License.

Licensor reserves the right to specify Additional Use Grants at their discretion and to facilitate changes enacted by the Grant Coordination process, provided always that Additional Use Grants shall not conflict with the Business License.

Prior to the Change Date, Licensor shall elect the Change License governing the Licensed Work after the Change Date, which license shall be an [Open Source Initiative](https://opensource.org/licenses) compliant license, provided always that the Change License shall be GPL Version 2.0 compatible. Once elected, Licensor may change its Change License designation at any time on or before the Change Date by updating this file in the master branch of [source control](https://github.com/ajna-finance/contracts/tree/master).

Modifications to, or notices of actions by Licensor, contemplated above or under the Business Service License shall be communicated by updating this file in the master branch of source control. All such updates are binding on Licensor and all licensees under the Business Service License upon the publication of the relevant update.


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
