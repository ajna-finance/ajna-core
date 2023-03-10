// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { Strings } from '@openzeppelin/contracts/utils/Strings.sol';

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/ERC20PoolFactory.sol';

import 'src/RewardsManager.sol';
import 'src/interfaces/rewards/IRewardsManager.sol';

import 'src/interfaces/position/IPositionManager.sol';
import 'src/PositionManager.sol';
import 'src/PoolInfoUtils.sol';
import { IPoolErrors } from 'src/interfaces/pool/commons/IPoolErrors.sol';

import { _borrowFeeRate } from 'src/libraries/helpers/PoolHelper.sol';

import { Token }       from './utils/Tokens.sol';
import { ERC20HelperContract } from './ERC20Pool/ERC20DSTestPlus.sol';

contract RewardsManagerTest is ERC20HelperContract {

    address         internal _bidder;
    address         internal _minterOne;
    address         internal _minterTwo;
    address         internal _minterThree;
    address         internal _minterFour;
    address         internal _minterFive;
    address         internal _updater;
    address         internal _updater2;

    ERC20           internal _ajnaToken;

    RewardsManager   internal _rewardsManager;
    PositionManager  internal _positionManager;

    Token           internal _collateralOne;
    Token           internal _quoteOne;
    ERC20Pool       internal _poolOne;
    Token           internal _collateralTwo;
    Token           internal _quoteTwo;
    ERC20Pool       internal _poolTwo;

    event ClaimRewards(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256[] epochsClaimed, uint256 amount);
    event Stake(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);
    event UpdateExchangeRates(address indexed caller, address indexed ajnaPool, uint256[] indexesUpdated, uint256 rewardsClaimed);
    event Unstake(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);
    event MoveStakedLiquidity(
        uint256 tokenId,
        uint256[] fromIndexes,
        uint256[] toIndexes
    );

    uint256 constant BLOCKS_IN_DAY = 7200;
    mapping (uint256 => address) internal tokenIdToMinter;
    mapping (address => uint256) internal minterToBalance;

    struct MintAndMemorializeParams {
        uint256[] indexes;
        address minter;
        uint256 mintAmount;
        ERC20Pool pool;
    }

    struct TriggerReserveAuctionParams {
        uint256 borrowAmount;
        uint256 limitIndex;
        ERC20Pool pool;
    }

    function setUp() external {
        vm.makePersistent(_ajna);

        _ajnaToken       = ERC20(_ajna);
        _positionManager = new PositionManager(_poolFactory, new ERC721PoolFactory(_ajna));
        _rewardsManager  = new RewardsManager(_ajna, _positionManager);
        _poolUtils       = new PoolInfoUtils();

        _collateralOne = new Token("Collateral 1", "C1");
        _quoteOne      = new Token("Quote 1", "Q1");
        _poolOne       = ERC20Pool(_poolFactory.deployPool(address(_collateralOne), address(_quoteOne), 0.05 * 10**18));

        _collateralTwo = new Token("Collateral 2", "C2");
        _quoteTwo      = new Token("Quote 2", "Q2");
        _poolTwo       = ERC20Pool(_poolFactory.deployPool(address(_collateralTwo), address(_quoteTwo), 0.05 * 10**18));

        // provide initial ajna tokens to staking rewards contract
        deal(_ajna, address(_rewardsManager), 100_000_000 * 1e18);
        assertEq(_ajnaToken.balanceOf(address(_rewardsManager)), 100_000_000 * 1e18);

        // instantiate test minters
        _minterOne   = makeAddr("minterOne");
        _minterTwo   = makeAddr("minterTwo");
        _minterThree = makeAddr("minterThree");
        _minterFour  = makeAddr("minterFour");
        _minterFive  = makeAddr("minterFive");

        // instantiate test bidder
        _bidder    = makeAddr("bidder");
        changePrank(_bidder);
        deal(_ajna, _bidder, 900_000_000 * 10**18);

        // instantiate test updater
        _updater     = makeAddr("updater");
        _updater2    = makeAddr("updater2");
    }

    // create a new test borrower with quote and collateral sufficient to draw a specified amount of debt
    function _createTestBorrower(ERC20Pool pool_, string memory borrowerName_, uint256 borrowAmount_, uint256 limitIndex_) internal returns (address borrower_, uint256 collateralToPledge_) {
        borrower_ = makeAddr(borrowerName_);

        changePrank(borrower_);

        Token collateral = Token(pool_.collateralAddress());
        Token quote = Token(pool_.quoteTokenAddress());

        // deal twice as much quote so the borrower has sufficient quote to repay the loan
        deal(address(quote), borrower_, Maths.wmul(borrowAmount_, Maths.wad(2)));

        // approve tokens
        collateral.approve(address(pool_), type(uint256).max);
        quote.approve(address(pool_), type(uint256).max);

        collateralToPledge_ = _requiredCollateral(pool_, borrowAmount_, limitIndex_);
        deal(address(collateral), borrower_, collateralToPledge_);
    }

    function _stakeToken(address pool_, address owner_, uint256 tokenId_) internal {
        changePrank(owner_);

        // approve and deposit NFT into rewards contract
        _positionManager.approve(address(_rewardsManager), tokenId_);
        vm.expectEmit(true, true, true, true);
        emit Stake(owner_, address(pool_), tokenId_);
        _rewardsManager.stake(tokenId_);

        // check token was transferred to rewards contract
        assertEq(_positionManager.ownerOf(tokenId_), address(_rewardsManager));
    }

    function _unstakeToken(
        address minter,
        address pool,
        uint256[] memory claimedArray,
        uint256 tokenId,
        uint256 reward,
        uint256 updateRatesReward
    ) internal {

        changePrank(minter);

        if (updateRatesReward != 0) {
            vm.expectEmit(true, true, true, true);
            emit UpdateExchangeRates(_minterOne, address(_poolOne), _positionManager.getPositionIndexes(tokenId), updateRatesReward);
        }

        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(minter, pool,  tokenId, claimedArray, reward);
        vm.expectEmit(true, true, true, true);
        emit Unstake(minter, address(pool), tokenId);
        _rewardsManager.unstake(tokenId);
        assertEq(_positionManager.ownerOf(tokenId), minter);

        // check token was transferred from rewards contract to minter
        assertEq(_positionManager.ownerOf(tokenId), address(minter));

        // invariant: all bucket snapshots are removed for the token id that was unstaken
        for(uint256 bucketIndex = 0; bucketIndex <= 7388; bucketIndex++) {
            (uint256 lps, uint256 rate) = _rewardsManager.getBucketStateStakeInfo(tokenId, bucketIndex);
            assertEq(lps, 0);
            assertEq(rate, 0);
        }
    }

    function _triggerReserveAuctionsNoTake(TriggerReserveAuctionParams memory params_) internal {
        // create a new borrower to write state required for reserve auctions
        (
            address borrower,
            uint256 collateralToPledge
        ) = _createTestBorrower(params_.pool, string("borrower"), params_.borrowAmount, params_.limitIndex);

        // borrower drawsDebt from the pool
        params_.pool.drawDebt(borrower, params_.borrowAmount, params_.limitIndex, collateralToPledge);

        // allow time to pass for interest to accumulate
        skip(26 weeks);

        // borrower repays some of their debt, providing reserves to be claimed
        // don't pull any collateral, as such functionality is unrelated to reserve auctions
        params_.pool.repayDebt(borrower, Maths.wdiv(params_.borrowAmount, Maths.wad(2)), 0, borrower, MAX_FENWICK_INDEX);

        // start reserve auction
        changePrank(_bidder);
        _ajnaToken.approve(address(params_.pool), type(uint256).max);
        params_.pool.startClaimableReserveAuction();
    }

    function _assertBurn(
        address pool,
        uint256 epoch,
        uint256 timestamp,
        uint256 interest,
        uint256 burned
        ) internal {

        (uint256 bETimestamp, uint256 bEInterest, uint256 bEBurned) = IPool(pool).burnInfo(epoch);

        assertEq(bETimestamp, timestamp);
        assertEq(bEInterest,  interest);
        assertEq(bEBurned,    burned);
    }


    function _updateExchangeRates(address updater, address pool, uint256[] memory depositIndexes, uint256 reward) internal {
        uint256 initialUpdaterTokenBalance = _ajnaToken.balanceOf(updater);

        changePrank(updater);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(updater, pool, depositIndexes, reward);
        _rewardsManager.updateBucketExchangeRatesAndClaim(pool, depositIndexes);
        assertEq(_ajnaToken.balanceOf(updater), initialUpdaterTokenBalance + reward);
    }


    function _epochsClaimedArray(uint256 numberOfAuctions_, uint256 lastClaimed_) internal pure returns (uint256[] memory epochsClaimed_) {
        epochsClaimed_ = new uint256[](numberOfAuctions_);
        uint256 claimEpoch = lastClaimed_; // starting index, not inclusive

        for (uint256 i = 0; i < numberOfAuctions_; i++) {
            epochsClaimed_[i] = claimEpoch + 1;
            claimEpoch += 1;
        }
    }

    function _mintAndMemorializePositionNFT(MintAndMemorializeParams memory params_) internal returns (uint256 tokenId_) {
        changePrank(params_.minter);

        Token collateral = Token(params_.pool.collateralAddress());
        Token quote = Token(params_.pool.quoteTokenAddress());

        // deal tokens to the minter
        deal(address(collateral), params_.minter, 250_000 * 1e18);
        deal(address(quote), params_.minter, params_.mintAmount * params_.indexes.length);

        // approve tokens
        collateral.approve(address(params_.pool), type(uint256).max);
        quote.approve(address(params_.pool), type(uint256).max);

        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(params_.minter, address(params_.pool), keccak256("ERC20_NON_SUBSET_HASH"));
        tokenId_ = _positionManager.mint(mintParams);

        uint256[] memory lpBalances = new uint256[](params_.indexes.length);

        for (uint256 i = 0; i < params_.indexes.length; i++) {
            params_.pool.addQuoteToken(params_.mintAmount, params_.indexes[i], type(uint256).max);
            (lpBalances[i], ) = params_.pool.lenderInfo(params_.indexes[i], params_.minter);
        }

        params_.pool.increaseLPsAllowance(address(_positionManager), params_.indexes, lpBalances);

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId_, params_.indexes
        );

        _positionManager.memorializePositions(memorializeParams);

        // register position manager as lender at memorialized indexes (for LP test assertions)
        _registerLender(address(_positionManager), params_.indexes);
    }

    function _triggerReserveAuctions(TriggerReserveAuctionParams memory params_) internal returns (uint256 tokensBurned_) {
        // create a new borrower to write state required for reserve auctions
        address borrower = makeAddr("borrower");

        changePrank(borrower);

        Token collateral = Token(params_.pool.collateralAddress());
        Token quote = Token(params_.pool.quoteTokenAddress());

        deal(address(quote), borrower, params_.borrowAmount);

        // approve tokens
        collateral.approve(address(params_.pool), type(uint256).max);
        quote.approve(address(params_.pool), type(uint256).max);

        uint256 collateralToPledge = _requiredCollateral(params_.pool, params_.borrowAmount, params_.limitIndex);
        deal(address(collateral), borrower, collateralToPledge);

        // borrower drawsDebt from the pool
        params_.pool.drawDebt(borrower, params_.borrowAmount, params_.limitIndex, collateralToPledge);

        // allow time to pass for interest to accumulate
        skip(26 weeks);

        // borrower repays some of their debt, providing reserves to be claimed
        // don't pull any collateral, as such functionality is unrelated to reserve auctions
        params_.pool.repayDebt(borrower, params_.borrowAmount, 0, borrower, MAX_FENWICK_INDEX);

        // start reserve auction
        changePrank(_bidder);
        _ajnaToken.approve(address(params_.pool), type(uint256).max);
        params_.pool.startClaimableReserveAuction();

        // Can't trigger reserve auction if less than two weeks have passed since last auction
        vm.expectRevert(IPoolErrors.ReserveAuctionTooSoon.selector);
        params_.pool.startClaimableReserveAuction();

        // allow time to pass for the reserve price to decrease
        skip(24 hours);

        (
            ,
            ,
            uint256 curClaimableReservesRemaining,
            ,
        ) = _poolUtils.poolReservesInfo(address(params_.pool));

        // take claimable reserves
        params_.pool.takeReserves(curClaimableReservesRemaining);

        (,, tokensBurned_) = IPool(params_.pool).burnInfo(IPool(params_.pool).currentBurnEpoch());
 
        return tokensBurned_;
    }

    function testStakeToken() external {
        skip(10);

        // configure NFT position one
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);

        // configure NFT position two
        depositIndexes = new uint256[](4);
        depositIndexes[0] = 5;
        depositIndexes[1] = 1;
        depositIndexes[2] = 3;
        depositIndexes[3] = 12;
        mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterTwo,
            mintAmount: 1000 * 1e18,
            pool: _poolTwo
        });
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT(mintMemorializeParams);

        // check only owner of an NFT can deposit it into the rewards contract
        changePrank(_minterTwo);
        vm.expectRevert(IRewardsManagerErrors.NotOwnerOfDeposit.selector);
        _rewardsManager.stake(tokenIdOne);

        // minterOne deposits their NFT into the rewards contract
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);
        // check deposit state
        (address owner, address pool, uint256 interactionBurnEvent) = _rewardsManager.getStakeInfo(tokenIdOne);
        assertEq(owner, _minterOne);
        assertEq(pool, address(_poolOne));
        assertEq(interactionBurnEvent, 0);

        // minterTwo deposits their NFT into the rewards contract
        _stakeToken(address(_poolTwo), _minterTwo, tokenIdTwo);
        // check deposit state
        (owner, pool, interactionBurnEvent) = _rewardsManager.getStakeInfo(tokenIdTwo);
        assertEq(owner, _minterTwo);
        assertEq(pool, address(_poolTwo));
        assertEq(interactionBurnEvent, 0);
    }

    function testUpdateExchangeRatesAndClaimRewards() external {
        skip(10);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        // mint memorialize and deposit NFT
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        // borrower takes actions providing reserves enabling reserve auctions
        // bidder takes reserve auctions by providing ajna tokens to be burned
        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });
        uint256 tokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        // call update exchange rate to enable claiming rewards
        changePrank(_updater);
        assertEq(_ajnaToken.balanceOf(_updater), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater, address(_poolOne), depositIndexes, 4.089968908133134320 * 1e18);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater), 4.089968908133134320 * 1e18);

        // check only deposit owner can claim rewards
        uint256 currentBurnEpoch = _poolOne.currentBurnEpoch();
        vm.expectRevert(IRewardsManagerErrors.NotOwnerOfDeposit.selector);
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpoch);

        // check rewards earned
        uint256 rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, currentBurnEpoch);
        assertEq(rewardsEarned, 40.899689081331305425 * 1e18);

        // claim rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), rewardsEarned);
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpoch);
        assertEq(_ajnaToken.balanceOf(_minterOne), rewardsEarned);

        // check can't claim rewards twice
        vm.expectRevert(IRewardsManagerErrors.AlreadyClaimed.selector);
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpoch);

        // check deposit state
        (address owner, address pool, uint256 interactionBurnEvent) = _rewardsManager.getStakeInfo(tokenIdOne);
        assertEq(owner, _minterOne);
        assertEq(pool, address(_poolOne));
        assertEq(interactionBurnEvent, 1);
        assertEq(_positionManager.ownerOf(tokenIdOne), address(_rewardsManager));

        // assert rewards claimed is less than ajna tokens burned cap
        assertLt(_ajnaToken.balanceOf(_minterOne), Maths.wmul(tokensToBurn, 0.800000000000000000 * 1e18));

        // check can't call update exchange rate after the update period has elapsed
        skip(2 weeks);
        // changePrank(_updater);
        // vm.expectRevert(IAjnaRewards.ExchangeRateUpdateTooLate.selector);
        uint256 updateRewards = _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(updateRewards, 0);
    }

    function testWithdrawAndClaimRewardsNoExchangeRateUpdate() external {
        skip(10);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);

        // epoch 0 - 1 is checked for rewards
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 2555,
            pool: _poolOne
        });

        // first reserve auction happens successfully -> epoch 1
        uint256 tokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        // call update exchange rate to enable claiming for epoch 0 - 1
        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_poolOne),
            depositIndexes: depositIndexes,
            reward:         4.089968908133134320 * 1e18
        });

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     0,
            timestamp: 0,
            burned:    0,
            interest:  0
        });

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     1,
            timestamp: block.timestamp - 24 hours,
            burned:    81.799378162662586331 * 1e18,
            interest:  6.443638300196908069 * 1e18
        });

        // second reserve auction happens successfully -> epoch 2
        tokensToBurn += _triggerReserveAuctions(triggerReserveAuctionParams);

        // check owner can withdraw the NFT and rewards will be automatically claimed
        _unstakeToken({
            minter:            _minterOne,
            pool:              address(_poolOne),
            tokenId:           tokenIdOne,
            claimedArray:      _epochsClaimedArray(2, 0),
            reward:            86.809555428378489140 * 1e18,
            updateRatesReward: 4.173624213367915345 * 1e18
        });
    }

    function testWithdrawAndClaimRewardsNoReserveTake() external {

        // healthy epoch, bad epoch

        skip(10);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);

        // epoch 0 - 1 is checked for rewards
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 2555,
            pool: _poolOne
        });


        // first reserve auction happens successfully Staker should receive rewards epoch 0 - 1
        _triggerReserveAuctions(triggerReserveAuctionParams);

        //call update exchange rate to enable claiming rewards for epoch 0 - 1
        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_poolOne),
            depositIndexes: depositIndexes,
            reward:         4.089968908133134320 * 1e18
        });

        skip(2 weeks);

        // first reserve auction happens successfully Staker should receive rewards epoch 0 - 1
        _triggerReserveAuctionsNoTake(triggerReserveAuctionParams);

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     1,
            timestamp: block.timestamp - (2 weeks + 26 weeks + 24 hours),
            burned:    81.799378162662586331 * 1e18,
            interest:  6.443638300196908069 * 1e18
        });

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     2,
            timestamp: block.timestamp,
            burned:    0,
            interest:  0
        });

        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_poolOne),
            depositIndexes: depositIndexes,
            reward:         4.206490995172287125 * 1e18
        });
    }

    // two lenders stake their positions in the pool
    // staker one bucket bankrupt, staker two bucket active
    // interest accrued to both buckets, but staker one receives no rewards
    function testClaimRewardsBankruptBucket() external {

        address borrower = makeAddr("borrower");
        address borrowerTwo = makeAddr("borrowerTwo");

        deal(address(_collateral), borrower, 4 * 1e18);
        changePrank(borrower);
        _collateral.approve(address(_pool), type(uint256).max);
        _quote.approve(address(_pool), type(uint256).max);

        deal(address(_collateral), borrowerTwo, 1_000 * 1e18);
        changePrank(borrowerTwo);
        _collateral.approve(address(_pool), type(uint256).max);
        _quote.approve(address(_pool), type(uint256).max);

        address[] memory transferors = new address[](1);
        transferors[0] = address(_positionManager);

        changePrank(_minterOne);
        deal(address(_quote), _minterOne, 500_000_000 * 1e18);
        _quote.approve(address(_pool), type(uint256).max);
        _quote.approve(address(_positionManager), type(uint256).max);
        _pool.approveLPsTransferors(transferors);

        changePrank(_minterTwo);
        deal(address(_quote), _minterTwo, 500_000_000 * 1e18);
        _quote.approve(address(_pool), type(uint256).max);
        _quote.approve(address(_positionManager), type(uint256).max);
        _pool.approveLPsTransferors(transferors);

        /*****************************/
        /*** Initialize Pool State ***/
        /*****************************/

        // Lender adds Quote token accross 5 prices
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 2_000 * 1e18,
            index:  _i9_91
        });
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 5_000 * 1e18,
            index:  _i9_81
        });
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 11_000 * 1e18,
            index:  _i9_72
        });
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 25_000 * 1e18,
            index:  _i9_62
        });
        _addInitialLiquidity({
            from:   _minterOne,
            amount: 30_000 * 1e18,
            index:  _i9_52
        });

        // first borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     borrower,
            borrower: borrower,
            amount:   2 * 1e18
        });
        _borrow({
            from:       borrower,
            amount:     19.25 * 1e18,
            indexLimit: _i9_91,
            newLup:     9.917184843435912074 * 1e18
        });

        // second borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     borrowerTwo,
            borrower: borrowerTwo,
            amount:   1_000 * 1e18
        });
        _borrow({
            from:       borrowerTwo,
            amount:     7_980 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        _borrow({
            from:       borrowerTwo,
            amount:     1_730 * 1e18,
            indexLimit: _i9_72,
            newLup:     9.721295865031779605 * 1e18
        });

        /*****************************/
        /*** Lenders Deposits NFTs ***/
        /*****************************/

        // set deposit indexes
        uint256[] memory depositIndexes = new uint256[](1);
        uint256[] memory depositIndexes2 = new uint256[](1);
        depositIndexes[0] = _i9_91;
        depositIndexes2[0] = _i9_81;

        ERC20Pool pool = ERC20Pool(address(_pool));

        // stake NFT position one
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 2_000 * 1e18,
            pool: pool
            });
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        changePrank(_minterOne);
        _stakeToken(address(pool), _minterOne, tokenIdOne);

        // stake NFT position two
        mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes2,
            minter: _minterTwo,
            mintAmount: 5_000 * 1e18,
            pool: pool
            });
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT(mintMemorializeParams);
        changePrank(_minterTwo);
        _stakeToken(address(pool), _minterTwo, tokenIdTwo);

        /***********************************/
        /*** Borrower Bankrupts A Bucket ***/
        /***********************************/

        // Skip to make borrower two undercollateralized
        skip(100 days);

        deal(address(_quote), _minterTwo, 500_000_000 * 1e18);

        _kick({
            from:           _minterTwo,
            borrower:       borrowerTwo,
            debt:           9_976.561670003961916237 * 1e18,
            collateral:     1_000 * 1e18,
            bond:           98.533942419792216457 * 1e18,
            transferAmount: 98.533942419792216457 * 1e18
        });

        // skip ahead so take can be called on the loan
        skip(10 hours);

        // take entire collateral
        _take({
            from:            _minterTwo,
            borrower:        borrowerTwo,
            maxCollateral:   1_000 * 1e18,
            bondChange:      6.531114528261135360 * 1e18,
            givenAmount:     653.111452826113536000 * 1e18,
            collateralTaken: 1_000 * 1e18,
            isReward:        true
        });

        _settle({
            from:        _minterTwo,
            borrower:    borrowerTwo,
            maxDepth:    10,
            settledDebt: 9_891.935520844277346922 * 1e18
        });

        // bucket is insolvent, balances are reset
        _assertBucket({
            index:        _i9_91,
            lpBalance:    0, // bucket is bankrupt
            collateral:   0,
            deposit:      0,
            exchangeRate: 1 * 1e18
        });

        // lower priced bucket isn't bankrupt, but exchange rate has decreased
        _assertBucket({
            index:        _i9_81,
            lpBalance:    10_000 * 1e18,
            collateral:   0,
            deposit:      4_936.350384467466066087 * 1e18,
            exchangeRate: 0.493635038446746607 * 1e18
        });

        /***********************/
        /*** Reserve Auction ***/
        /***********************/

        // start reserve auction
        changePrank(_bidder);
        _ajnaToken.approve(address(_pool), type(uint256).max);
        _pool.startClaimableReserveAuction();

        // allow time to pass for the reserve price to decrease
        skip(24 hours);

        (
            ,
            ,
            uint256 curClaimableReservesRemaining,
            ,
        ) = _poolUtils.poolReservesInfo(address(_pool));

        // take claimable reserves
        changePrank(_bidder);
        _pool.takeReserves(curClaimableReservesRemaining);

        /*********************/
        /*** Claim Rewards ***/
        /*********************/

        // _minterOne withdraws and claims rewards, rewards should be 0
        _unstakeToken({
            minter:            _minterOne,
            pool:              address(_pool),
            tokenId:           tokenIdOne,
            claimedArray:      _epochsClaimedArray(1, 0),
            reward:            0,
            updateRatesReward: 0
        });

        // _minterTwo withdraws and claims rewards, rewards should be 0 as their bucket exchange rate decreased
        _unstakeToken({
            minter:            _minterTwo,
            pool:              address(_pool),
            tokenId:           tokenIdTwo,
            claimedArray:      _epochsClaimedArray(1, 0),
            reward:            0,
            updateRatesReward: 0
        });
    }

    function testClaimRewardsCap() external {
        skip(10);
        
        /***************************/
        /*** Lender Deposits NFT ***/
        /***************************/
        
        // set deposit indexes
        uint256[] memory depositIndexes = new uint256[](2);
        uint256[] memory depositIndex1 = new uint256[](1);
        uint256[] memory depositIndex2 = new uint256[](1);
        depositIndexes[0] = 2770;
        depositIndexes[1] = 2771;
        depositIndex1[0] = 2771;
        depositIndex2[0] = 2770;
        
        // configure NFT position one
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 10_000 * 1e18,
            pool: _poolOne
            });
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        changePrank(_minterOne);
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);
        
        /************************************/
        /*** Borrower One Accrue Interest ***/
        /************************************/
        
        // borrower1 borrows
        (address borrower1, uint256 collateralToPledge) = _createTestBorrower(_poolOne, string("borrower1"), 10_000 * 1e18, 2770);
        changePrank(borrower1);
        
        _poolOne.drawDebt(borrower1, 5 * 1e18, 2770, collateralToPledge);

        // pass time to allow interest to accrue
        skip(2 hours);

        // borrower1 repays their loan
        (uint256 debt, , ) = _poolOne.borrowerInfo(borrower1);
        _poolOne.repayDebt(borrower1, debt, 0, borrower1, MAX_FENWICK_INDEX);

        /*****************************/
        /*** First Reserve Auction ***/
        /*****************************/

        // start reserve auction
        changePrank(_bidder);
        _ajnaToken.approve(address(_poolOne), type(uint256).max);
        _poolOne.startClaimableReserveAuction();

        // borrower1 now takes out more debt to accumulate more interest
        changePrank(borrower1);
        _poolOne.drawDebt(borrower1, 2_000 * 1e18, 2770, 0);

        // allow time to pass for the reserve price to decrease
        skip(24 hours);

        (
            ,
            ,
            uint256 curClaimableReservesRemaining,
            ,
        ) = _poolUtils.poolReservesInfo(address(_poolOne));

        // take claimable reserves
        changePrank(_bidder);
        _poolOne.takeReserves(curClaimableReservesRemaining);

        // recorder updates the change in exchange rates in the first index
        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_poolOne),
            depositIndexes: depositIndex1,
            reward:         0.007104600671645296 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater), .007104600671645296 * 1e18);

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     0,
            timestamp: 0,
            burned:    0,
            interest:  0
        });

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     1,
            timestamp: block.timestamp - 24 hours,
            burned:    0.284184026893324971 * 1e18,
            interest:  0.000048562908902619 * 1e18
        });

        // skip more time to allow more interest to accrue
        skip(10 days);

        // borrower1 repays their loan again
        changePrank(borrower1);
        (debt, , ) = _poolOne.borrowerInfo(borrower1);
        _poolOne.repayDebt(borrower1, debt, 0, borrower1, MAX_FENWICK_INDEX);

        // recorder updates the change in exchange rates in the second index
        _updateExchangeRates({
            updater:        _updater2,
            pool:           address(_poolOne),
            depositIndexes: depositIndex2,
            reward:         0.021313802017687201 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater2), .021313802017687201 * 1e18);

        /*******************************************/
        /*** Lender Withdraws And Claims Rewards ***/
        /*******************************************/

        // _minterOne withdraws and claims rewards, rewards should be set to the difference between total claimed and cap
        _unstakeToken({
            minter:            _minterOne,
            pool:              address(_poolOne),
            tokenId:           tokenIdOne,
            claimedArray:      _epochsClaimedArray(1, 0),
            reward:            0.298393228234161298 * 1e18,
            updateRatesReward: 0
        });
    }

    function testMultiPeriodRewardsSingleClaim() external {
        skip(10);

        uint256 totalTokensBurned;

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](10);
        depositIndexes[0] = 5995;
        depositIndexes[1] = 5996;
        depositIndexes[2] = 5997;
        depositIndexes[3] = 5998;
        depositIndexes[4] = 5999;
        depositIndexes[5] = 6000;
        depositIndexes[6] = 6001;
        depositIndexes[7] = 6002;
        depositIndexes[8] = 6003;
        depositIndexes[9] = 6004;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1_000 * 1e18,
            pool: _poolOne
        });

        // mint memorialize and deposit NFT
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        /*****************************/
        /*** First Reserve Auction ***/
        /*****************************/

        // borrower takes actions providing reserves enabling reserve auctions
        // bidder takes reserve auctions by providing ajna tokens to be burned
        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 1_500 * 1e18,
            limitIndex: 6000,
            pool: _poolOne
        });
        totalTokensBurned += _triggerReserveAuctions(triggerReserveAuctionParams);

        // call update exchange rate to enable claiming rewards
        changePrank(_updater);
        assertEq(_ajnaToken.balanceOf(_updater), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater, address(_poolOne), depositIndexes, 20.449844540665683990 * 1e18);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater), 20.449844540665683990 * 1e18);

        uint256 rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 204.498445406656758711 * 1e18);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        /******************************/
        /*** Second Reserve Auction ***/
        /******************************/

        // trigger second reserve auction
        triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 1_500 * 1e18,
            limitIndex: 6000,
            pool: _poolOne
        });
        totalTokensBurned += _triggerReserveAuctions(triggerReserveAuctionParams);

        // call update exchange rate to enable claiming rewards
        changePrank(_updater);
        assertEq(_ajnaToken.balanceOf(_updater), 20.449844540665683990 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater, address(_poolOne), depositIndexes, 17.238252336072284751 * 1e18);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater), 37.688096876737968741 * 1e18);

        // check available rewards
        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 376.880968767380328766 * 1e18);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        /*****************************/
        /*** Third Reserve Auction ***/
        /*****************************/

        // trigger third reserve auction
        triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 1_500 * 1e18,
            limitIndex: 6000,
            pool: _poolOne
        });
        totalTokensBurned += _triggerReserveAuctions(triggerReserveAuctionParams);

        // skip updating exchange rates and check available rewards
        uint256 rewardsEarnedNoUpdate = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarnedNoUpdate, 376.880968767380328766 * 1e18);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        // snapshot calling update exchange rate
        uint256 snapshot = vm.snapshot();

        // call update exchange rate
        changePrank(_updater2);
        assertEq(_ajnaToken.balanceOf(_updater2), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater2, address(_poolOne), depositIndexes, 14.019164349973576689 * 1e18);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater2), 14.019164349973576689 * 1e18);

        // check available rewards
        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 517.072612267115797118 * 1e18);
        assertGt(rewardsEarned, rewardsEarnedNoUpdate);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        // revert to no update state
        vm.revertTo(snapshot);

        /******************************/
        /*** Fourth Reserve Auction ***/
        /******************************/

        // triger fourth reserve auction
        triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 1_500 * 1e18,
            limitIndex: 6000,
            pool: _poolOne
        });
        totalTokensBurned += _triggerReserveAuctions(triggerReserveAuctionParams);

        // check rewards earned
        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 376.880968767380328766 * 1e18);

        // call update exchange rate
        changePrank(_updater2);
        assertEq(_ajnaToken.balanceOf(_updater2), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater2, address(_poolOne), depositIndexes, 0);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater2), 0);

        // check rewards earned won't increase since previous update was missed
        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 376.880968767380328766 * 1e18);

        /*****************************/
        /*** Fifth Reserve Auction ***/
        /*****************************/

        // triger fourth reserve auction
        triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 1_500 * 1e18,
            limitIndex: 6000,
            pool: _poolOne
        });
        totalTokensBurned += _triggerReserveAuctions(triggerReserveAuctionParams);

        // call update exchange rate
        changePrank(_updater2);
        assertEq(_ajnaToken.balanceOf(_updater2), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater2, address(_poolOne), depositIndexes, 11.615849155266846067 * 1e18);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater2), 11.615849155266846067 * 1e18);

        rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 493.039460320049032067 * 1e18);

        // claim all rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(5, 0), rewardsEarned);
        _rewardsManager.claimRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterOne), rewardsEarned);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));
    }

    function testMoveStakedLiquidity() external {
        skip(10);

        /*****************/
        /*** Stake NFT ***/
        /*****************/

        uint256[] memory firstIndexes = new uint256[](5);
        firstIndexes[0] = 2550;
        firstIndexes[1] = 2551;
        firstIndexes[2] = 2552;
        firstIndexes[3] = 2553;
        firstIndexes[4] = 2555;

        // configure NFT position
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes:    firstIndexes,
            minter:     _minterOne,
            mintAmount: 1000 * 1e18,
            pool:       _poolOne
        });
        uint256 tokenId = _mintAndMemorializePositionNFT(mintMemorializeParams);

        // stake nft
        _stakeToken(address(_poolOne), _minterOne, tokenId);

        /***********************/
        /*** Move Staked NFT ***/
        /***********************/

        uint256 expiry = block.timestamp + 1000;
        uint256[] memory secondIndexes = new uint256[](5);
        secondIndexes[0] = 2556;
        secondIndexes[1] = 2557;
        secondIndexes[2] = 2558;
        secondIndexes[3] = 2559;
        secondIndexes[4] = 2560;

        // check no rewards are claimed on first move
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_minterOne, address(_poolOne), firstIndexes, 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenId, _epochsClaimedArray(0, 0), 0);

        // check MoveLiquidity emits
        for (uint256 i = 0; i < firstIndexes.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit MoveLiquidity(address(_rewardsManager), tokenId, firstIndexes[i], secondIndexes[i]);
        }

        vm.expectEmit(true, true, true, true);
        emit MoveStakedLiquidity(tokenId, firstIndexes, secondIndexes);
        _rewardsManager.moveStakedLiquidity(tokenId, firstIndexes, secondIndexes, expiry);

        /*****************************/
        /*** First Reserve Auction ***/
        /*****************************/

        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 2560,
            pool: _poolOne
        });
        // first reserve auction happens successfully -> epoch 1
        _triggerReserveAuctions(triggerReserveAuctionParams);

        uint256 currentBurnEpoch = _poolOne.currentBurnEpoch();

        /***********************/
        /*** Move Staked NFT ***/
        /***********************/

        expiry = block.timestamp + 1000;

        // need to retrieve the position managers index set since positionIndexes are stored unordered in EnnumerableSets
        secondIndexes = _positionManager.getPositionIndexes(tokenId);

        // check rewards are claimed from the indexes that the staker is moving away from
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_minterOne, address(_poolOne), secondIndexes, 4.089968908133134320 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenId, _epochsClaimedArray(1, 0), 44.989657989464439745 * 1e18);
        // check MoveLiquidity emits
        for (uint256 i = 0; i < firstIndexes.length; ++i) {
            vm.expectEmit(true, true, true, true);
            emit MoveLiquidity(address(_rewardsManager), tokenId, secondIndexes[i], firstIndexes[i]);
        }
        vm.expectEmit(true, true, true, true);
        emit MoveStakedLiquidity(tokenId, secondIndexes, firstIndexes);

        // check exchange rates are updated
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_minterOne, address(_poolOne), firstIndexes, 0);

        changePrank(_minterOne);
        _rewardsManager.moveStakedLiquidity(tokenId, secondIndexes, firstIndexes, expiry);

        // check that no rewards are available yet in the indexes that the staker moved to
        vm.expectRevert(IRewardsManagerErrors.AlreadyClaimed.selector);
        _rewardsManager.claimRewards(tokenId, currentBurnEpoch);

        /******************************/
        /*** Second Reserve Auction ***/
        /******************************/

        triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 2555,
            pool: _poolOne
        });
        // first reserve auction happens successfully -> epoch 1
        _triggerReserveAuctions(triggerReserveAuctionParams);

        currentBurnEpoch = _poolOne.currentBurnEpoch();

        /******************************/
        /*** Exchange Rates Updated ***/
        /******************************/

        // need to retrieve the position managers index set since positionIndexes are stored unordered in EnnumerableSets
        firstIndexes = _positionManager.getPositionIndexes(tokenId);

        _updateExchangeRates(_updater, address(_poolOne), firstIndexes, 4.173045773803754351 * 1e18);

        /*********************/
        /*** Claim Rewards ***/
        /*********************/

        // claim rewards accrued since second movement of lps
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 44.989657989464439745 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenId, _epochsClaimedArray(1, 1), 41.730457738037587731 * 1e18);
        _rewardsManager.claimRewards(tokenId, currentBurnEpoch);
    }

    function testEarlyAndLateStakerRewards() external {
        skip(10);

        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;

        // configure NFT position two
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes:    depositIndexes,
            minter:     _minterTwo,
            mintAmount: 1000 * 1e18,
            pool:       _poolOne
        });
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT(mintMemorializeParams);
        // bucket exchange rates are not changed at the time minter two stakes
        assertEq(_poolOne.bucketExchangeRate(2550), 1e18);
        assertEq(_poolOne.bucketExchangeRate(2551), 1e18);
        assertEq(_poolOne.bucketExchangeRate(2552), 1e18);
        assertEq(_poolOne.bucketExchangeRate(2553), 1e18);
        assertEq(_poolOne.bucketExchangeRate(2555), 1e18);
        _stakeToken(address(_poolOne), _minterTwo, tokenIdTwo);

        // borrower borrows and change the exchange rates of buckets
        (address borrower1, uint256 collateralToPledge) = _createTestBorrower(_poolOne, string("borrower1"), 10_000 * 1e18, 2770);
        changePrank(borrower1);

        _poolOne.drawDebt(borrower1, 5 * 1e18, 2770, collateralToPledge);

        skip(1 days);

        // configure NFT position three one day after early minter
        mintMemorializeParams = MintAndMemorializeParams({
            indexes:    depositIndexes,
            minter:     _minterThree,
            mintAmount: 1000 * 1e18,
            pool:       _poolOne
        });
        uint256 tokenIdThree = _mintAndMemorializePositionNFT(mintMemorializeParams);
        // bucket exchange rates are higher at the time minter three stakes
        assertEq(_poolOne.bucketExchangeRate(2550), 1.000000116558299385 * 1e18);
        assertEq(_poolOne.bucketExchangeRate(2551), 1.000000116558299385 * 1e18);
        assertEq(_poolOne.bucketExchangeRate(2552), 1.000000116558299385 * 1e18);
        assertEq(_poolOne.bucketExchangeRate(2553), 1.000000116558299385 * 1e18);
        assertEq(_poolOne.bucketExchangeRate(2555), 1.000000116558299385 * 1e18);
        _stakeToken(address(_poolOne), _minterThree, tokenIdThree);

        skip(1 days);

        // trigger reserve auction and update rates
        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex:   2555,
            pool:         _poolOne
        });
        _triggerReserveAuctions(triggerReserveAuctionParams);

        // unstake and compare rewards and balances of minter two and minter three
        _unstakeToken({
            minter:            _minterTwo,
            pool:              address(_poolOne),
            tokenId:           tokenIdTwo,
            claimedArray:      _epochsClaimedArray(1, 0),
            reward:            39.908019526547621234 * 1e18,
            updateRatesReward: 0
        });
        uint256 minterTwoBalance = _ajnaToken.balanceOf(_minterTwo);
        assertEq(minterTwoBalance, 39.908019526547621234 * 1e18);
        _unstakeToken({
            minter:            _minterThree,
            pool:              address(_poolOne),
            tokenId:           tokenIdThree,
            claimedArray:      _epochsClaimedArray(1, 0),
            reward:            33.248129642902499062 * 1e18,
            updateRatesReward: 0
        });
        uint256 minterThreeBalance = _ajnaToken.balanceOf(_minterThree);
        assertEq(minterThreeBalance, 33.248129642902499062 * 1e18);

        assertGt(minterTwoBalance, minterThreeBalance);
    }

    // Calling updateExchangeRates not needed since deposits will update the exchange rate themselves
    function testClaimRewardsMultipleDepositsSameBucketsMultipleAuctions() external {
        skip(10);

        /*****************************/
        /*** First Lender Deposits ***/
        /*****************************/

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        // mint memorialize and deposit NFT
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        /*****************************/
        /*** First Reserve Auction ***/
        /*****************************/

        // borrower takes actions providing reserves enabling reserve auctions
        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });
        uint256 auctionOneTokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        /******************************/
        /*** Second Lender Deposits ***/
        /******************************/

        // second depositor deposits an NFT representing the same positions into the rewards contract
        mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterTwo,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT(mintMemorializeParams);
        // second depositor stakes NFT, generating an update reward
        _stakeToken(address(_poolOne), _minterTwo, tokenIdTwo);
        assertEq(_ajnaToken.balanceOf(_minterTwo), 8.175422393077340107 * 1e18);

        // calculate rewards earned since exchange rates have been updated
        uint256 idOneRewardsAtOne = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertLt(idOneRewardsAtOne, auctionOneTokensToBurn);
        assertGt(idOneRewardsAtOne, 0);

        // minter one claims rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), idOneRewardsAtOne);
        _rewardsManager.claimRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterOne), idOneRewardsAtOne);

        /******************************/
        /*** Second Reserve Auction ***/
        /******************************/

        // borrower takes actions providing reserves enabling additional reserve auctions
        triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });

        // conduct second reserve auction
        uint256 auctionTwoTokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        /*****************************/
        /*** Third Lender Deposits ***/
        /*****************************/

        // third depositor deposits an NFT representing the same positions into the rewards contract
        mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterThree,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });
        uint256 tokenIdThree = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _stakeToken(address(_poolOne), _minterThree, tokenIdThree);

        /***********************/
        /*** Rewards Claimed ***/
        /***********************/

        // calculate rewards earned since exchange rates have been updated
        uint256 idOneRewardsAtTwo = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertLt(idOneRewardsAtTwo, auctionTwoTokensToBurn);
        assertGt(idOneRewardsAtTwo, 0);

        uint256 idTwoRewardsAtTwo = _rewardsManager.calculateRewards(tokenIdTwo, _poolOne.currentBurnEpoch());
        assertLt(idOneRewardsAtTwo + idTwoRewardsAtTwo, auctionTwoTokensToBurn);
        assertGt(idTwoRewardsAtTwo, 0);

        // minter one claims rewards accrued after second auction
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), idOneRewardsAtOne);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 1), idOneRewardsAtTwo);
        _rewardsManager.claimRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterOne), idOneRewardsAtOne + idOneRewardsAtTwo);

        // minter two claims rewards accrued since deposit
        changePrank(_minterTwo);
        assertEq(_ajnaToken.balanceOf(_minterTwo), 8.175422393077340107 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterTwo, address(_poolOne), tokenIdTwo, _epochsClaimedArray(1, 1), idTwoRewardsAtTwo);
        _rewardsManager.claimRewards(tokenIdTwo, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterTwo), idTwoRewardsAtTwo + 8.175422393077340107 * 1e18);

        // check there are no remaining rewards available after claiming
        uint256 remainingRewards = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(remainingRewards, 0);

        remainingRewards = _rewardsManager.calculateRewards(tokenIdTwo, _poolOne.currentBurnEpoch());
        assertEq(remainingRewards, 0);

        remainingRewards = _rewardsManager.calculateRewards(tokenIdThree, _poolOne.currentBurnEpoch());
        assertEq(remainingRewards, 0);
    }

    function testClaimRewardsMultipleDepositsDifferentBucketsMultipleAuctions() external {
        // configure _minterOne's NFT position
        uint256[] memory depositIndexesMinterOne = new uint256[](5);
        depositIndexesMinterOne[0] = 2550;
        depositIndexesMinterOne[1] = 2551;
        depositIndexesMinterOne[2] = 2552;
        depositIndexesMinterOne[3] = 2553;
        depositIndexesMinterOne[4] = 2555;
        MintAndMemorializeParams memory mintMemorializeParamsMinterOne = MintAndMemorializeParams({
            indexes: depositIndexesMinterOne,
            minter: _minterOne,
            mintAmount: 1_000 * 1e18,
            pool: _poolOne
        });

        // configure _minterTwo's NFT position
        uint256[] memory depositIndexesMinterTwo = new uint256[](5);
        depositIndexesMinterTwo[0] = 2550;
        depositIndexesMinterTwo[1] = 2551;
        depositIndexesMinterTwo[2] = 2200;
        depositIndexesMinterTwo[3] = 2221;
        depositIndexesMinterTwo[4] = 2222;
        MintAndMemorializeParams memory mintMemorializeParamsMinterTwo = MintAndMemorializeParams({
            indexes: depositIndexesMinterTwo,
            minter: _minterTwo,
            mintAmount: 5_000 * 1e18,
            pool: _poolOne
        });

        uint256[] memory depositIndexes = new uint256[](8);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;
        depositIndexes[5] = 2200;
        depositIndexes[6] = 2221;
        depositIndexes[7] = 2222;

        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParamsMinterOne);
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT(mintMemorializeParamsMinterTwo);

        // lenders stake their NFTs
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);
        _stakeToken(address(_poolOne), _minterTwo, tokenIdTwo);

        // borrower takes actions providing reserves enabling three reserve auctions
        _triggerReserveAuctions(TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 2555,
            pool: _poolOne
        }));

        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_poolOne),
            depositIndexes: depositIndexes,
            reward:         4.089968908133113615 * 1e18
        });

        _triggerReserveAuctions(TriggerReserveAuctionParams({
            borrowAmount: 1_000 * 1e18,
            limitIndex: 2555,
            pool: _poolOne
        }));

        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_poolOne),
            depositIndexes: depositIndexes,
            reward:         13.717705175494177175 * 1e18
        });

        _triggerReserveAuctions(TriggerReserveAuctionParams({
            borrowAmount: 2_000 * 1e18,
            limitIndex: 2555,
            pool: _poolOne
        }));
        
        _updateExchangeRates({
            updater:        _updater,
            pool:           address(_poolOne),
            depositIndexes: depositIndexes,
            reward:         27.568516982211776340 * 1e18
        });

        // proof of burn events
        _assertBurn({
            pool:      address(_poolOne),
            epoch:     0,
            timestamp: 0,
            burned:    0,
            interest:  0
        });

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     1,
            timestamp: block.timestamp - (52 weeks + 72 hours),
            interest:  6.443638300196908069 * 1e18,
            burned:    81.799378162662586331 * 1e18
        });

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     2,
            timestamp: block.timestamp - (26 weeks + 48 hours),
            burned:    356.153481672544289291 * 1e18,
            interest:  28.092564949680668737 * 1e18
        });

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     3,
            timestamp: block.timestamp - 24 hours,
            burned:    907.523821316779267550 * 1e18,
            interest:  71.814132054505950833 * 1e18
        });

        // both stakers claim rewards
        _unstakeToken({
            minter:            _minterOne,
            pool:              address(_poolOne),
            tokenId:           tokenIdOne,
            claimedArray:      _epochsClaimedArray(3, 0),
            reward:            75.626985109731636395 * 1e18,
            updateRatesReward: 0
        });

        _unstakeToken({
            minter:            _minterTwo,
            pool:              address(_poolOne),
            tokenId:           tokenIdTwo,
            claimedArray:      _epochsClaimedArray(3, 0),
            reward:            378.134925548658181975 * 1e18,
            updateRatesReward: 0
        });
    }

    function testUnstakeToken() external {
        skip(10);

        address nonOwner = makeAddr("nonOwner");

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        // mint memorialize and deposit NFT
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        // only owner should be able to withdraw the NFT
        changePrank(nonOwner);
        vm.expectRevert(IRewardsManagerErrors.NotOwnerOfDeposit.selector);
        _rewardsManager.unstake(tokenIdOne);

        // check owner can withdraw the NFT
        changePrank(_minterOne);
        vm.expectEmit(true, true, true, true);
        emit Unstake(_minterOne, address(_poolOne), tokenIdOne);
        _rewardsManager.unstake(tokenIdOne);
        assertEq(_positionManager.ownerOf(tokenIdOne), _minterOne);

        // deposit information should have been deleted on withdrawal
        (address owner, address pool, uint256 interactionBlock) = _rewardsManager.getStakeInfo(tokenIdOne);
        assertEq(owner, address(0));
        assertEq(pool, address(0));
        assertEq(interactionBlock, 0);
    }

    function testWithdrawAndClaimRewards() external {
        skip(10);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;
        depositIndexes[3] = 2553;
        depositIndexes[4] = 2555;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 2555,
            pool: _poolOne
        });

        uint256 tokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        // call update exchange rate to enable claiming rewards
        changePrank(_updater);
        assertEq(_ajnaToken.balanceOf(_updater), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater, address(_poolOne), depositIndexes, 4.089968908133134320 * 1e18);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertGt(_ajnaToken.balanceOf(_updater), 0);

        // check owner can withdraw the NFT and rewards will be automatically claimed

        uint256 snapshot = vm.snapshot();

        // claimed rewards amount is greater than available tokens in rewards manager contract

        // burn rewards manager tokens and leave only 5 tokens available
        changePrank(address(_rewardsManager));
        IERC20Token(address(_ajnaToken)).burn(99_999_990.978586345404952410 * 1e18);

        uint256 managerBalance = _ajnaToken.balanceOf(address(_rewardsManager));
        assertEq(managerBalance, 4.931444746461913270 * 1e18);

        changePrank(_minterOne);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), 40.899689081331305425 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit Unstake(_minterOne, address(_poolOne), tokenIdOne);
        _rewardsManager.unstake(tokenIdOne);

        // minter one receives only the amount of 5 ajna tokens available in manager balance instead calculated rewards of 40.214136545950568150
        assertEq(_ajnaToken.balanceOf(_minterOne), managerBalance);
        // all 5 tokens available in manager balance were used to reward minter one
        assertEq(_ajnaToken.balanceOf(address(_rewardsManager)), 0); 

        vm.revertTo(snapshot);

        // test when enough tokens in rewards manager contracts
        changePrank(_minterOne);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), 40.899689081331305425 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit Unstake(_minterOne, address(_poolOne), tokenIdOne);
        _rewardsManager.unstake(tokenIdOne);
        assertEq(_positionManager.ownerOf(tokenIdOne), _minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 40.899689081331305425 * 1e18);
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);

        uint256 currentBurnEpoch = _poolOne.currentBurnEpoch();

        // check can't claim rewards twice
        vm.expectRevert(IRewardsManagerErrors.NotOwnerOfDeposit.selector);
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpoch);
    }

    function testMultiplePools() external {
        skip(10);

        // configure NFT position one
        uint256[] memory depositIndexesOne = new uint256[](5);
        depositIndexesOne[0] = 9;
        depositIndexesOne[1] = 1;
        depositIndexesOne[2] = 2;
        depositIndexesOne[3] = 3;
        depositIndexesOne[4] = 4;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexesOne,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);

        // configure NFT position two
        uint256[] memory depositIndexesTwo = new uint256[](4);
        depositIndexesTwo[0] = 5;
        depositIndexesTwo[1] = 1;
        depositIndexesTwo[2] = 3;
        depositIndexesTwo[3] = 12;
        mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexesTwo,
            minter: _minterTwo,
            mintAmount: 1000 * 1e18,
            pool: _poolTwo
        });

        uint256 tokenIdTwo = _mintAndMemorializePositionNFT(mintMemorializeParams);

        // minterOne deposits their NFT into the rewards contract
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        // minterTwo deposits their NFT into the rewards contract
        _stakeToken(address(_poolTwo), _minterTwo, tokenIdTwo);

        // borrower takes actions providing reserves enabling reserve auctions
        // bidder takes reserve auctions by providing ajna tokens to be burned
        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });

        uint256 tokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        uint256 currentBurnEpochPoolOne = _poolOne.currentBurnEpoch();

        // check only deposit owner can claim rewards
        changePrank(_minterTwo);
        vm.expectRevert(IRewardsManagerErrors.NotOwnerOfDeposit.selector);
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpochPoolOne);

        // check rewards earned in one pool shouldn't be claimable by depositors from another pool
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);
        _rewardsManager.claimRewards(tokenIdTwo, _poolTwo.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);

        // call update exchange rate to enable claiming rewards
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_minterOne, address(_poolOne), depositIndexesOne, 4.089968908133134320 * 1e18);
        uint256 updateReward = _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexesOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), updateReward);
        assertEq(_ajnaToken.balanceOf(_minterOne), 4.089968908133134320 * 1e18);

        // check owner in pool with accrued interest can properly claim rewards
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 4.089968908133134320 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), 40.899689081331305425 * 1e18);
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpochPoolOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 44.989657989464439745 * 1e18);
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);
    }

    /********************/
    /*** FUZZ TESTING ***/
    /********************/

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
        for(uint j = 0; j < copyOfArray.length; j++){
            copyOfArray[j] = array[j];
        }
        uint256 randomNoOfNfts = randomInRange(1, copyOfArray.length);
        subsetArray = new uint256[](randomNoOfNfts);
        for(uint256 i = 0; i < randomNoOfNfts; i++) {
            uint256 randomIndex = randomInRange(0, copyOfArray.length - i - 1);
            subsetArray[i] = copyOfArray[randomIndex];
            copyOfArray[randomIndex] = copyOfArray[copyOfArray.length - i - 1];
        }
    }

    // Returns N addresses array
    function _getAddresses(uint256 noOfAddress) internal returns(address[] memory addresses_) {
        addresses_ = new address[](noOfAddress);
        for(uint i = 0; i < noOfAddress; i++) {
            addresses_[i] = makeAddr(string(abi.encodePacked("Minter", Strings.toString(i))));
        }
    }

    function testClaimRewardsFuzzy(uint256 indexes, uint256 mintAmount) external {
        indexes = bound(indexes, 3, 10); // number of indexes to add liquidity to
        mintAmount = bound(mintAmount, 1 * 1e18, 100_000 * 1e18); // bound mint amount and dynamically determine borrow amount and collateral based upon provided index and mintAmount

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](indexes);
        for (uint256 i = 0; i < indexes; ++i) {
            depositIndexes[i] = _randomIndex();
        }
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: mintAmount,
            pool: _poolOne
        });
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);

        // stake NFT
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        // calculates a limit index leaving one index above the htp to accrue interest
        uint256 limitIndex = _findSecondLowestIndexPrice(depositIndexes);
        TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: Maths.wdiv(mintAmount, Maths.wad(3)),
            limitIndex: limitIndex,
            pool: _poolOne
        });

        uint256 tokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        // call update exchange rate to enable claiming rewards
        changePrank(_updater);
        assertEq(_ajnaToken.balanceOf(_updater), 0);
        _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertGt(_ajnaToken.balanceOf(_updater), 0);

        // calculate rewards earned and compare to percentages for updating and claiming
        uint256 rewardsEarned = _rewardsManager.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertGt(rewardsEarned, 0);

        // claim rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), rewardsEarned);
        _rewardsManager.claimRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterOne), rewardsEarned);

        // assert rewards claimed is less than ajna tokens burned cap
        assertLt(_ajnaToken.balanceOf(_minterOne), Maths.wmul(tokensToBurn, 0.800000000000000000 * 1e18));
    }

    function testStakingRewardsFuzzy(uint256 deposits, uint256 reserveAuctions) external {
        deposits        = bound(deposits, 1, 25); // number of deposits to make
        reserveAuctions = bound(reserveAuctions, 1, 25); // number of reserve Auctions to complete

        uint256[] memory tokenIds = new uint256[](deposits);

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](3);
        for (uint256 j = 0; j < 3; ++j) {
            depositIndexes[j] = _randomIndex();
            vm.roll(block.number + 1); // advance block to ensure that the index price is different
        }

        address[] memory minters = _getAddresses(deposits);

        // stake variable no of deposits
        for(uint256 i = 0; i < deposits; ++i) {
            // mint and memorilize Positions
            MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
                indexes: depositIndexes,
                minter: minters[i],
                mintAmount: 1_000_000_000 * 1e18,
                pool: _poolOne
            });

            tokenIds[i] = _mintAndMemorializePositionNFT(mintMemorializeParams);
            tokenIdToMinter[tokenIds[i]] = minters[i];
            _stakeToken(address(_poolOne), minters[i], tokenIds[i]);
        }

        uint256 updaterBalance = _ajnaToken.balanceOf(_updater);

        for(uint i = 0; i < deposits; i++) {
            minterToBalance[minters[i]] = _ajnaToken.balanceOf(minters[i]);
        }

        // start variable no of reserve Auctions and claim rewards for random tokenIds in each epoch
        for(uint i = 0; i < reserveAuctions; ++i) {
            uint256 limitIndex = _findSecondLowestIndexPrice(depositIndexes);
            TriggerReserveAuctionParams memory triggerReserveAuctionParams = TriggerReserveAuctionParams({
                borrowAmount: 10_000 * 1e18,
                limitIndex: limitIndex,
                pool: _poolOne
            });

            // start and end new reserve auction 
            uint256 tokensBurned = _triggerReserveAuctions(triggerReserveAuctionParams);

            // call update exchange rate to enable claiming rewards
            changePrank(_updater);
            assertEq(_ajnaToken.balanceOf(_updater), updaterBalance);
            _rewardsManager.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);

            // ensure updater gets reward for updating exchange rate
            assertGt(_ajnaToken.balanceOf(_updater), updaterBalance);

            // ensure update rewards in each epoch is less than or equals to 10% of tokensBurned
            assertLe(_ajnaToken.balanceOf(_updater) - updaterBalance, tokensBurned / 10);

            updaterBalance = _ajnaToken.balanceOf(_updater);

            // pick random NFTs from all NFTs to claim rewards
            uint256[] memory randomNfts = _getRandomSubsetFromArray(tokenIds);

            for(uint j = 0; j < randomNfts.length; j++) {
                address minterAddress = tokenIdToMinter[randomNfts[j]];
                changePrank(minterAddress);

                (, , uint256 lastInteractionEpoch) = _rewardsManager.getStakeInfo(randomNfts[j]);

                // select random epoch to claim reward
                uint256 epochToClaim = lastInteractionEpoch < _poolOne.currentBurnEpoch() ? randomInRange(lastInteractionEpoch + 1, _poolOne.currentBurnEpoch()) : lastInteractionEpoch; 
                
                uint256 rewardsEarned = _rewardsManager.calculateRewards(randomNfts[j], epochToClaim);
                assertGt(rewardsEarned, 0);

                _rewardsManager.claimRewards(randomNfts[j], _poolOne.currentBurnEpoch());

                // ensure user gets reward
                assertGt(_ajnaToken.balanceOf(minterAddress), minterToBalance[minterAddress]);
                minterToBalance[minterAddress] = _ajnaToken.balanceOf(minterAddress);
            }
        }
    }

    function testClaimRewardsFreezeUnclaimedYield() external {
        skip(10);

        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });

        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);

        uint256 currentBurnEpoch = _poolOne.currentBurnEpoch();

        changePrank(_minterOne);
        // should revert if the epoch to claim is not available yet
        vm.expectRevert(IRewardsManagerErrors.EpochNotAvailable.selector);
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpoch + 10);

        // user should be able to claim rewards for current epoch
        _rewardsManager.claimRewards(tokenIdOne, currentBurnEpoch);
    }

}
