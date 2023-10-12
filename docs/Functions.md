
## Pool base contract

### addQuoteToken
	external libraries call:
    - PoolCommons.accrueInterest()
	- LenderActions.addQuoteToken()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state 
		- increment reserveAuction.totalInterestEarned accumulator
	- LenderActions.addQuoteToken():
		- Deposits.unscaledAdd() (add new amount in Fenwick tree):
			- update values array state 
		- increment bucket.lps accumulator
		- increment lender.lps accumulator and lender.depositTime state
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- block timestamp greater than expiry TransactionExpired()
	- head auction not cleared AuctionNotCleared()
	- LenderActions.addQuoteToken():
		- invalid bucket index InvalidIndex()
		- same block when bucket becomes insolvent BucketBankruptcyBlock()

	emit events:
	- LenderActions.addQuoteToken():
		- AddQuoteToken
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### moveQuoteToken
	external libraries call:
	- PoolCommons.accrueInterest()
	- LenderActions.moveQuoteToken()
	- PoolCommons.updateInterestRate()
	
	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state 
		- increment reserveAuction.totalInterestEarned accumulator
	- LenderActions.moveQuoteToken():
		- _removeMaxDeposit():
			- Deposits.unscaledRemove() (remove amount in Fenwick tree, from index):
				- update values array state
			- Deposits.unscaledAdd() (add amount in Fenwick tree, to index):
				- update values array state
		- decrement lender.lps accumulator for from bucket
		- increment lender.lps accumulator and lender.depositTime state for to bucket
		- decrement bucket.lps accumulator for from bucket
		- increment bucket.lps accumulator for to bucket
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- block timestamp greater than expiry TransactionExpired()
	- deposits locked RemoveDepositLockedByAuctionDebt()
	- head auction not cleared AuctionNotCleared()
	- LenderActions.moveQuoteToken():
		- same index MoveToSameIndex()
		- dust amount DustAmountNotExceeded()
		- invalid index InvalidIndex()

	emit events:
	- LenderActions.moveQuoteToken():
		- MoveQuoteToken
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### removeQuoteToken
	external libraries call:
	- PoolCommons.accrueInterest()
	- LenderActions.removeQuoteToken()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state 
		- increment reserveAuction.totalInterestEarned accumulator
	- LenderActions.removeQuoteToken():
		- _removeMaxDeposit():
			- Deposits.unscaledRemove() (remove amount in Fenwick tree):
				- update values array state
		- decrement lender.lps accumulator
		- decrement bucket.lps accumulator
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- deposits locked RemoveDepositLockedByAuctionDebt()
	- LenderActions.removeQuoteToken():
		- no LP NoClaim()
		- LUP lower than HTP LUPBelowHTP()
	emit events:
	- LenderActions.removeQuoteToken():
		- RemoveQuoteToken
		- BucketBankruptcy
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### transferLP
	external libraries call:
	- LPActions.transferLP()

	write state:
	- LPActions.transferLP():
		- delete allowance mapping
		- increment new lender.lps accumulator and lender.depositTime state
		- delete old lender from bucket -> lender mapping

	reverts on:
	- LPActions.transferLP():
		- invalid index InvalidIndex()
		- no allowance NoAllowance()

	emit events:
	- LPActions.transferLP():
		- TransferLP

### kick
	external libraries call:
	- PoolCommons.accrueInterest()
	- KickerActions.kick()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state 
		- increment reserveAuction.totalInterestEarned accumulator
	- KickerActions.kick():
		- _kick():
			- _recordAuction():
				- borrower -> liquidation mapping update
				- increment auctions count accumulator
				- increment auctions.totalBondEscrowed accumulator
				- updates auction queue state
				- _updateEscrowedBonds():
					- update locked and claimable kicker accumulators
					- update global escrow accumulator
				- Loans.remove():
					- delete borrower from indices => borrower address mapping
					- remove loan from loans array
	- increment poolBalances.t0DebtInAuction and poolBalances.t0Debt accumulators
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- KickerActions.kick():
		- borrower collateralized BorrowerOk()
		- auction active AuctionActive()

	emit events:
	- KickerActions.kick():
		- Kick
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### lenderKick
	external libraries call:
	- PoolCommons.accrueInterest()
	- KickerActions.lenderKick()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state 
    	- increment reserveAuction.totalInterestEarned accumulator
	- KickerActions.lenderKick():
		- _kick():
			- _recordAuction():
				- borrower -> liquidation mapping update
				- increment auctions count accumulator
				- increment auctions.totalBondEscrowed accumulator
				- updates auction queue state
				- _updateKicker():
					- update locked and claimable kicker accumulators
				- Loans.remove():
					- delete borrower from indices => borrower address mapping
					- remove loan from loans array
	- increment poolBalances.t0DebtInAuction and poolBalances.t0Debt accumulators
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- KickerActions.lenderKick():
		- bucket price below current pool LUP PriceBelowLUP()
		- borrower collateralized BorrowerOk()
		- insuficient amount InsufficientLiquidity()

	emit events:
	- KickerActions.lenderKick():
		- Kick
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### withdrawBonds
	write state:
	- decrease kicker's claimable accumulator
	- decrease auctions totalBondEscrowed accumulator

	reverts on:
	- insufficient liquidity InsufficientLiquidity()

	emit events:
	- BondWithdrawn

### kickReserveAuction
	external libraries call:
	- KickerActions.kickReserveAuction()

	write state:
	- KickerActions.kickReserveAuction():
		- update reserveAuction.unclaimed accumulator
		- update reserveAuction.kicked timestamp state
	- increment latestBurnEpoch counter
	- update reserveAuction.latestBurnEventEpoch and burn event timestamp state

	reverts on:
	- 2 weeks not passed ReserveAuctionTooSoon()
	- KickerActions.kickReserveAuction():
		- no reserves to claim NoReserves()

	emit events:
	- KickerActions.kickReserveAuction():
		- KickReserveAuction


### takeReserves
	external libraries call:
	- TakerActions.takeReserves()

	write state:
	- TakerActions.takeReserves():
		- decrement reserveAuction.unclaimed accumulator
	- increment reserveAuction.totalAjnaBurned accumulator
	- update burn event totalInterest and totalBurned accumulators

	reverts on:
	- TakerActions.takeReserves():
		- not kicked or 72 hours didn't pass NoReservesAuction()

	emit events:
	- TakerActions.takeReserves():
		- ReserveAuction

### stampLoan
	external libraries call:
	- BorrowerActions.stampLoan()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- BorrowerActions.stampLoan():
		- Loans.update():
			- _upsert():
				- insert or update loan in loans array
			- remove():
				- remove loan from loans array
			- update borrower in address => borrower mapping
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- BorrowerActions.stampLoan()
		- loan in auction AuctionActive()
		- borrower under collateralized BorrowerUnderCollateralized()

	emit events:
	- BorrowerActions.stampLoan():
		- LoanStamped
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

## ERC20Pool contract

### addCollateral
	external libraries call:
	- PoolCommons.accrueInterest()
	- LenderActions.addCollateral()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- LenderActions.addCollateral():
		- Buckets.addCollateral():
			- increment bucket.collateral and bucket.lps accumulator
			- addLenderLP():
				- increment lender.lps accumulator and lender.depositTime state
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- LenderActions.addCollateral():
		- invalid bucket index InvalidIndex()

	emit events:
	- AddCollateral
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### removeCollateral
	external libraries call:
	- PoolCommons.accrueInterest()
	- LenderActions.removeMaxCollateral()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- LenderActions.removeMaxCollateral():
		- _removeMaxCollateral():
			- decrement lender.lps accumulator
			- decrement bucket.collateral and bucket.lps accumulator
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
		- LenderActions.removeMaxCollateral():
			- not enough collateral InsufficientCollateral()
			- no claim NoClaim()

	emit events:
	- LenderActions.removeMaxCollateral():
		- BucketBankruptcy
	- RemoveCollateral
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### drawDebt
	external libraries call:
	- PoolCommons.accrueInterest()
	- BorrowerActions.drawDebt()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- BorrowerActions.drawDebt():
		- Loans.update():
			- _upsert():
				- insert or update loan in loans array
			- remove():
				- remove loan from loans array
			- update borrower in address => borrower mapping
	- increment poolBalances.pledgedCollateral accumulator
	- increment poolBalances.t0Debt accumulator
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- BorrowerActions.drawDebt()
		- borrower not sender BorrowerNotSender()
		- borrower debt less than pool min debt AmountLTMinDebt()
		- limit price reached LimitIndexExceeded()
		- borrower cannot draw more debt BorrowerUnderCollateralized()

	emit events:
	- BorrowerActions.drawDebt():
	- DrawDebt
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### repayDebt
	external libraries call:
	- PoolCommons.accrueInterest()
	- BorrowerActions.repayDebt()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- BorrowerActions.repayDebt():
		- Loans.update():
			- _upsert():
				- insert or update loan in loans array
			- remove():
				- remove loan from loans array
			- update borrower in address => borrower mapping
	- decrement poolBalances.t0Debt accumulator
	- decrement poolBalances.pledgedCollateral accumulator
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- BorrowerActions.repayDebt():
		- no debt to repay NoDebt()
		- borrower debt less than pool min debt AmountLTMinDebt()
		- borrower not sender BorrowerNotSender()
		- not enough collateral to pull InsufficientCollateral()

	emit events:
	- BorrowerActions.repayDebt():
	- RepayDebt
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### settle
	external libraries call:
	- PoolCommons.accrueInterest()
	- SettlerActions.settlePoolDebt()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- SettlerActions.settlePoolDebt():
		- Deposits.unscaledRemove() (remove amount in Fenwick tree, from index):
			- update values array state
		- Buckets.addCollateral():
			- increment bucket.collateral and bucket.lps accumulator
			- addLenderLP():
				- increment lender.lps accumulator and lender.depositTime state
		- SettlerActions._settleAuction():
			- _removeAuction():
				- decrement kicker locked accumulator, increment kicker claimable accumumlator
				- decrement auctions count accumulator
				- decrement auctions.totalBondEscrowed accumulator
				- update auction queue state
		- update borrower state
	- decrement poolBalances.t0Debt accumulator
	- decrement poolBalances.t0DebtInAuction accumulator
	- decrement poolBalances.pledgedCollateral accumulator
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- SettlerActions.settlePoolDebt():
		- loan not kicked NoAuction()
		- 72 hours didn't pass and auction still has collateral AuctionNotClearable()

	emit events:
	- SettlerActions.settlePoolDebt():
		- Settle
		- SettlerActions._settleAuction():
			- AuctionNFTSettle or AuctionSettle
		- BucketBankruptcy
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### take
	external libraries call:
	- PoolCommons.accrueInterest()
	- TakerActions.take()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- TakerActions.take():
		- _take():
			- _rewardTake():
				- update liquidation bond size accumulator
				- update kicker's locked balance accumulator
				- update auctions.totalBondEscrowed accumulator
		- _takeLoan():
			- SettlerActions._settleAuction():
				- _removeAuction():
					- decrement kicker locked accumulator, increment kicker claimable accumumlator
					- decrement auctions count accumulator
					- decrement auctions.totalBondEscrowed accumulator
					- update auction queue state
			- Loans.update():
				- _upsert():
					- insert or update loan in loans array
				- remove():
					- remove loan from loans array
				- update borrower in address => borrower mapping
	- decrement poolBalances.t0Debt accumulator
	- decrement poolBalances.t0DebtInAuction accumulator
	- decrement poolBalances.pledgedCollateral accumulator
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- TakerActions.take():
		- insufficient collateral InsufficientCollateral()
		- _prepareTake():
			- loan is not in auction NoAuction()
		- _takeLoan():
			- borrower debt less than pool min debt AmountLTMinDebt()

	emit events:
	- TakerActions.take():
		- Take
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### bucketTake
	external libraries call:
	- PoolCommons.accrueInterest()
	- TakerActions.bucketTake()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- TakerActions.bucketTake():
		- _takeBucket():
			- _rewardBucketTake():
				- Buckets.addLenderLP:
					- increment taker lender.lps accumulator and lender.depositTime state
					- increment kicker lender.lps accumulator and lender.depositTime state
				- update liquidation bond size accumulator
				- update kicker's locked balance accumulator
				- update auctions.totalBondEscrowed accumulator
				- Deposits.unscaledRemove() (remove amount in Fenwick tree, from index):
					- update values array state
				- increment bucket.collateral and bucket.lps accumulator
		- _takeLoan():
			- SettlerActions._settleAuction():
				- _removeAuction():
					- decrement kicker locked accumulator, increment kicker claimable accumumlator
					- decrement auctions count accumulator
					- decrement auctions.totalBondEscrowed accumulator
					- update auction queue state
			- Loans.update():
				- _upsert():
					- insert or update loan in loans array
				- remove():
					- remove loan from loans array
				- update borrower in address => borrower mapping
	- decrement poolBalances.t0Debt accumulator
	- decrement poolBalances.t0DebtInAuction accumulator
	- decrement poolBalances.pledgedCollateral accumulator
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- TakerActions.bucketTake():
		- insufficient collateral InsufficientCollateral()
		- _prepareTake():
			- loan is not in auction NoAuction()
		- _takeLoan():
			- borrower debt less than pool min debt AmountLTMinDebt()

	emit events:
	- TakerActions.bucketTake():
		- _rewardBucketTake():
			- BucketTakeLPAwarded
		- BucketTake
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

## ERC721Pool contract

### addCollateral
	external libraries call:
	- PoolCommons.accrueInterest()
	- LenderActions.addCollateral()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state 
    	- increment reserveAuction.totalInterestEarned accumulator
	- LenderActions.addCollateral():
		- Buckets.addCollateral():
			- increment bucket.collateral and bucket.lps accumulator
			- addLenderLP():
				- increment lender.lps accumulator and lender.depositTime state
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- LenderActions.addCollateral():
		- invalid bucket index InvalidIndex()

	emit events:
	- AddCollateralNFT
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate

### removeCollateral
	external libraries call:
	- PoolCommons.accrueInterest()
	- LenderActions.removeCollateral()
	- PoolCommons.updateInterestRate()

	write state:
	- _accruePoolInterest():
		- PoolCommons.accrueInterest():
			- Deposits.mult() (scale Fenwick tree with new interest accrued):
				- update scaling array state
		- increment reserveAuction.totalInterestEarned accumulator
	- LenderActions.removeCollateral():
		- decrement lender.lps accumulator
		- decrement bucket.collateral and bucket.lps accumulator
	- _updateInterestState():
		- PoolCommons.updateInterestRate():
			- interest debt and lup * collateral EMAs accumulators
			- interest rate accumulator and interestRateUpdate state
		- pool inflator and inflatorUpdate state

	reverts on:
	- LenderActions.removeCollateral():
		- not enough collateral InsufficientCollateral()
		- insufficient LP InsufficientLP()

	emit events:
	- RemoveCollateral
	- PoolCommons.updateInterestRate():
		- UpdateInterestRate
