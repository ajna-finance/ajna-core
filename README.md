# ajna contracts

Ajna contracts

## Development

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

#### Build

```bash
make build
```

#### Run Tests

```bash
make test
```

## Brownie integration
- Install Brownie [instructions](https://eth-brownie.readthedocs.io/en/stable/install.html)
- Make a copy of .env.example and name it .env. Add the values for ETHERSCAN_TOKEN and WEB3_INFURA_PROJECT_ID
- Run `brownie console`

### ERC20 pool test

- Deploy ERC20 Perp pool for DAI/MKR, swap ETH to DAI for `alice` and ETH to MKR for `bob` and check balances:

```bash
>>> deployer, alice, bob, dai, mkr, daiPool = run('erc20setup')
>>> dai.balanceOf(alice)
157571811476835406723764
```
- Deposit and withdraw collateral from pool:

```bash
>>> daiPool.deposit(1111111111, {"from": alice})
>>> dai.balanceOf(daiPool)
1111111111
>>> daiPool.withdraw(1111111111, {"from": alice})
0
```
- Deposit quote token into the pool:
```
>>> daiPool.depositQuoteToken(125454, 307000000000000000000, {"from": alice})
>>> daiPool.quoteBalances(alice)
125454
```
- Query buckets
```
>>> daiPool.indexToPrice(3)
307000000000000000000
>>> daiPool.priceToIndex(307000000000000000000)
3
```
