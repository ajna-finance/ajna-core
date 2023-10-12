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
- **QT3**: pool quote token balance (`Quote.balanceOf(pool)`) >= liquidation bonds (`AuctionsState.totalBondEscrowed`) + reserve auction unclaimed amount (`reserveAuction.unclaimed`)

## Auctions
- **A1**: total t0 debt auctioned (`PoolBalancesState.t0DebtInAuction`) = sum of debt across all auctioned borrowers (`Borrower.t0Debt` where borrower's `kickTime != 0`)  
- **A2**: sum of bonds locked in auctions (`Liquidation.bondSize`) = sum of locked balances across all kickers (`Kicker.locked`);  total bond escrowed accumulator (`AuctionsState.totalBondEscrowed`) = sum of kickers locked balances (`Kicker.locked`) + sum of kickers claimable balances (`Kicker.claimable`)  
- **A3**: number of borrowers with debt (`LoansState.borrowers.length` with `t0Debt != 0`) = number of loans (`LoansState.loans.length -1`) + number of auctioned borrowers (`AuctionsState.noOfAuctions`)  
- **A4**: number of recorded auctions (`AuctionsState.noOfAuctions`) = length of auctioned borrowers (count of borrowers in `AuctionsState.liquidations` with `kickTime != 0`)
- **A5**: for each `Liquidation` recorded in liquidation mapping (`AuctionsState.liquidations`) the kicker address (`Liquidation.kicker`) has a locked balance (`Kicker.locked`) equal or greater than liquidation bond size (`Liquidation.bondSize`)  
- **A7**: total bond escrowed accumulator (`AuctionsState.totalBondEscrowed`) should increase when auction is kicked with the difference needed to cover the bond and should decrease only when kicker bonds withdrawn (`Pool.withdrawBonds`). Claimable bonds should be available for withdrawal from pool at any time.  
- **A8**: Upon a take/arbtake/deposittake the kicker reward <= borrower penalty

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
- **F4**: For any index `i < MAX_FENWICK_INDEX`, `Deposits.valueAt(findIndexOfSum(prefixSum(i) + 1)) > 0`
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
- **RE7**:  Reserves increase by bond penalty/reward plus borrower penalty on take above TP.
- **RE8**:  Reserves increase by bond penalty/reward plus borrower penalty on bucket takes above TP.
- **RE9**:  Reserves unchanges by takes and bucket takes below TP.
- **RE10**: Reserves increase by origination fee: max(1 week interest, 0.05% of borrow amount), on draw debt
- **RE11**: Reserves decrease by claimableReserves by kickReserveAuction
- **RE12**: Reserves decrease by amount of reserve used to settle a auction
- **RE13**: Reserves are unchanged by kick

## Rewards
- **RW1**: Staking rewards must be less than reward cap percentage multiplied by ajna burned (`newRewards < REWARD_CAP * totalBurnedInPeriod`) for any given time period (`epoch`)
- **RW2**: Updating (recording) rewards must be less than reward cap percentage multiplied by ajna burned (`newRewards < UPDATE_CAP * totalBurned`) for any given time period (`epoch`)
- **RW3**: If a bucket has had it's exchange rate updated bucketExchangeRates mapping should be non-zero (`bucketExchangeRates[pool_][bucketIndex_][burnEpoch_] != 0`)
- **RW4**: After staking, for each bucket in the staked position `lpsAtStakeTime` should equal the position's LP (`position.lps`) in the bucket and `rateAtStakeTime` should equal the bucket's exchange rate (`Buckets.getExchangeRate()`)
- **RW5**: After staking, the Reward's manager contract should be the new owner of the position (`ERC721.ownerOf()`). Upon unstaking, The caller of unstake should be the new owner of the position (`ERC721.ownerOf()`)
- **RW6**: After claiming rewards, `stakeInfo_.lastClaimedEpoch` should be equal to the epoch this position was staked in or the last epoch they claimed rewards for. After claiming or unstaking, `isEpochClaimed` should be equal to `true` for all epochs that the staker has claimed rewards for.
- **RW7**: Each time the bucket rate is updated the `updateRewardsClaimed` accumulator should be updated. Each time a user claims rewards from staking the `rewardsClaimed` accumulator should be updated.
- **RW8**: After unstaking or claiming rewards, if ajna has been burned over an epoch while the staker was staked they should have an increased amount in ajna balance `_ajna.balanceOf()` that matches the amount of ajna balance deducted from the contract `_ajna.balanceOf()`.
- **RW9**: After unstaking, stakeInfo's tokenId mapping should be deleted and all corrosponding values should therefore be zero'd out (`StakeInfo.owner`,`StakeInfo.ajnaPool`, `StakeInfo.lastClaimedEpoch`)
- **RW10**: a Staker can never claim rewards for the same epoch twice

## Position Manager
- **PM1**: LP balance of PositionManager in a Pool for a Bucket should be the sum of the positions[...][index].lps for all tokens/users
- **PM2**: Sum of the LP balance of the PositionManager in a Pool across all buckets should be the sum of the positions[...].[...].lps across all indexes and tokens/users
- **PM3**: Position deposit time (`depositTime`) tracked by tokenId in PositionManager (`positions[tokenId][index]`) should always be of equal or lesser value than the PositionManager's LP at that index in the pool contract.
- **PM4**: mint should populate `poolKey[tokenId]`, `positionIndexes` should be empty and the owner of the NFT should be the caller.
- **PM5**: burn should reset `poolKey[tokenId]`, `positionIndexes` should be empty and the owner of the NFT should be the zero address.
- **PM6**: moveLiquidity should remove all LP from the from index and set deposit time to zero. To index should receive increased LP and deposit time should match positionManager's deposit time. PositionManager should have less then or equal to the same quoteToken after move.
- **PM7**: memorializePosition should transfer all pool contract LP in the provided index to the positionManager. PositionManager should take on the greater of the lender of positionManager's deposit time. PositionManager's LP in the provided index should match what the lender had in the pool contract before memorializePosition was called.
- **PM8**: reedemPositions should maintain the preivous owner of the NFT position and pool associated with position. Remove the passed in indexes from the positionIndexes associated token. LP of redeemer should increase with same amount that LP of PositionManager decrease (by checking the pool). tokenId associated with the indexes redeemed should be zero.


