# Ajna contracts

The Ajna protocol is a non-custodial, peer-to-peer, permissionless lending, borrowing and trading system that requires no governance or external price feeds to function. The protocol consists of pools: pairings of quote tokens provided by lenders and collateral tokens provided by borrowers. Ajna is capable of accepting fungible tokens as quote tokens and both fungible and non-fungible tokens as collateral tokens.

## Accepted tokens:
- Fungible tokens (following the [ERC20 token standard](https://eips.ethereum.org/EIPS/eip-20)).
- Non-fungible tokens (following the [ERC721 token standard](https://eips.ethereum.org/EIPS/eip-721))

## Caveats:
### Token limitations
- The following types of tokens are incompatible with Ajna, and no countermeasures exist to explicitly prevent creating a pool with such tokens, actors should use them at their own risk:
  - NFT and fungible tokens which charge a fee on transfer.
  - Fungible tokens whose balance rebases.
- The following types of tokens are incompatible with Ajna, and countermeasures exist to explicitly prevent creating a pool with such tokens:
  - Fungible tokens with more than 18 decimals or 0 decimals, whose `decimals()` function does not return a constant value, or which do not implement the optional [decimals()](https://eips.ethereum.org/EIPS/eip-20#decimals) function.
### Pool limitations
- Borrowers cannot draw debt from a pool in the same block as when the pool was created.
- With the exception of quantized prices, pool inputs and most accumulators are not explicitly limited. The pool will stop functioning when the bounds of a `uint256` need to be exceeded to process a request.
- Game theory for liquidations and reserve auctions relies on multiple actors.  If only a single actor is interacting, they may purchase collateral or reserves at a trivial price close to zero.
- Pricing functions for liquidations and reserve auctions rely on the availability of the chain and accuracy of block timestamps.  If the chain is unavailable or returns inaccurate timestamps, collateral or reserves may be purchased well below market value.
- Several protocol functions have a parameters to prevent MEV manipulation or processing against an undesired pool state.  Passing blanket values to these functions obviates their purpose.  For example, passing a `limitIndex_` of 7388 to `drawDebt` allows a combative MEV bot to move liquidity down to a price which could make the loan liquidatable on the very next block.
### Bucket limitations
- Lenders should maintain their deposit in buckets slightly below the market price.  Choosing an inappropriately high price will likely result in the lender losing their deposit in exchange for a potentially trivial amount of collateral.  Symmetrically, adding collateral to an inappropriately underpriced bucket will likely result in the actor losing their collateral in exchange for a potentially small amount of quote token.
- Integrators should take care to understand how token decimal precision, exchange rate, and LP balance in a bucket will affect the lender, especially with respect to rounding.  Inflated exchange rates, whether occurring naturally or through manipulation, could cause lenders to lose a portion of their deposit due to the protocol rounding in favor of the pool.  This can be avoided using a proxy or helper contract to validate the deposit or adjust deposit amounts.
### Position NFT limitations
- Position NFTs are vulnerable to front running attacks when buying from open markets. Seller of such NFT could redeem positions before transfer, and then transfer an NFT without any value to the buyer.
Ajna positions NFTs should not be purchased from open markets.


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

## Documentation
Documentation can be generated as mdbook from Solidity NatSpecs by using `forge doc` command.
For example, to generate documentation and serve it locally on port 4000 (http://localhost:4000/):
```bash
forge doc --serve --port 4000
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
- Make sure the default `solc` version is set to the same version as contracts (currently 0.8.18). This can be done by installing and using `solc-select`:
```bash
pip install solc-select && solc-select install 0.8.18 && solc-select use 0.8.18
```
- Run `analyze`

```bash
make analyze
```


## Licensing
For purposes of the Business Service License: (i) the term “Licensor” means Ajna Labs, LLC, (ii) the term Licensed Work means Licensor’s proprietary software marketed under the name _The Ajna Protocol™_ and useful for purposes of facilitating the lending and borrowing of digital assets, (iii) the term “Additional Use Grants” means a grant of rights in the Licensed Work that are not included in the Business Service License and are granted by Licensor pursuant to a separate agreement between Licensor and one or more third parties, and (iv) the term “Change Date” means April 1, 2026 or such other date as Licensor may specify on or before April 1, 2026.

The licensed work is under the [Business Service License](https://github.com/ajna-finance/contracts/blob/develop/LICENSE) ("BUSL license") with but not limited to the following exceptions:
- To facilitate integrations, public-facing interfaces are licensed under `MIT`, as indicated in their SPDX headers.
- As a derivative work of [ds-math](https://github.com/dapphub/ds-math/), `Maths.sol` is licensed under `GPL-3.0-or-later`, as indicated in its SPDX header.
- As a derivative work of [SafeERC20Namer](https://github.com/Uniswap/solidity-lib/blob/master/contracts/libraries/SafeERC20Namer.sol), `SafeTokenNamer.sol` is licensed under `GPL-3.0-or-later`, as indicated in its SPDX header.
- Unit and integration tests under `tests` folder remain unlicensed, unless their file header specifies otherwise.

Prior to the Change Date, Licensor intends to transfer ownership of the Licensed Work to a to-be-organized not-for-profit foundation or similar public benefit focused entity (the “Ajna Foundation”), whereupon the rights, duties and obligations of Licensor under the BUSL License shall, without further act or deed of the parties, be assigned to Ajna Foundation, which entity shall thereafter be, and assume all rights, duties and obligations of (but not the liabilities, if any, of), the Licensor under the Business Service License.

Licensor reserves the right to specify Additional Use Grants at their discretion and to facilitate changes enacted by the Grant Coordination process, provided always that Additional Use Grants shall not conflict with the Business License. Licensor grants third parties permission to deploy The Ajna Protocol to other public blockchains and scaling solutions, hereby referred to as the "target chain", so long as:
- No other functional and successful deployment of Ajna is available on the target chain.
- No modification to Solidity source files in the protocol is made, and no changes are made which conflict with the Business License.
- Prior to deployment, the canonical burn-wrapped AJNA token (bwAJNA) on Ethereum mainnet is bridged to the target chain.
- Upon deployment, the protocol is configured to use the bwAJNA token on the target chain.

Prior to the Change Date, Licensor shall elect the Change License governing the Licensed Work after the Change Date, which license shall be an [Open Source Initiative](https://opensource.org/licenses) compliant license, provided always that the Change License shall be GPL Version 2.0 compatible. Once elected, Licensor may change its Change License designation at any time on or before the Change Date by updating this file in the master branch of [source control](https://github.com/ajna-finance/contracts/tree/master).

Modifications to, or notices of actions by Licensor, contemplated above or under the Business Service License shall be communicated by updating this file in the master branch of source control. All such updates are binding on Licensor and all licensees under the Business Service License upon the publication of the relevant update.


## Deployment

A deployment script has been created to automate deployment of libraries, factory contracts, and manager contracts.

To use it, ensure the following env variables are in your `.env` file or exported into your environment.
| Environment Variable | Purpose |
|----------------------|---------|
| `AJNA_TOKEN`         | address of the AJNA token on your target chain
| `DEPLOY_ADDRESS`     | address from which you wish to deploy
| `DEPLOY_KEY`         | path to the JSON keystore file for the deployment address
| `ETHERSCAN_API_KEY`  | required to verify contracts
| `ETH_RPC_URL`        | node on your target deployment network

To run:

```
make deploy-contracts
```

Upon completion, contract addresses will be printed to `stdout`:
```
== Logs ==
  Deploying to chain with AJNA token address 0xaadebCF61AA7Da0573b524DE57c67aDa797D46c5
  === Deployment addresses ===
  ERC20PoolFactory       0x14F2474fB5ea9DF82059053c4F85A8C803Ab10C9
  ERC721PoolFactory      0xb0d1c875B240EE9f6C2c3284a31b10f1EC6De7d2
  PoolInfoUtils          0x08F304cBeA7FAF48C93C27ae1305E220913a571d
  PoolInfoUtilsMulticall 0x12874db433dBF1D0f3c73B39F96B009093A56E0E
  PositionManager        0xC4114D90F51960854ab574297Cf7CC131d445F29
```

Record these addresses.  If Etherscan verification fails on the first try, copy the deployment command from the `Makefile`, and tack a `--resume` switch onto the end.
Failing that, manual verification is possible.  Following steps show how to do this on Goerli (chainId 5), using addresses from the example output above.
* Open `broadcast/5/run-latest.json` and find the _"libraries"_ section towards the end of the file.
* Copy/paste the _libraries_ config into the _[profile.default]_ section of `foundry.toml`, replacing the `:` with an `=`.
* Run the following commands, adjusting addresses as appropriate.  _PoolInfoUtilsMulticall_ constructor takes the address of _PoolInfoUtils_. _PositionManager_ constructor takes the factory addresses.
    ```
    forge verify-contract --chain-id 5 --watch 0x14F2474fB5ea9DF82059053c4F85A8C803Ab10C9 ERC20PoolFactory --constructor-args $(cast abi-encode "constructor(address)" ${AJNA_TOKEN})
    forge verify-contract --chain-id 5 --watch 0xb0d1c875B240EE9f6C2c3284a31b10f1EC6De7d2 ERC721PoolFactory --constructor-args $(cast abi-encode "constructor(address)" ${AJNA_TOKEN})
    forge verify-contract --chain-id 5 --watch 0x08F304cBeA7FAF48C93C27ae1305E220913a571d PoolInfoUtils
    forge verify-contract --chain-id 5 --watch 0x12874db433dBF1D0f3c73B39F96B009093A56E0E PoolInfoUtilsMulticall --constructor-args $(cast abi-encode "constructor(address)" 0x08F304cBeA7FAF48C93C27ae1305E220913a571d)
    forge verify-contract --chain-id 5 --watch 0xC4114D90F51960854ab574297Cf7CC131d445F29 PositionManager --constructor-args $(cast abi-encode "constructor(address,address)" 0x14F2474fB5ea9DF82059053c4F85A8C803Ab10C9 0xb0d1c875B240EE9f6C2c3284a31b10f1EC6De7d2)
    ```
* To verify pool contracts, return to the `run-latest.json` file and search for the factory contracts.  After the factory bytecode, under the `additionalContracts` section should be a _CREATE_ action.  Copy the address for the "seed" pool from each factory deployment, and verify this seed pool.
    ```
    forge verify-contract --chain-id 5 --watch 0x5a4fB4f6a83282D62c3fc87c4DFE9A2849D987E9 ERC20Pool
    forge verify-contract --chain-id 5 --watch 0x7c79C719081d987678b1cFAb5f95B48f3CEC55b2 ERC721Pool
    ```

### Validation

Validate the deployment by creating a pool.  Set relevant environment variables, and run the following:
```
cast send ${AJNA_ERC20_POOLFACTORY} "deployPool(address,address,uint256)(address)" \
	${WBTC_TOKEN} ${DAI_TOKEN} 50000000000000000 \
	--from ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY}
```

Where did it deploy the pool?  Let's find out:
```
export ERC20_NON_SUBSET_HASH=0x2263c4378b4920f0bef611a3ff22c506afa4745b3319c50b6d704a874990b8b2
cast call ${AJNA_ERC20_POOLFACTORY} "deployedPools(bytes32,address,address)(address)" \
	${ERC20_NON_SUBSET_HASH} ${WBTC_TOKEN} ${DAI_TOKEN}
```
Record the pool address.

Run an approval to let the contract spend some of your quote token, and then add some liquidity:
```
cast send ${DAI_TOKEN} "approve(address,uint256)" ${WBTC_DAI_POOL} 50000ether \
	--from ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY}
cast send ${WBTC_DAI_POOL} "addQuoteToken(uint256,uint256,uint256)" 100ether 3232 $(($(cast block -f timestamp) + 60)) \
	--from ${DEPLOY_ADDRESS} --keystore ${DEPLOY_KEY}
```
