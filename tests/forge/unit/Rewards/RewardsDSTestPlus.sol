// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import 'src/RewardsManager.sol';
import 'src/PoolInfoUtils.sol';
import 'src/PositionManager.sol';

import 'src/interfaces/rewards/IRewardsManager.sol';
import 'src/interfaces/position/IPositionManager.sol';

import '@openzeppelin/contracts/token/ERC20/ERC20.sol';

import { Token }               from '../../utils/Tokens.sol';
import { Strings }             from '@openzeppelin/contracts/utils/Strings.sol';

import { IPoolErrors }         from 'src/interfaces/pool/commons/IPoolErrors.sol';
import { ERC20Pool }           from 'src/ERC20Pool.sol';
import { PositionManager }     from 'src/PositionManager.sol';

import { ERC20HelperContract } from '../ERC20Pool/ERC20DSTestPlus.sol';
import { IRewardsManagerEvents } from 'src/interfaces/rewards/IRewardsManagerEvents.sol';

abstract contract RewardsDSTestPlus is IRewardsManagerEvents, ERC20HelperContract {

    address internal _minterOne;
    address internal _minterTwo;
    address internal _minterThree;
    address internal _minterFour;
    address internal _minterFive;

    ERC20 internal _ajnaToken;

    IPool            internal _poolTwo;
    IRewardsManager  internal _rewardsManager;
    IPositionManager internal _positionManager;

    uint256 internal REWARDS_CAP = 0.8 * 1e18;

    struct MintAndMemorializeParams {
        uint256[] indexes;
        address minter;
        uint256 mintAmount;
        IPool pool;
    }

    struct TriggerReserveAuctionParams {
        address borrower;
        uint256 borrowAmount;
        uint256 limitIndex;
        IPool pool;
    }

    function _stakeToken(address pool, address owner, uint256 tokenId) internal {
        changePrank(owner);

        // approve and deposit NFT into rewards contract
        PositionManager(address(_positionManager)).approve(address(_rewardsManager), tokenId);
        vm.expectEmit(true, true, true, true);
        emit Stake(owner, address(pool), tokenId);
        _rewardsManager.stake(tokenId);

        // check token was transferred to rewards contract
        (address ownerInf, address poolInf, ) = _rewardsManager.getStakeInfo(tokenId);
        assertEq(PositionManager(address(_positionManager)).ownerOf(tokenId), address(_rewardsManager));
        assertEq(ownerInf, owner);
        assertEq(poolInf, pool);
    }

    function _unstakeToken(
        address owner,
        address pool,
        uint256[] memory claimedArray,
        uint256 tokenId,
        uint256 reward,
        uint256[] memory indexes,
        uint256 updateExchangeRatesReward
    ) internal {

        changePrank(owner);

        // when the token is unstaked updateExchangeRates emits
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(owner, pool, indexes, updateExchangeRatesReward);

        // when the token is unstaked claimRewards emits
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(owner, pool,  tokenId, claimedArray, reward);

        // when the token is unstaked unstake emits
        vm.expectEmit(true, true, true, true);
        emit Unstake(owner, address(pool), tokenId);
        _rewardsManager.unstake(tokenId);
        assertEq(PositionManager(address(_positionManager)).ownerOf(tokenId), owner);

        // check token was transferred from rewards contract to minter
        assertEq(PositionManager(address(_positionManager)).ownerOf(tokenId), owner);

        // invariant: all bucket snapshots are removed for the token id that was unstaken
        for (uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (uint256 lps, uint256 rate) = _rewardsManager.getBucketStateStakeInfo(tokenId, bucketIndex);
            assertEq(lps, 0);
            assertEq(rate, 0);
        }

        (address ownerInf, address poolInf, uint256 interactionBlockInf) = _rewardsManager.getStakeInfo(tokenId);
        assertEq(ownerInf, address(0));
        assertEq(poolInf, address(0));
        assertEq(interactionBlockInf, 0);
    }

    function _assertBurn(
        address pool,
        uint256 epoch,
        uint256 timestamp,
        uint256 interest,
        uint256 burned,
        uint256 tokensToBurn
        ) internal {

        (uint256 bETimestamp, uint256 bEInterest, uint256 bEBurned) = IPool(pool).burnInfo(epoch);

        assertEq(bETimestamp, timestamp);
        assertEq(bEInterest,  interest);
        assertEq(bEBurned,    burned);
        assertEq(burned,      tokensToBurn);
    }


    function _updateExchangeRates(
        address updater,
        address pool,
        uint256[] memory indexes,
        uint256 reward
    ) internal {
        changePrank(updater);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(updater, pool, indexes, reward);
        _rewardsManager.updateBucketExchangeRatesAndClaim(pool, indexes);
    }


    function _epochsClaimedArray(uint256 numberOfAuctions_, uint256 lastClaimed_) internal pure returns (uint256[] memory epochsClaimed_) {
        epochsClaimed_ = new uint256[](numberOfAuctions_);
        uint256 claimEpoch = lastClaimed_; // starting index, not inclusive

        for (uint256 i = 0; i < numberOfAuctions_; i++) {
            epochsClaimed_[i] = claimEpoch + 1;
            claimEpoch += 1;
        }
    }

    function _claimRewards(
        address from,
        address pool,
        uint256 tokenId,
        uint256 reward,
        uint256[] memory epochsClaimed
    ) internal {
        changePrank(from);
        uint256 fromAjnaBal = _ajnaToken.balanceOf(from);

        uint256 currentBurnEpoch = IPool(pool).currentBurnEpoch();
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(from, pool, tokenId, epochsClaimed, reward);
        _rewardsManager.claimRewards(tokenId, currentBurnEpoch);

        assertEq(_ajnaToken.balanceOf(from), fromAjnaBal + reward);
    }

    function _moveStakedLiquidity(
        address from,
        uint256 tokenId,
        uint256[] memory fromIndexes,
        uint256[] memory lpsRedeemed,
        bool fromIndStaked,
        uint256[] memory toIndexes,
        uint256[] memory lpsAwarded,
        uint256 expiry
    ) internal {
        
        changePrank(from);

        // check MoveLiquidity emits
        for (uint256 i = 0; i < fromIndexes.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit MoveLiquidity(address(_rewardsManager), tokenId, fromIndexes[i], toIndexes[i], lpsRedeemed[i], lpsAwarded[i]);
        }

        vm.expectEmit(true, true, true, true);
        emit MoveStakedLiquidity(tokenId, fromIndexes, toIndexes);

        if (fromIndStaked) {
            // check exchange rates are updated
            vm.expectEmit(true, true, true, true);
            emit UpdateExchangeRates(_minterOne, address(_pool), toIndexes, 0);
        }
        _rewardsManager.moveStakedLiquidity(tokenId, fromIndexes, toIndexes, expiry);

    }

    function _assertNotOwnerOfDepositRevert(address from , uint256 tokenId) internal {
        // check only deposit owner can claim rewards
        changePrank(from);
        uint256 currentBurnEpoch = _pool.currentBurnEpoch();
        vm.expectRevert(IRewardsManagerErrors.NotOwnerOfDeposit.selector);
        _rewardsManager.claimRewards(tokenId, currentBurnEpoch);
    }

    function _assertNotOwnerOfDepositUnstakeRevert(address from , uint256 tokenId) internal {
        // check only deposit owner can claim rewards
        changePrank(from);
        uint256 currentBurnEpoch = _pool.currentBurnEpoch();
        vm.expectRevert(IRewardsManagerErrors.NotOwnerOfDeposit.selector);
        _rewardsManager.claimRewards(tokenId, currentBurnEpoch);
    }

    function _assertAlreadyClaimedRevert(address from , uint256 tokenId) internal {
        // check only deposit owner can claim rewards
        changePrank(from);
        uint256 currentBurnEpoch = _pool.currentBurnEpoch();
        vm.expectRevert(IRewardsManagerErrors.AlreadyClaimed.selector);
        _rewardsManager.claimRewards(tokenId, currentBurnEpoch);
    }

    function _assertStake(
        address owner,
        address pool,
        uint256 tokenId,
        uint256 burnEvent,
        uint256 rewardsEarned
    ) internal {
        uint256 currentBurnEpoch = _pool.currentBurnEpoch();
        (address ownerInf, address poolInf, uint256 interactionBurnEvent) = _rewardsManager.getStakeInfo(tokenId);
        uint256 rewardsEarnedInf = _rewardsManager.calculateRewards(tokenId, currentBurnEpoch);

        assertEq(ownerInf, owner);
        assertEq(poolInf, pool);
        assertEq(interactionBurnEvent, burnEvent);
        assertEq(rewardsEarnedInf, rewardsEarned);
        assertEq(PositionManager(address(_positionManager)).ownerOf(tokenId), address(_rewardsManager));
    }
}

abstract contract RewardsHelperContract is RewardsDSTestPlus {

    address         internal _bidder;
    address         internal _updater;
    address         internal _updater2;

    Token internal _collateralOne;
    Token internal _quoteOne;
    Token internal _collateralTwo;
    Token internal _quoteTwo;

    constructor() {
        vm.makePersistent(_ajna);

        _ajnaToken       = ERC20(_ajna);
        _positionManager = new PositionManager(_poolFactory, new ERC721PoolFactory(_ajna));
        _rewardsManager  = new RewardsManager(_ajna, _positionManager);

        _collateralOne = new Token("Collateral 1", "C1");
        _quoteOne      = new Token("Quote 1", "Q1");
        _collateralTwo = new Token("Collateral 2", "C2");
        _quoteTwo      = new Token("Quote 2", "Q2");

        _poolTwo       = ERC20Pool(_poolFactory.deployPool(address(_collateralTwo), address(_quoteTwo), 0.05 * 10**18));

        // provide initial ajna tokens to staking rewards contract
        deal(_ajna, address(_rewardsManager), 100_000_000 * 1e18);
        assertEq(_ajnaToken.balanceOf(address(_rewardsManager)), 100_000_000 * 1e18);
    }

    // create a new test borrower with quote and collateral sufficient to draw a specified amount of debt
    function _createTestBorrower(address pool, address borrower, uint256 borrowAmount, uint256 limitIndex) internal returns (uint256 collateralToPledge_) {

        changePrank(borrower);
        Token collateral = Token(ERC20Pool(address(pool)).collateralAddress());
        Token quote = Token(ERC20Pool(address(pool)).quoteTokenAddress());
        // deal twice as much quote so the borrower has sufficient quote to repay the loan
        deal(address(quote), borrower, Maths.wmul(borrowAmount, Maths.wad(2)));

        // approve tokens
        collateral.approve(address(pool), type(uint256).max);
        quote.approve(address(pool), type(uint256).max);

        collateralToPledge_ = _requiredCollateral(borrowAmount, limitIndex);
        deal(address(collateral), borrower, collateralToPledge_);
    }

    function _triggerReserveAuctionsNoTake(
        address borrower,
        address pool,
        uint256 borrowAmount,
        uint256 limitIndex
    ) internal {
        // create a new borrower to write state required for reserve auctions
        uint256 collateralToPledge = _createTestBorrower(address(pool), borrower, borrowAmount, limitIndex);

        // borrower drawsDebt from the pool
        ERC20Pool(address(pool)).drawDebt(borrower, borrowAmount, limitIndex, collateralToPledge);

        // allow time to pass for interest to accumulate
        skip(26 weeks);

        // borrower repays some of their debt, providing reserves to be claimed
        // don't pull any collateral, as such functionality is unrelated to reserve auctions
        ERC20Pool(address(pool)).repayDebt(borrower, Maths.wdiv(borrowAmount, Maths.wad(2)), 0, borrower, MAX_FENWICK_INDEX);

        // start reserve auction
        _kickReserveAuction(address(pool), _bidder);
    }

    function _kickReserveAuction(
        address pool,
        address bidder
    ) internal {
        changePrank(bidder);
        _ajnaToken.approve(address(pool), type(uint256).max);
        ERC20Pool(address(pool)).kickReserveAuction();
    }

    function _mintAndMemorializePositionNFT(
        address minter,
        uint256 mintAmount,
        address pool,
        uint256[] memory indexes
    ) internal returns (uint256 tokenId_) {
        changePrank(minter);

        Token collateral = Token(ERC20Pool(address(pool)).collateralAddress());
        Token quote = Token(ERC20Pool(address(pool)).quoteTokenAddress());

        // deal tokens to the minter
        deal(address(quote), minter, mintAmount * indexes.length);

        // approve tokens
        collateral.approve(address(pool), type(uint256).max);
        quote.approve(address(pool), type(uint256).max);

        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(minter, address(pool), keccak256("ERC20_NON_SUBSET_HASH"));
        tokenId_ = _positionManager.mint(mintParams);

        uint256[] memory lpBalances = new uint256[](indexes.length);

        for (uint256 i = 0; i < indexes.length; i++) {
            ERC20Pool(address(pool)).addQuoteToken(mintAmount, indexes[i], type(uint256).max);
            (lpBalances[i], ) = ERC20Pool(address(pool)).lenderInfo(indexes[i], minter);
        }

        ERC20Pool(address(pool)).increaseLPAllowance(address(_positionManager), indexes, lpBalances);

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId_, indexes
        );

        _positionManager.memorializePositions(memorializeParams);

        // register position manager as lender at memorialized indexes (for LP test assertions)
        _registerLender(address(_positionManager), indexes);
    }

    function _triggerReserveAuctions(
        address borrower,
        address pool,
        uint256 borrowAmount,
        uint256 limitIndex,
        uint256 tokensToBurn
    ) internal returns (uint256 tokensBurned_) {

        // fund borrower to write state required for reserve auctions
        changePrank(borrower);
        Token collateral = Token(ERC20Pool(address(pool)).collateralAddress());
        Token quote = Token(ERC20Pool(address(pool)).quoteTokenAddress());
        deal(address(quote), borrower, borrowAmount);

        // approve tokens
        collateral.approve(address(pool), type(uint256).max);
        quote.approve(address(pool), type(uint256).max);

        uint256 collateralToPledge = _requiredCollateral(borrowAmount, limitIndex);
        deal(address(_collateral), borrower, collateralToPledge);

        // borrower drawsDebt from the pool
        ERC20Pool(address(pool)).drawDebt(borrower, borrowAmount, limitIndex, collateralToPledge);

        // allow time to pass for interest to accumulate
        skip(26 weeks);

        // borrower repays some of their debt, providing reserves to be claimed
        // don't pull any collateral, as such functionality is unrelated to reserve auctions
        ERC20Pool(address(pool)).repayDebt(borrower, borrowAmount, 0, borrower, MAX_FENWICK_INDEX);

        // start reserve auction
        changePrank(_bidder);
        _ajnaToken.approve(address(pool), type(uint256).max);
        ERC20Pool(address(pool)).kickReserveAuction();

        // Can't trigger reserve auction if less than two weeks have passed since last auction
        vm.expectRevert(IPoolErrors.ReserveAuctionTooSoon.selector);
        ERC20Pool(address(pool)).kickReserveAuction();

        // allow time to pass for the reserve price to decrease
        skip(24 hours);

        _takeReserves(pool, _bidder);

        (,, tokensBurned_) = IPool(pool).burnInfo(IPool(pool).currentBurnEpoch());
        assertEq(tokensBurned_, tokensToBurn);

        return tokensBurned_;
    }

    function _triggerReserveAuctionsBurnUnknown(
        address borrower,
        address pool,
        uint256 borrowAmount,
        uint256 limitIndex
    ) internal returns (uint256 tokensBurned_) {

        // fund borrower to write state required for reserve auctions
        changePrank(borrower);
        Token collateral = Token(ERC20Pool(address(pool)).collateralAddress());
        Token quote = Token(ERC20Pool(address(pool)).quoteTokenAddress());
        deal(address(quote), borrower, borrowAmount);

        // approve tokens
        collateral.approve(address(pool), type(uint256).max);
        quote.approve(address(pool), type(uint256).max);

        uint256 collateralToPledge = _requiredCollateral(borrowAmount, limitIndex);
        deal(address(_collateral), borrower, collateralToPledge);

        // borrower drawsDebt from the pool
        ERC20Pool(address(pool)).drawDebt(borrower, borrowAmount, limitIndex, collateralToPledge);

        // allow time to pass for interest to accumulate
        skip(26 weeks);

        // borrower repays some of their debt, providing reserves to be claimed
        // don't pull any collateral, as such functionality is unrelated to reserve auctions
        ERC20Pool(address(pool)).repayDebt(borrower, borrowAmount, 0, borrower, MAX_FENWICK_INDEX);

        // start reserve auction
        changePrank(_bidder);
        _ajnaToken.approve(address(pool), type(uint256).max);
        ERC20Pool(address(pool)).kickReserveAuction();

        // Can't trigger reserve auction if less than two weeks have passed since last auction
        vm.expectRevert(IPoolErrors.ReserveAuctionTooSoon.selector);
        ERC20Pool(address(pool)).kickReserveAuction();

        // allow time to pass for the reserve price to decrease
        skip(24 hours);

        _takeReserves(pool, _bidder);

        (,, tokensBurned_) = IPool(pool).burnInfo(IPool(pool).currentBurnEpoch());

        return tokensBurned_;
    }

    function _takeReserves(address pool, address from) internal {
        changePrank(from);
        (
            ,
            ,
            uint256 curClaimableReservesRemaining,
            ,
        ) = _poolUtils.poolReservesInfo(pool);

        ERC20Pool(pool).takeReserves(curClaimableReservesRemaining);
    }

    function _requiredCollateral(ERC20Pool pool_, uint256 borrowAmount, uint256 indexPrice) internal view returns (uint256 requiredCollateral_) {
        // calculate the required collateral based upon the borrow amount and index price
        (uint256 interestRate, ) = pool_.interestRateInfo();
        uint256 newInterestRate = Maths.wmul(interestRate, 1.1 * 10**18); // interest rate multipled by increase coefficient
        uint256 expectedDebt = Maths.wmul(borrowAmount, _borrowFeeRate(newInterestRate) + Maths.WAD);
        requiredCollateral_ = Maths.wdiv(expectedDebt, _poolUtils.indexToPrice(indexPrice)) + Maths.WAD;
    }
    
    // Helper function that returns a random subset from array
    function _getRandomSubsetFromArray(uint256[] memory array) internal returns (uint256[] memory subsetArray) {
        uint256[] memory copyOfArray = new uint256[](array.length);
        for (uint j = 0; j < copyOfArray.length; j++){
            copyOfArray[j] = array[j];
        }
        uint256 randomNoOfNfts = randomInRange(1, copyOfArray.length);
        subsetArray = new uint256[](randomNoOfNfts);
        for (uint256 i = 0; i < randomNoOfNfts; i++) {
            uint256 randomIndex = randomInRange(0, copyOfArray.length - i - 1);
            subsetArray[i] = copyOfArray[randomIndex];
            copyOfArray[randomIndex] = copyOfArray[copyOfArray.length - i - 1];
        }
    }

    // Returns N addresses array
    function _getAddresses(uint256 noOfAddress) internal returns(address[] memory addresses_) {
        addresses_ = new address[](noOfAddress);
        for (uint i = 0; i < noOfAddress; i++) {
            addresses_[i] = makeAddr(string(abi.encodePacked("Minter", Strings.toString(i))));
        }
    }
}
