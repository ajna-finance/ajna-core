# Ajna Pool Invariants

## Collateral
- #### ERC20:  
  - **CT1**: pool collateral token balance (`Collateral.balanceOf(pool)`) = sum of collateral balances across all borrowers (`Borrower.collateral`) + sum of claimable collateral across all buckets (`Bucket.collateral`)  
- #### NFT:  
  - **CT2**: number of tokens owned by the pool (`Collateral.balanceOf(pool)`) * `1e18` = sum of collateral across all borrowers (`Borrower.collateral`) + sum of claimable collateral across all buckets (`Bucket.collateral`)  
  - **CT3**: number of tokens owned by the pool (`Collateral.balanceOf(pool)`) = length of borrower array token ids (`ERC721Pool.borrowerTokenIds.length`) + length of buckets array token ids (`ERC721Pool.bucketTokenIds.length`)  
  - **CT4**: number of borrower token ids (`ERC721Pool.borrowerTokenIds.length`) * `1e18` >= borrower balance (`Borrower.collateral`) Note: can be lower in case when fractional collateral that is rebalanced / moved to buckets claimable token ids  
  - **CT5**: token ids in buckets array (`ERC721Pool.bucketTokenIds`) and in borrowers array (`ERC721Pool.borrowerTokenIds`) are owned by pool contract (`Collateral.ownerOf(tokenId)`)  
  - **CT6**: in case of subset pools: token ids in buckets array (`ERC721Pool.bucketTokenIds`) and in borrowers array (`ERC721Pool.borrowerTokenIds`) should have a mapping of `True` in allowed token ids mapping (`ERC721Pool.tokenIdsAllowed`)  

- **CT7**: total pledged collateral in pool (`PoolBalancesState.pledgedCollateral`) = sum of collateral balances across all borrowers (`Borrower.collateral`)

## Quote Token
- **QT1**: pool quote token balance (`Quote.balanceOf(pool)`) >= liquidation bonds (`AuctionsState.totalBondEscrowed`) + pool deposit size (`Pool.depositSize()`) + reserve auction unclaimed amount (`reserveAuction.unclaimed`) - pool t0 debt (`PoolBalancesState.t0Debt`) (with a `1e13` margin)
- **QT2**: pool t0 debt (`PoolBalancesState.t0Debt`) = sum of t0 debt across all borrowers (`Borrower.t0Debt`)

## Auctions
- **A1**: total t0 debt auctioned (`PoolBalancesState.t0DebtInAuction`) = sum of debt across all auctioned borrowers (`Borrower.t0Debt` where borrower's `kickTime != 0`)  
- **A2**: sum of bonds locked in auctions (`Liquidation.bondSize`) = sum of locked balances across all kickers (`Kicker.locked`) = total bond escrowed accumulator (`AuctionsState.totalBondEscrowed`)  
- **A3**: number of borrowers with debt (`LoansState.borrowers.length` with `t0Debt != 0`) = number of loans (`LoansState.loans.length -1`) + number of auctioned borrowers (`AuctionsState.noOfAuctions`)  
- **A4**: number of recorded auctions (`AuctionsState.noOfAuctions`) = length of auctioned borrowers (count of borrowers in `AuctionsState.liquidations` with `kickTime != 0`)
- **A5**: for each `Liquidation` recorded in liquidation mapping (`AuctionsState.liquidations`) the kicker address (`Liquidation.kicker`) has a locked balance (`Kicker.locked`) equal or greater than liquidation bond size (`Liquidation.bondSize`)  
- **A6**: if a `Liquidation` is not taken then the take flag (`Liquidation.alreadyTaken`) should be `False`, if already taken then the take flag should be `True`  

## Loans
- **L1**: for each `Loan` in loans array (`LoansState.loans`) starting from index 1, the corresponding address (`Loan.borrower`) is not `0x`, the threshold price (`Loan.thresholdPrice`) is different than 0 and the id mapped in indices mapping (`LoansState.indices`) equals index of loan in loans array.  
- **L2**: `Loan` in loans array (`LoansState.loans`) at index 0 has the corresponding address (`Loan.borrower`) equal with `0x` address and the threshold price (`Loan.thresholdPrice`) equal with 0
- **L3**: Loans array (`LoansState.loans`) is a max-heap with respect to t0-threshold price: the t0TP of loan at index `i` is >= the t0-threshold price of the loans at index `2*i` and `2*i+1`

## Buckets
- **B1**: sum of LP of lenders in bucket (`Lender.lps`) = bucket LP accumulator (`Bucket.lps`)  
- **B2**: bucket LP accumulator (`Bucket.lps`) = 0 if no deposit / collateral in bucket  
- **B3**: if no collateral or deposit in bucket then the bucket exchange rate is `1e18`  
- **B4**: bucket LP accumulator (`Bucket.lps`) = 0 when a bucket is bankrupted
- **B5**: when adding / moving quote tokens or adding collateral : lender deposit time (`Lender.depositTime`) = timestamp of block when deposit happened (`block.timestamp`)  
- **B6**: when receiving transferred LP : receiver deposit time (`Lender.depositTime`) = max of sender and receiver deposit time  
- **B7**: when awarded bucket take LP : taker/kicker deposit time (`Lender.depositTime`) = timestamp of block when award happened (`block.timestamp`)  

## Interest
- **I1**: interest rate (`InterestState.interestRate`) cannot be updated more than once in a 12 hours period of time (`InterestState.interestRateUpdate`)  
- **I2**: reserve interest (`ReserveAuctionState.totalInterestEarned`) accrues only once per block (`block.timestamp - InflatorState.inflatorUpdate != 0`) and only if there's debt in the pool (`PoolBalancesState.t0Debt != 0`)  
- **I3**: pool inflator (`InflatorState.inflator`) cannot be updated more than once per block (`block.timestamp - InflatorState.inflatorUpdate != 0`) and equals `1e18` if there's no debt in the pool (`PoolBalancesState.t0Debt != 0`)
- **I4**: for all borrowers that are not auctioned and (`borrower.collateral != 0`) the sum of borrower debt squared divided by borrower collateral (`borrower.debt^2 / borrower.collateral`) should equal borrower collateralization accumulator (`t0Debt2ToCollateral`)

## Fenwick tree
- **F1**: Value represented at index `i` (`Deposits.valueAt(i)`) is equal to the accumulation of scaled values incremented or decremented from index `i`
- **F2**: For any index `i`, the prefix sum up to and including `i` is the sum of values stored in indices `j<=i`
- **F3**: For any index `i < MAX_FENWICK_INDEX`,  `findIndexOfSum(prefixSum(i)) > i`
- **F4**: For any index i, there is zero deposit above i and below findIndexOfSum(prefixSum(i) + 1): `depositAtIndex(j) == 0 for i < j < findIndexOfSum(prefixSum(i)+1)`
- **F5**: Global scalar is never updated (`DepositsState.scaling[8192]` is always 0)

## Exchange rate (Margin of 1e12 - 1e16 on comparisons, dependent on amounts)
- **R1**: Exchange rates are unchanged by pledging collateral
- **R2**: Exchange rates are unchanged by pulling collateral
- **R3**: Exchange rates are unchanged by depositing quote token into a bucket
- **R4**: Exchange rates are unchanged by withdrawing deposit (quote token) from a bucket
- **R5**: Exchange rates are unchanged by adding collateral token into a bucket
- **R6**: Exchange rates are unchanged by removing collateral token from a bucket
- **R7**: Exchange rates are unchanged under depositTakes
- **R8**: Exchange rates are unchanged under arbTakes

## Reserves (margin of 1e15 on comparisons)
- **RE1**:  Reserves are unchanged by pledging collateral
- **RE2**:  Reserves are unchanged by removing collateral
- **RE3**:  Reserves increase only when depositing quote token into a bucket below LUP. Reserves increase only when moving quote tokens into a bucket below LUP.
- **RE4**:  Reserves are unchanged by withdrawing deposit (quote token) from a bucket after the penalty period hes expired
- **RE5**:  Reserves are unchanged by adding collateral token into a bucket
- **RE6**:  Reserves are unchanged by removing collateral token from a bucket
- **RE7**:  Reserves increase by 7% of the loan quantity upon the first take (including depositTake or arbTake) and increase/decrease by bond penalty/reward on take.
- **RE8**:  Reserves are unchanged under takes/depositTakes/arbTakes after the first take but increase/decrease by bond penalty/reward on take.
- **RE9**:  Reserves increase by 3 months of interest when a loan is kicked
- **RE10**: Reserves increase by origination fee: max(1 week interest, 0.05% of borrow amount), on draw debt
- **RE11**: Reserves decrease by claimableReserves by kickReserveAuction
- **RE12**: Reserves decrease by amount of reserve used to settle a auction
