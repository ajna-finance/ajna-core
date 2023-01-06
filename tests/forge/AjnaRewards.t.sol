// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20Pool }        from 'src/erc20/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/erc20/ERC20PoolFactory.sol';

import 'src/AjnaRewards.sol';
import 'src/IAjnaRewards.sol';

import 'src/base/interfaces/IPositionManager.sol';
import 'src/base/PositionManager.sol';
import 'src/base/PoolInfoUtils.sol';

import { DSTestPlus } from './utils/DSTestPlus.sol';
import { Token }      from './utils/Tokens.sol';

contract AjnaRewardsTest is DSTestPlus {

    address         internal _bidder;
    address         internal _minterOne;
    address         internal _minterTwo;
    address         internal _minterThree;
    address         internal _minterFour;
    address         internal _minterFive;
    address         internal _updater;
    address         internal _updater2;

    ERC20           internal _ajnaToken;

    AjnaRewards      internal _ajnaRewards;
    ERC20PoolFactory internal _poolFactory;
    PositionManager  internal _positionManager;

    Token           internal _collateralOne;
    Token           internal _quoteOne;
    ERC20Pool       internal _poolOne;
    Token           internal _collateralTwo;
    Token           internal _quoteTwo;
    ERC20Pool       internal _poolTwo;

    event ClaimRewards(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256[] epochsClaimed, uint256 amount);
    event StakeToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);
    event UpdateExchangeRates(address indexed caller, address indexed ajnaPool, uint256[] indexesUpdated, uint256 rewardsClaimed);
    event UnstakeToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);

    uint256 constant BLOCKS_IN_DAY = 7200;

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
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.makePersistent(_ajna);

        _ajnaToken       = ERC20(_ajna);
        _poolFactory     = new ERC20PoolFactory(_ajna);
        _positionManager = new PositionManager(_poolFactory, new ERC721PoolFactory(_ajna));
        _ajnaRewards     = new AjnaRewards(_ajna, _positionManager);
        _poolUtils       = new PoolInfoUtils();

        _collateralOne = new Token("Collateral 1", "C1");
        _quoteOne      = new Token("Quote 1", "Q1");
        _poolOne       = ERC20Pool(_poolFactory.deployPool(address(_collateralOne), address(_quoteOne), 0.05 * 10**18));

        _collateralTwo = new Token("Collateral 2", "C2");
        _quoteTwo      = new Token("Quote 2", "Q2");
        _poolTwo       = ERC20Pool(_poolFactory.deployPool(address(_collateralTwo), address(_quoteTwo), 0.05 * 10**18));

        // provide initial ajna tokens to staking rewards contract
        deal(_ajna, address(_ajnaRewards), 100_000_000 * 1e18);
        assertEq(_ajnaToken.balanceOf(address(_ajnaRewards)), 100_000_000 * 1e18);

        // instaantiate test minters
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
        _positionManager.approve(address(_ajnaRewards), tokenId_);
        vm.expectEmit(true, true, true, true);
        emit StakeToken(owner_, address(pool_), tokenId_);
        _ajnaRewards.stakeToken(tokenId_);

        // check token was transferred to rewards contract
        assertEq(_positionManager.ownerOf(tokenId_), address(_ajnaRewards));
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
        emit UnstakeToken(minter, address(pool), tokenId);
        _ajnaRewards.unstakeToken(tokenId);
        assertEq(_positionManager.ownerOf(tokenId), minter);

        // check token was transferred to rewards contract
        assertEq(_positionManager.ownerOf(tokenId), address(minter));
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
        params_.pool.repayDebt(borrower, Maths.wdiv(params_.borrowAmount, Maths.wad(2)), 0);

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
        // call update exchange rate to enable claiming rewards for epoch 0 - 1
        changePrank(updater);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(updater, address(pool), depositIndexes, reward);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(pool), depositIndexes);
    }


    function _epochsClaimedArray(uint256 numberOfAuctions_, uint256 lastClaimed_) internal pure returns (uint256[] memory epochsClaimed_) {
        epochsClaimed_ = new uint256[](numberOfAuctions_);
        uint256 claimEpoch = lastClaimed_; // starting index, not inclusive

        // FIXME: this doesn't work for non starting auction epochs
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

        for (uint256 i = 0; i < params_.indexes.length; i++) {
            params_.pool.addQuoteToken(params_.mintAmount, params_.indexes[i]);
            (uint256 lpBalance, ) = params_.pool.lenderInfo(params_.indexes[i], params_.minter);
            params_.pool.approveLpOwnership(address(_positionManager), params_.indexes[i], lpBalance);
        }

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId_, params_.indexes
        );

        _positionManager.memorializePositions(memorializeParams);
    }

    function _triggerReserveAuctions(TriggerReserveAuctionParams memory params_) internal returns (uint256 tokensToBurn_) {
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
        params_.pool.repayDebt(borrower, Maths.wdiv(params_.borrowAmount, Maths.wad(2)), 0);

        // start reserve auction
        changePrank(_bidder);
        _ajnaToken.approve(address(params_.pool), type(uint256).max);
        params_.pool.startClaimableReserveAuction();

        // allow time to pass for the reserve price to decrease
        skip(24 hours);

        (
            ,
            ,
            uint256 curClaimableReservesRemaining,
            uint256 curAuctionPrice,
        ) = _poolUtils.poolReservesInfo(address(params_.pool));

        // take claimable reserves
        params_.pool.takeReserves(curClaimableReservesRemaining);

        // calculate ajna tokens to burn in order to take the full auction amount
        tokensToBurn_ = Maths.wmul(curClaimableReservesRemaining, curAuctionPrice);
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
        vm.expectRevert(IAjnaRewards.NotOwnerOfDeposit.selector);
        _ajnaRewards.stakeToken(tokenIdOne);

        // minterOne deposits their NFT into the rewards contract
        _stakeToken(address(_poolOne), _minterOne, tokenIdOne);
        // check deposit state
        (address owner, address pool, uint256 interactionBurnEvent) = _ajnaRewards.getDepositInfo(tokenIdOne);
        assertEq(owner, _minterOne);
        assertEq(pool, address(_poolOne));
        assertEq(interactionBurnEvent, 0);

        // minterTwo deposits their NFT into the rewards contract
        _stakeToken(address(_poolTwo), _minterTwo, tokenIdTwo);
        // check deposit state
        (owner, pool, interactionBurnEvent) = _ajnaRewards.getDepositInfo(tokenIdTwo);
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
        emit UpdateExchangeRates(_updater, address(_poolOne), depositIndexes, 1.808591217308675030 * 1e18);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater), 1.808591217308675030 * 1e18);

        // check only deposit owner can claim rewards
        uint256 currentBurnEpoch = _poolOne.currentBurnEpoch();
        vm.expectRevert(IAjnaRewards.NotOwnerOfDeposit.selector);
        _ajnaRewards.claimRewards(tokenIdOne, currentBurnEpoch);

        // check rewards earned
        uint256 rewardsEarned = _ajnaRewards.calculateRewards(tokenIdOne, currentBurnEpoch);
        assertEq(rewardsEarned, 18.085912173086791760 * 1e18);

        // claim rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), rewardsEarned);
        _ajnaRewards.claimRewards(tokenIdOne, currentBurnEpoch);
        assertEq(_ajnaToken.balanceOf(_minterOne), rewardsEarned);

        // check can't claim rewards twice
        vm.expectRevert(IAjnaRewards.AlreadyClaimed.selector);
        _ajnaRewards.claimRewards(tokenIdOne, currentBurnEpoch);

        // check deposit state
        (address owner, address pool, uint256 interactionBurnEvent) = _ajnaRewards.getDepositInfo(tokenIdOne);
        assertEq(owner, _minterOne);
        assertEq(pool, address(_poolOne));
        assertEq(interactionBurnEvent, 1);
        assertEq(_positionManager.ownerOf(tokenIdOne), address(_ajnaRewards));

        // assert rewards claimed is less than ajna tokens burned cap
        assertLt(_ajnaToken.balanceOf(_minterOne), Maths.wmul(tokensToBurn, 0.800000000000000000 * 1e18));

        // check can't call update exchange rate after the update period has elapsed
        skip(2 weeks);
        // changePrank(_updater);
        // vm.expectRevert(IAjnaRewards.ExchangeRateUpdateTooLate.selector);
        uint256 updateRewards = _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
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
            reward:         1.808591217308675030 * 1e18
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
            burned:    36.171824346173572302 * 1e18,
            interest:  6.466873982955353003 * 1e18
        });

        // second reserve auction happens successfully -> epoch 2
        tokensToBurn += _triggerReserveAuctions(triggerReserveAuctionParams);

        // check owner can withdraw the NFT and rewards will be automatically claimed
        _unstakeToken({
            minter:            _minterOne,
            pool:              address(_poolOne),
            tokenId:           tokenIdOne,
            claimedArray:      _epochsClaimedArray(2, 0),
            reward:            49.549902798107900845 * 1e18,
            updateRatesReward: 2.860362784092827595 * 1e18
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
            reward:         1.808591217308675030 * 1e18
        });

        skip(2 weeks);

        // first reserve auction happens successfully Staker should receive rewards epoch 0 - 1
        _triggerReserveAuctionsNoTake(triggerReserveAuctionParams);

        _assertBurn({
            pool:      address(_poolOne),
            epoch:     1,
            timestamp: block.timestamp - (2 weeks + 26 weeks + 24 hours),
            burned:    36.171824346173572302 * 1e18,
            interest:  6.466873982955353003 * 1e18
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
            reward:         2.556218432497364950 * 1e18
        });
    }

    function testUpdateExchangeRatesAndClaimRewardsAfterMultiReserveAuctions() external {
        // TODO: implement this test checking handling of staking an NFT after multiple reserve auctions have already occured
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
        _poolOne.repayDebt(borrower1, debt, 0);

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
            reward:         0.007104599616026695 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater), .007104599616026695 * 1e18);

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
            burned:    0.284183984708078027 * 1e18,
            interest:  0.000048563623809373 * 1e18
        });

        // skip more time to allow more interest to accrue
        skip(10 days);

        // borrower1 repays their loan again
        changePrank(borrower1);
        (debt, , ) = _poolOne.borrowerInfo(borrower1);
        _poolOne.repayDebt(borrower1, debt, 0);

        // recorder updates the change in exchange rates in the second index
        _updateExchangeRates({
            updater:        _updater2,
            pool:           address(_poolOne),
            depositIndexes: depositIndex2,
            reward:         0.021313798854781108 * 1e18
        });
        assertEq(_ajnaToken.balanceOf(_updater2), .021313798854781108 * 1e18);

        /*******************************************/
        /*** Lender Withdraws And Claims Rewards ***/
        /*******************************************/

        // _minterOne withdraws and claims rewards, rewards should be set to the difference between total claimed and cap
        _unstakeToken({
            minter:            _minterOne,
            pool:              address(_poolOne),
            tokenId:           tokenIdOne,
            claimedArray:      _epochsClaimedArray(1, 0),
            reward:            0.227347187766462422 * 1e18,
            updateRatesReward: 0
        });
        // TODO: check reward amount vs expected from burn
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
        emit UpdateExchangeRates(_updater, address(_poolOne), depositIndexes, 7.850216032003022257 * 1e18);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater), 7.850216032003022257 * 1e18);

        uint256 rewardsEarned = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 78.502160320030238033 * 1e18);
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
        assertEq(_ajnaToken.balanceOf(_updater), 7.850216032003022257 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater, address(_poolOne), depositIndexes, 11.067266682269247786 * 1e18);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater), 18.917482714272270043 * 1e18);

        // check available rewards
        rewardsEarned = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 189.174827142723173055 * 1e18);
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
        uint256 rewardsEarnedNoUpdate = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarnedNoUpdate, 189.174827142723173055 * 1e18);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));

        // snapshot calling update exchange rate
        uint256 snapshot = vm.snapshot();

        // call update exchange rate
        changePrank(_updater2);
        assertEq(_ajnaToken.balanceOf(_updater2), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater2, address(_poolOne), depositIndexes, 11.288375322721084926 * 1e18);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater2), 11.288375322721084926 * 1e18);

        // check available rewards
        rewardsEarned = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 302.058580369933599319 * 1e18);
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
        rewardsEarned = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 189.174827142723173055 * 1e18);

        // call update exchange rate
        changePrank(_updater2);
        assertEq(_ajnaToken.balanceOf(_updater2), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_updater2, address(_poolOne), depositIndexes, 0);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater2), 0);

        // check rewards earned won't increase since previous update was missed
        rewardsEarned = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 189.174827142723173055 * 1e18);

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
        emit UpdateExchangeRates(_updater2, address(_poolOne), depositIndexes, 12.907659732060585203 * 1e18);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertEq(_ajnaToken.balanceOf(_updater2), 12.907659732060585203 * 1e18);

        rewardsEarned = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(rewardsEarned, 318.251424463329156087 * 1e18);

        // claim all rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(5, 0), rewardsEarned);
        _ajnaRewards.claimRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterOne), rewardsEarned);
        assertLt(rewardsEarned, Maths.wmul(totalTokensBurned, 0.800000000000000000 * 1e18));
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
        assertEq(_poolOne.bucketExchangeRate(2550), 1e27);
        assertEq(_poolOne.bucketExchangeRate(2551), 1e27);
        assertEq(_poolOne.bucketExchangeRate(2552), 1e27);
        assertEq(_poolOne.bucketExchangeRate(2553), 1e27);
        assertEq(_poolOne.bucketExchangeRate(2555), 1e27);
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
        assertEq(_poolOne.bucketExchangeRate(2550), 1.000000116565164638999999999 * 1e27);
        assertEq(_poolOne.bucketExchangeRate(2551), 1.000000116565164638999999999 * 1e27);
        assertEq(_poolOne.bucketExchangeRate(2552), 1.000000116565164638999999999 * 1e27);
        assertEq(_poolOne.bucketExchangeRate(2553), 1.000000116565164638999999999 * 1e27);
        assertEq(_poolOne.bucketExchangeRate(2555), 1.000000116565164638999999999 * 1e27);
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
            reward:            6.757003114621612065 * 1e18,
            updateRatesReward: 0
        });
        uint256 minterTwoBalance = _ajnaToken.balanceOf(_minterTwo);
        assertEq(minterTwoBalance, 6.757003114621612065 * 1e18);

        _unstakeToken({
            minter:            _minterThree,
            pool:              address(_poolOne),
            tokenId:           tokenIdThree,
            claimedArray:      _epochsClaimedArray(1, 0),
            reward:            5.629597976281608765 * 1e18,
            updateRatesReward: 0
        });
        uint256 minterThreeBalance = _ajnaToken.balanceOf(_minterThree);
        assertEq(minterThreeBalance, 5.629597976281608765 * 1e18);

        assertGt(minterTwoBalance, minterThreeBalance);
    }

    function testMultiPeriodRewardsMultiClaim() external {

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
        assertEq(_ajnaToken.balanceOf(_minterTwo), 3.617182434617357230 * 1e18);

        /******************************/
        /*** Second Reserve Auction ***/
        /******************************/

        // calculate rewards earned since exchange rates have been updated
        uint256 idOneRewardsAtOne = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertLt(idOneRewardsAtOne, auctionOneTokensToBurn);
        assertGt(idOneRewardsAtOne, 0);

        // borrower takes actions providing reserves enabling additional reserve auctions
        triggerReserveAuctionParams = TriggerReserveAuctionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });

        // check can't trigger reserve auction if less than two weeks have passed since last auction
        // FIXME: breaking due to an apparent foundry bug on _triggerReserveAuctions params.pool.collateralAddress()
        // vm.expectRevert(IPoolErrors.ReserveAuctionTooSoon.selector);
        // vm.expectRevert(abi.encodeWithSignature('ReserveAuctionTooSoon()'));
        // _triggerReserveAuctions(triggerReserveAuctionParams);

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
        uint256 idOneRewardsAtTwo = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertLt(idOneRewardsAtTwo, auctionTwoTokensToBurn);
        assertGt(idOneRewardsAtTwo, 0);
        assertGt(idOneRewardsAtTwo, idOneRewardsAtOne);

        uint256 idTwoRewardsAtTwo = _ajnaRewards.calculateRewards(tokenIdTwo, _poolOne.currentBurnEpoch());
        assertLt(idOneRewardsAtTwo + idTwoRewardsAtTwo, auctionTwoTokensToBurn);
        assertGt(idTwoRewardsAtTwo, 0);

        // minter one claims rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(2, 0), idOneRewardsAtTwo);
        _ajnaRewards.claimRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterOne), idOneRewardsAtTwo);

        // minter two claims rewards accrued since deposit
        changePrank(_minterTwo);
        assertEq(_ajnaToken.balanceOf(_minterTwo), 3.617182434617357230 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterTwo, address(_poolOne), tokenIdTwo, _epochsClaimedArray(1, 1), idTwoRewardsAtTwo);
        _ajnaRewards.claimRewards(tokenIdTwo, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterTwo), idTwoRewardsAtTwo + 3.617182434617357230 * 1e18);

        // check there are no remaining rewards available after claiming
        uint256 remainingRewards = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(remainingRewards, 0);

        remainingRewards = _ajnaRewards.calculateRewards(tokenIdTwo, _poolOne.currentBurnEpoch());
        assertEq(remainingRewards, 0);

        remainingRewards = _ajnaRewards.calculateRewards(tokenIdThree, _poolOne.currentBurnEpoch());
        assertEq(remainingRewards, 0);
    }

    function testClaimRewardsMultipleDepositsDifferentBucketsMultipleAuctions() external {

        // TODO: implement this -> instead of using the same RewardsTestParams struct for each new depositor, use modified structs across depositors

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
        vm.expectRevert(IAjnaRewards.NotOwnerOfDeposit.selector);
        _ajnaRewards.unstakeToken(tokenIdOne);

        // check owner can withdraw the NFT
        changePrank(_minterOne);
        vm.expectEmit(true, true, true, true);
        emit UnstakeToken(_minterOne, address(_poolOne), tokenIdOne);
        _ajnaRewards.unstakeToken(tokenIdOne);
        assertEq(_positionManager.ownerOf(tokenIdOne), _minterOne);

        // deposit information should have been deleted on withdrawal
        (address owner, address pool, uint256 interactionBlock) = _ajnaRewards.getDepositInfo(tokenIdOne);
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
        emit UpdateExchangeRates(_updater, address(_poolOne), depositIndexes, 1.808591217308675030 * 1e18);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertGt(_ajnaToken.balanceOf(_updater), 0);

        // check owner can withdraw the NFT and rewards will be automatically claimed
        changePrank(_minterOne);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), 18.085912173086791760 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit UnstakeToken(_minterOne, address(_poolOne), tokenIdOne);
        _ajnaRewards.unstakeToken(tokenIdOne);
        assertEq(_positionManager.ownerOf(tokenIdOne), _minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 18.085912173086791760 * 1e18);
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);

        uint256 currentBurnEpoch = _poolOne.currentBurnEpoch();

        // check can't claim rewards twice
        vm.expectRevert(IAjnaRewards.NotOwnerOfDeposit.selector);
        _ajnaRewards.claimRewards(tokenIdOne, currentBurnEpoch);
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
        vm.expectRevert(IAjnaRewards.NotOwnerOfDeposit.selector);
        _ajnaRewards.claimRewards(tokenIdOne, currentBurnEpochPoolOne);

        // check rewards earned in one pool shouldn't be claimable by depositors from another pool
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);
        _ajnaRewards.claimRewards(tokenIdTwo, _poolTwo.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);

        // call update exchange rate to enable claiming rewards
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_minterOne, address(_poolOne), depositIndexesOne, 1.808591217308675030 * 1e18);
        uint256 updateReward = _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexesOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), updateReward);
        assertEq(_ajnaToken.balanceOf(_minterOne), 1.808591217308675030 * 1e18);

        // check owner in pool with accrued interest can properly claim rewards
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 1.808591217308675030 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), 18.085912173086791760 * 1e18);
        _ajnaRewards.claimRewards(tokenIdOne, currentBurnEpochPoolOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 19.894503390395466790 * 1e18);
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);
    }

    /********************/
    /*** FUZZ TESTING ***/
    /********************/

    function _randomIndex() internal view returns (uint256) {
        // calculate a random index between 1 and 7388
        return 1 + uint256(keccak256(abi.encodePacked(block.number, block.difficulty))) % 7387;
    }

    function _findHighestIndexPrice(uint256[] memory indexes) internal pure returns (uint256 highestIndex_) {
        highestIndex_ = 7388;
        // highest index corresponds to lowest price
        for (uint256 i = 0; i < indexes.length; ++i) {
            if (indexes[i] < highestIndex_) {
                highestIndex_ = indexes[i];
            }
        }
    }

    function _findLowestIndexPrice(uint256[] memory indexes) internal pure returns (uint256 lowestIndex_) {
        lowestIndex_ = 1;
        // lowest index corresponds to highest price
        for (uint256 i = 0; i < indexes.length; ++i) {
            if (indexes[i] > lowestIndex_) {
                lowestIndex_ = indexes[i];
            }
        }
    }

    // calculates a limit index leaving one index above the htp to accrue interest
    function _findSecondLowestIndexPrice(uint256[] memory indexes) internal pure returns (uint256 secondLowestIndex_) {
        secondLowestIndex_ = 1;
        uint256 lowestIndex = secondLowestIndex_;

        // lowest index corresponds to highest price
        for (uint256 i = 0; i < indexes.length; ++i) {
            if (indexes[i] > lowestIndex) {
                secondLowestIndex_ = lowestIndex;
                lowestIndex = indexes[i];
            }
            else if (indexes[i] > secondLowestIndex_) {
                secondLowestIndex_ = indexes[i];
            }
        }
    }

    function _requiredCollateral(ERC20Pool pool_, uint256 borrowAmount, uint256 indexPrice) internal view returns (uint256 requiredCollateral_) {
        // calculate the required collateral based upon the borrow amount and index price
        (uint256 interestRate, ) = pool_.interestRateInfo();
        uint256 newInterestRate = Maths.wmul(interestRate, 1.1 * 10**18); // interest rate multipled by increase coefficient
        uint256 expectedDebt = Maths.wmul(borrowAmount, _feeRate(newInterestRate) + Maths.WAD);
        requiredCollateral_ = Maths.wdiv(expectedDebt, _poolUtils.indexToPrice(indexPrice)) + Maths.WAD;
    }

    function testClaimRewardsFuzzy(uint256 indexes, uint256 mintAmount) external {
        indexes = bound(indexes, 3, 10); // number of indexes to add liquidity to
        mintAmount = bound(mintAmount, 1 * 1e18, 100_000 * 1e18); // bound mint amount and dynamically determine borrow amount and collateral based upon provided index and mintAmount

        // configure NFT position
        uint256[] memory depositIndexes = new uint256[](indexes);
        for (uint256 i = 0; i < indexes; ++i) {
            depositIndexes[i] = _randomIndex();
            vm.roll(block.number + 1); // advance block to ensure that the index price is different
        }
        MintAndMemorializeParams memory mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterOne,
            mintAmount: mintAmount,
            pool: _poolOne
        });

        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
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
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexes);
        assertGt(_ajnaToken.balanceOf(_updater), 0);

        // calculate rewards earned and compare to percentages for updating and claiming
        // FIXME: can't calculate this for use in updateBucketExchangeRatesAndClaim as current exchange rate hasn't been updated yet 
        uint256 rewardsEarned = _ajnaRewards.calculateRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertGt(rewardsEarned, 0);

        // claim rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, _epochsClaimedArray(1, 0), rewardsEarned);
        _ajnaRewards.claimRewards(tokenIdOne, _poolOne.currentBurnEpoch());
        assertEq(_ajnaToken.balanceOf(_minterOne), rewardsEarned);

        // assert rewards claimed is less than ajna tokens burned cap
        assertLt(_ajnaToken.balanceOf(_minterOne), Maths.wmul(tokensToBurn, 0.800000000000000000 * 1e18));
    }

}
