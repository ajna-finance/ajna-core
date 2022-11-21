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
