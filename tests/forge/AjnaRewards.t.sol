// SPDX-License-Identifier: GPL-3.0-or-later
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
    address         internal _updater;

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

    event ClaimRewards(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256 amount);
    event DepositToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);
    event UpdateExchangeRates(address indexed caller, address indexed ajnaPool, uint256[] indexesUpdated, uint256 rewardsClaimed);
    event WithdrawToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);

    uint256 constant BLOCKS_IN_DAY = 7200;

    struct MintAndMemorializeParams {
        uint256[] indexes;
        address minter;
        uint256 mintAmount;
        ERC20Pool pool;
    }

    struct TriggerReserveAcutionParams {
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

        // instantiate test bidder
        _bidder    = makeAddr("bidder");
        changePrank(_bidder);
        deal(_ajna, _bidder, 900_000_000 * 10**18);

        // instantiate test updater
        _updater    = makeAddr("updater");
    }

    function _depositNFT(address pool_, address owner_, uint256 tokenId_) internal {
        changePrank(owner_);

        // approve and deposit NFT into rewards contract
        _positionManager.approve(address(_ajnaRewards), tokenId_);
        vm.expectEmit(true, true, true, true);
        emit DepositToken(owner_, address(pool_), tokenId_);
        _ajnaRewards.depositNFT(tokenId_);

        // check token was transferred to rewards contract
        assertEq(_positionManager.ownerOf(tokenId_), address(_ajnaRewards));
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

    function _triggerReserveAuctions(TriggerReserveAcutionParams memory params_) internal returns (uint256 tokensToBurn_) {
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

        // TODO: create meta method to simultaneously update timestamp and block
        // allow time to pass for the reserve price to decrease
        skip(24 hours);
        vm.roll(block.number + BLOCKS_IN_DAY);

        (
            ,
            uint256 curClaimableReserves,
            uint256 curClaimableReservesRemaining,
            uint256 curAuctionPrice,
        ) = _poolUtils.poolReservesInfo(address(params_.pool));

        // take claimable reserves
        params_.pool.takeReserves(curClaimableReservesRemaining);

        // calculate ajna tokens to burn in order to take the full auction amount
        tokensToBurn_ = curClaimableReservesRemaining * curAuctionPrice;
    }

    // calculate the amount of tokens that are expected to be earned based upon current state
    function _localRewardsEarned() internal {
        // TODO: finish implementing this -> use for differential testing
    }

    function testDepositToken() external {
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
        vm.expectRevert(IAjnaRewards.NotOwnerOfToken.selector);
        _ajnaRewards.depositNFT(tokenIdOne);

        // minterOne deposits their NFT into the rewards contract
        _depositNFT(address(_poolOne), _minterOne, tokenIdOne);
        // check deposit state
        (address owner, address pool, uint256 interactionBurnEvent) = _ajnaRewards.getDepositInfo(tokenIdOne);
        assertEq(owner, _minterOne);
        assertEq(pool, address(_poolOne));
        assertEq(interactionBurnEvent, 0);

        // minterTwo deposits their NFT into the rewards contract
        _depositNFT(address(_poolTwo), _minterTwo, tokenIdTwo);
        // check deposit state
        (owner, pool, interactionBurnEvent) = _ajnaRewards.getDepositInfo(tokenIdTwo);
        assertEq(owner, _minterTwo);
        assertEq(pool, address(_poolTwo));
        assertEq(interactionBurnEvent, 0);
    }

    function testClaimRewards() external {
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
        _depositNFT(address(_poolOne), _minterOne, tokenIdOne);

        // borrower takes actions providing reserves enabling reserve auctions
        // bidder takes reserve auctions by providing ajna tokens to be burned
        TriggerReserveAcutionParams memory triggerReserveAuctionParams = TriggerReserveAcutionParams({
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
        assertGt(_ajnaToken.balanceOf(_updater), 0);

        // check only deposit owner can claim rewards
        vm.expectRevert(IAjnaRewards.NotOwnerOfToken.selector);
        _ajnaRewards.claimRewards(tokenIdOne);

        // TODO: check interest accrued by calling calculateRewardsEarned

        // claim rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, 18.085912173086791740 * 1e18);
        _ajnaRewards.claimRewards(tokenIdOne);
        assertGt(_ajnaToken.balanceOf(_minterOne), 0);

        // check deposit state
        (address owner, address pool, uint256 interactionBurnEvent) = _ajnaRewards.getDepositInfo(tokenIdOne);
        assertEq(owner, _minterOne);
        assertEq(pool, address(_poolOne));
        assertEq(interactionBurnEvent, 1);
        assertEq(_positionManager.ownerOf(tokenIdOne), address(_ajnaRewards));

        // assert rewards claimed is less than ajna tokens burned
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);
    }

    function testClaimRewardsMultipleDepositsSameBucketsMultipleAuctions() external {
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
        _depositNFT(address(_poolOne), _minterOne, tokenIdOne);

        // borrower takes actions providing reserves enabling reserve auctions
        TriggerReserveAcutionParams memory triggerReserveAuctionParams = TriggerReserveAcutionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });
        uint256 auctionOneTokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        // second depositor deposits an NFT representing the same positions into the rewards contract
        mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterTwo,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _depositNFT(address(_poolOne), _minterTwo, tokenIdTwo);

        // calculate rewards earned since exchange rates have been updated
        uint256 idOneRewardsAtOne = _ajnaRewards.calculateRewardsEarned(tokenIdOne);
        assertLt(idOneRewardsAtOne, auctionOneTokensToBurn);
        assertGt(idOneRewardsAtOne, 0);

        // borrower takes actions providing reserves enabling additional reserve auctions
        vm.roll(block.number + 10);
        triggerReserveAuctionParams = TriggerReserveAcutionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });

        // check can't trigger reserve auction if less than two weeks have passed since last auction
        // FIXME: breaking due to an apparent foundry bug on _triggerReserveAuctions params.pool.collateralAddress()
        // vm.expectRevert(IPoolErrors.ReserveAuctionTooSoon.selector);
        // vm.expectRevert(abi.encodeWithSignature('ReserveAuctionTooSoon()'));
        // _triggerReserveAuctions(triggerReserveAuctionParams);

        // roll blocks pass cooldown period to enable next reserve auction
        vm.roll(block.number + 110_000);
        uint256 auctionTwoTokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        // third depositor deposits an NFT representing the same positions into the rewards contract
        mintMemorializeParams = MintAndMemorializeParams({
            indexes: depositIndexes,
            minter: _minterThree,
            mintAmount: 1000 * 1e18,
            pool: _poolOne
        });
        uint256 tokenIdThree = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _depositNFT(address(_poolOne), _minterThree, tokenIdThree);

        // calculate rewards earned since exchange rates have been updated
        uint256 idOneRewardsAtTwo = _ajnaRewards.calculateRewardsEarned(tokenIdOne);
        assertLt(idOneRewardsAtTwo, auctionTwoTokensToBurn);
        assertGt(idOneRewardsAtTwo, 0);
        assertGt(idOneRewardsAtTwo, idOneRewardsAtOne);

        uint256 idTwoRewardsAtTwo = _ajnaRewards.calculateRewardsEarned(tokenIdTwo);
        assertLt(idOneRewardsAtTwo + idTwoRewardsAtTwo, auctionTwoTokensToBurn);
        assertGt(idTwoRewardsAtTwo, 0);

        // TODO: check calling updateExchangeRates? Not needed since deposits will update the exchange rate themselves

        // minter one claims rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, idOneRewardsAtTwo);
        _ajnaRewards.claimRewards(tokenIdOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), idOneRewardsAtTwo);

        // minter two claims rewards accrued since deposit
        changePrank(_minterTwo);
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterTwo, address(_poolOne), tokenIdTwo, idTwoRewardsAtTwo);
        _ajnaRewards.claimRewards(tokenIdTwo);
        assertEq(_ajnaToken.balanceOf(_minterTwo), idTwoRewardsAtTwo);

        // check there are no remaining rewards available after claiming
        vm.roll(block.number + 1);
        uint256 remainingRewards = _ajnaRewards.calculateRewardsEarned(tokenIdOne);
        assertEq(remainingRewards, 0);

        remainingRewards = _ajnaRewards.calculateRewardsEarned(tokenIdTwo);
        assertEq(remainingRewards, 0);

        remainingRewards = _ajnaRewards.calculateRewardsEarned(tokenIdThree);
        assertEq(remainingRewards, 0);
    }

    function testClaimRewardsMultipleDepositsDifferentBucketsMultipleAuctions() external {

        // TODO: implement this -> instead of using the same RewardsTestParams struct for each new depositor, use modified structs across depositors

    }

    function testWithdrawToken() external {
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
        _depositNFT(address(_poolOne), _minterOne, tokenIdOne);

        // only owner should be able to withdraw the NFT
        changePrank(nonOwner);
        vm.expectRevert(IAjnaRewards.NotOwnerOfToken.selector);
        _ajnaRewards.withdrawNFT(tokenIdOne);

        vm.roll(block.number + 1);

        // check owner can withdraw the NFT
        changePrank(_minterOne);
        vm.expectEmit(true, true, true, true);
        emit WithdrawToken(_minterOne, address(_poolOne), tokenIdOne);
        _ajnaRewards.withdrawNFT(tokenIdOne);
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
        _depositNFT(address(_poolOne), _minterOne, tokenIdOne);

        TriggerReserveAcutionParams memory triggerReserveAuctionParams = TriggerReserveAcutionParams({
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
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, 18.085912173086791740 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit WithdrawToken(_minterOne, address(_poolOne), tokenIdOne);
        _ajnaRewards.withdrawNFT(tokenIdOne);
        assertEq(_positionManager.ownerOf(tokenIdOne), _minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 18.085912173086791740 * 1e18);
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);
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
        _depositNFT(address(_poolOne), _minterOne, tokenIdOne);

        // minterTwo deposits their NFT into the rewards contract
        _depositNFT(address(_poolTwo), _minterTwo, tokenIdTwo);

        // borrower takes actions providing reserves enabling reserve auctions
        // bidder takes reserve auctions by providing ajna tokens to be burned
        TriggerReserveAcutionParams memory triggerReserveAuctionParams = TriggerReserveAcutionParams({
            borrowAmount: 300 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });
        uint256 tokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        // check only deposit owner can claim rewards
        changePrank(_minterTwo);
        vm.expectRevert(IAjnaRewards.NotOwnerOfToken.selector);
        _ajnaRewards.claimRewards(tokenIdOne);

        // check rewards earned in one pool shouldn't be claimable by depositors from another pool
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);
        _ajnaRewards.claimRewards(tokenIdTwo);
        assertEq(_ajnaToken.balanceOf(_minterTwo), 0);

        // call update exchange rate to enable claiming rewards
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit UpdateExchangeRates(_minterOne, address(_poolOne), depositIndexesOne, 1.808591217308675030 * 1e18);
        _ajnaRewards.updateBucketExchangeRatesAndClaim(address(_poolOne), depositIndexesOne);
        assertGt(_ajnaToken.balanceOf(_minterOne), 0);

        // check owner in pool with accrued interest can properly claim rewards
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 1.808591217308675030 * 1e18);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, 18.085912173086791740 * 1e18);
        _ajnaRewards.claimRewards(tokenIdOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 19.894503390395466770 * 1e18);
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
        _depositNFT(address(_poolOne), _minterOne, tokenIdOne);

        // calculates a limit index leaving one index above the htp to accrue interest
        uint256 limitIndex = _findSecondLowestIndexPrice(depositIndexes);
        TriggerReserveAcutionParams memory triggerReserveAuctionParams = TriggerReserveAcutionParams({
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
        uint256 rewardsEarned = _ajnaRewards.calculateRewardsEarned(tokenIdOne);
        assertGt(rewardsEarned, 0);

        // claim rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        vm.expectEmit(true, true, true, true);
        emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, rewardsEarned);
        _ajnaRewards.claimRewards(tokenIdOne);
        assertGt(_ajnaToken.balanceOf(_minterOne), 0);
        assertLt(_ajnaToken.balanceOf(_minterOne), tokensToBurn);
    }

}
