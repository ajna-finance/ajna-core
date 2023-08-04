# Ajna Tests
## Forge tests
### Unit tests
- validation tests:
```bash
make test
```
- validation tests with gas report:
```bash
make test-with-gas-report
```
- load tests with gas report  
NOTE: takes longer to execute, simulate pool with 2000 lenders and 8000 borrowers, using all buckets of the pool
```bash
make test-load
```

### Regression tests
Regression tests are scenarios exposed by invariant testing and fixed by changing contracts or testing logic.
- regression tests for both ERC20 and ERC721 Pool:
```bash
make test-regression-all
```
- run a specific regression test:
```bash
make test-regression MT=<test_name>
```
- regression tests for ERC20 Pool:
```bash
make test-regression-erc20
```
- regression tests for ERC721 Pool:
```bash
make test-regression-erc721
```
- regression tests for Position Manager:
```bash
make test-regression-position
```
- regression tests for Rewards Manager:
```bash
make test-regression-rewards
```
#### Instruction to generate regression test from failing invariant sequence

- copy the failing scenario steps from invariant failure in `trace.log` file in invariants dir
- run python script 
```bash
python regression_generator.py
```
- it will output regression test based on scenario steps
- copy test in proper RegressionTest* test suite

### Invariant tests
#### Configuration
Invariant test scenarios can be externally configured by customizing following environment variables:
| Variable | Contract Type | Default | Description |
| ------------- | ------------- | ------------- | ------------- |
| NO_OF_ACTORS  | ERC20 ERC721 | 10 | Max number of actors to interact with the pool |
| QUOTE_PRECISION  | ERC20 ERC721 | 18 | Precision of token used as quote token |
| MIN_QUOTE_AMOUNT_ERC20 | ERC20 | 1e3 | The min amount of quote tokens that can be used in a single ERC20 pool action |
| MIN_QUOTE_AMOUNT_ERC721 | ERC721 | 1e3 | The min amount of quote tokens that can be used in a single ERC721 pool action |
| MAX_QUOTE_AMOUNT_ERC20 | ERC20 | 1e30 | The max amount of quote tokens that can be used in a single ERC20 pool action |
| MAX_QUOTE_AMOUNT_ERC721 | ERC721 | 1e30 | The max amount of quote tokens that can be used in a single ERC721 pool action |
| COLLATERAL_PRECISION  | ERC20 | 18 | Precision of token used as colalteral token in ERC20 actions |
| MIN_COLLATERAL_AMOUNT_ERC20 | ERC20 | 1e3 | The min amount of collateral tokens that can be used in a single pool action |
| MIN_COLLATERAL_AMOUNT_ERC721 | ERC721 | 1 | The min amount of collateral tokens that can be used in a single ERC721 pool actions |
| MAX_COLLATERAL_AMOUNT_ERC20 | ERC20 | 1e30 | The max amount of collateral tokens that can be used in a single pool action |
| MAX_COLLATERAL_AMOUNT_ERC721 | ERC721 | 100 | The max amount of collateral tokens that can be used in a single ERC721 pool action |
| NO_OF_BUCKETS | ERC20 ERC721 | 3 | Number of buckets starting from `BUCKET_INDEX_*` to be used in pool actions |
| BUCKET_INDEX_ERC20 | ERC20 | 2570 | First bucket index to be used in ERC20 pool actions |
| BUCKET_INDEX_ERC721 | ERC721 | 850 | First bucket index to be used in ERC721 pool actions |
| MIN_DEBT_AMOUNT | ERC20 ERC721 | 0 | The min amount of debt that can be taken in a single pool action |
| MAX_DEBT_AMOUNT | ERC20 ERC721 | 1e28 | The max amount of debt that can be taken in a single pool action |
| MAX_POOL_DEBT | ERC20 ERC721 | 1e45 | The max amount of debt that can be taken from the pool. If debt goes above this amount, borrower debt will be repaid |
| SKIP_TIME | ERC20 ERC721 | 24 hours | The upper limit of time that can be skipped after a pool action (fuzzed) |
| SKIP_TIME_TO_KICK | ERC20 ERC721 | 200 days | The time to be skipped and drive a new loan undercollateralized. Use a big value to ensure a successful kick |
| MAX_EPOCH_ADVANCE | ERC20 ERC721 | 5 | The maximum number of epochs that will be created before an unstake or claimRewards call |
| MAX_AJNA_AMOUNT | ERC20 ERC721 | 100_000_000 | The maximum amount of ajna provided to the rewards contract |
| NO_OF_POOLS | Position Rewards | 10 | Number of pools to be used in position and rewards manager invariant testing |
| FOUNDRY_INVARIANT_RUNS | ERC20 ERC721 | 10 | The number of runs for each scenario |
| FOUNDRY_INVARIANT_DEPTH | ERC20 ERC721 | 200 | The number of actions performed in each scenario |
| LOGS_VERBOSITY_POOL | ERC20 ERC721 | 0 | <p> Details to log <p> 0 = No Logs <p> 1 = pool State  <p> 2 = pool State, Auctions details <p> 3 = pool State, Auctions details , Buckets details <p> 4 = pool State, Auctions details , Buckets details, Lender details <p> 5 = pool State, Auctions details , Buckets details, Lender details, Borrower details <p> Note - Log File with name `logFile.txt` will be generated in project directory|
| LOGS_VERBOSITY_POSITION | ERC20 ERC721 | 0 | <p> Details to log <p> 0 = No Logs <p> 1 = positionManager details <p> Note - Log File with name `logFile.txt` will be generated in project directory|
| LOGS_VERBOSITY_REWARDS | ERC20 ERC721 | 0 | <p> Details to log <p> 0 = No Logs <p> 1 = rewardsManager details <p> Note - Log File with name `logFile.txt` will be generated in project directory|
#### Invariant names

The `<invariant_name>` placeholder in commands below could take following values:
| Invariant Name |
| ------------- |
| invariant_bucket |
| invariant_quote |
| invariant_collateral |
| invariant_exchange_rate |
| invariant_loan |
| invariant_interest_rate |
| invariant_fenwick |
| invariant_auction |

#### Custom Scenarios

Custom scenario configurations are defined in [scenarios](forge/invariants/scenarios/) directory in `scenario-<custom-pool>.sh` files.
For running a custom scenario
```bash
make test-invariant MT=<invariant_name> SCENARIO=<custom-pool>
```
For example, to test all invariants for the active pool scenario (with actions happening every 5 minutes, defined by `SKIP_TIME`):
```bash
make test-invariant MT=invariant SCENARIO=active-pool
```
To test all invariants for a pool with reduced usage (actions happening once in a 24 hours interval, defined by `SKIP_TIME`):
```bash
make test-invariant MT=invariant SCENARIO=inactive-pool
```

To test all invariants for a pool with more depth (Time skip after kick actions are 0 and `SKIP_TIME` between actions is maximum 5 mins):
```bash
make test-invariant MT=invariant SCENARIO=no-skip
```
To test all invariants (lend/borrow, liquidations and reserve auctions) for a real-world like pool simulation:
```bash
make test-rw-simulation-erc20 SCENARIO=<rw-scenario>
make test-rw-simulation-erc721 SCENARIO=<rw-scenario>
```
where `<rw-scenario>` is the configured setup (two sample provided as `rw-1` and `rw-2`). Real-time pool statistics are written in `logfile.txt`

To test invariants for an ERC20 auctioned pool with 200 lenders and 500 borrowers:
```bash
make test-liquidations-load-erc20 SCENARIO=panic-exit
```
or for ERC721 pool:
```bash
make test-liquidations-load-erc721 SCENARIO=panic-exit
```
To test invariants for swapping quote for colalteral in an ERC20 pool with 200 lenders and 500 borrowers:
```bash
make test-swap-load-erc20 SCENARIO=trading-pool
```

#### Commands
- run all invariant tests for both ERC20 and ERC721 pools:
```bash
make test-invariant-all
```
- run all invariant tests for ERC20 pool:
```bash
make test-invariant-erc20
```
- run all invariant tests for ERC721 pool:
```bash
make test-invariant-erc721
```
- run all invariant tests for Position Manager with ERC20Pool:
```bash
make test-invariant-position-erc20
```
- run all invariant tests for Position Manager with ERC721Pool:
```bash
make test-invariant-position-erc721
```
- run all invariant tests for Rewards Manager:
```bash
make test-invariant-rewards
```
- run specific invariant test for both ERC20 and ERC721 pools:
```bash
make test-invariant MT=<invariant_name>
```
- run ERC20 pool invariant tests for specific quote and collateral token precision, default values (18, 18):
```bash
make test-invariant-erc20 QUOTE_PRECISION=<quote_precision> COLLATERAL_PRECISION=<collateral_precision>
```
- run ERC721 pool invariant tests for specific quote token precision, default value(18):
```bash
make test-invariant-erc721 QUOTE_PRECISION=<quote_precision>
```
- run ERC20 pool invariant tests for most popular token precision combinations(6, 8 and 18):
```bash
make test-invariant-erc20-precision
```
- run ERC721 pool invariant tests for most popular token precision(6, 8 and 18):
```bash
make test-invariant-erc721-precision
```
- run ERC20 pool invariant tests for multiple bucket ranges:
```bash
make test-invariant-erc20-buckets
```
- run ERC721 pool invariant tests for multiple bucket ranges:
```bash
make test-invariant-erc721-buckets
```
- run Position manager with ERC20 pool invariant tests for most popular token precision combinations(6, 8 and 18):
```bash
make test-invariant-position-erc20-precision
```
- run Position manager with ERC721 pool invariant tests for most popular token precision(6, 8 and 18):
```bash
make test-invariant-position-erc721-precision
```

### Code coverage:
```bash
make coverage
```

## Brownie tests
- run integration tests:
```bash
brownie test
```
- to view `stdout` on long-running tests, use `brownie test -s`.
- run invariant tests (experimental, doesn't have full coverage):
```bash
brownie test --stateful true
```

### Debugging Brownie integration tests
- to drop into the console upon test failure:
```bash
brownie test --interactive
```
- From there, you can pull the last transaction using `tx=history[-1]`, followed by `tx.events` to debug.
