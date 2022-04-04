# Create MKR/DAI pool

- 10 lenders with 200000 DAI each
- 10 borrowers with 5000 MKR each
- lender1 deposits 10000 DAI in bucket 2922.125138357663115550
- lender1 deposits 10000 DAI in bucket 1774.567954841786765083
- lender1 deposits 10000 DAI in bucket 1077.671652392430276064
- borrower1 and borrower2 deposit 100 MKR each as collateral
- borrower1 and borrower2 borrow 10000 DAI each from pool

```bash
brownie console
protocol, lenders, borrowers, dai, mkr, pool = run('erc20setup')
```
