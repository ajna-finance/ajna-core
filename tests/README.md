## Ajna Tests
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
- run both ERC20 and ERC721 Pool invariant tests:
```bash
make test-invariant
```
- run ERC20 Pool invariant tests:
```bash
make test-invariant-erc20
```
- run ERC20 Pool invariant tests for specific quote and collateral token precision, default values (18, 18):
```bash
make test-invariant-erc20 QUOTE_PRECISION=<quote_precision> COLLATERAL_PRECISION=<collateral_precision>
```
- run ERC721 Pool invariant tests:
```bash
make test-invariant-erc721
```
- run ERC721 Pool invariant tests for specific quote token precision, default value(18):
```bash
make test-invariant-erc721 QUOTE_PRECISION=<quote_precision>
```
- run ERC20 Pool invariant tests for most popular token precision combinations(6,8 and 18):
```bash
make test-invariant-erc20-precision
```
- run ERC20 Pool invariant tests for multiple bucket ranges:
```bash
make test-invariant-erc20-buckets
```
- run ERC721 Pool invariant tests for multiple bucket ranges:
```bash
make test-invariant-erc721-buckets
```
- run regression test for both ERC20 and ERC721 Pool:
```bash
make test-regression
```
- run regression test for ERC20 Pool:
```bash
make test-regression-erc20
```
- run regression test for ERC721 Pool:
```bash
make test-regression-erc721
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
- run invariant tests (experimental, doesn't have full coverage):
```bash
brownie test --stateful true
```

#### Debugging Brownie integration tests
- to drop into the console upon test failure:
```bash
brownie test --interactive
```
- From there, you can pull the last transaction using `tx=history[-1]`, followed by `tx.events` to debug.
