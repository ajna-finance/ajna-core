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

    // address          internal _ajna = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    address         internal _bidder;
    address         internal _minterOne;
    address         internal _minterTwo;
    address         internal _minterThree;

    ERC20           internal _ajnaToken;

    AjnaRewards     internal _ajnaRewards;
    PositionManager internal _positionManager;

    Token           internal _collateralOne;
    Token           internal _quoteOne;
    ERC20Pool       internal _poolOne;

    Token           internal _collateralTwo;
    Token           internal _quoteTwo;
    ERC20Pool       internal _poolTwo;

    event ClaimRewards(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId, uint256 amount);
    event DepositToken(address indexed owner, address indexed ajnaPool, uint256 indexed tokenId);
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
        uint256 collateralToPledge;
        uint256 limitIndex;
        ERC20Pool pool;
    }

    function setUp() external {

        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        vm.makePersistent(_ajna);

        _ajnaToken       = ERC20(_ajna);
        _positionManager = new PositionManager();
        _ajnaRewards     = new AjnaRewards(_ajna, _positionManager);
        _poolUtils       = new PoolInfoUtils();

        _collateralOne = new Token("Collateral 1", "C1");
        _quoteOne      = new Token("Quote 1", "Q1");
        _poolOne       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(_collateralOne), address(_quoteOne), 0.05 * 10**18));

        _collateralTwo = new Token("Collateral 2", "C2");
        _quoteTwo      = new Token("Quote 2", "Q2");
        _poolTwo       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(_collateralTwo), address(_quoteTwo), 0.05 * 10**18));

        // provide initial ajna tokens to staking rewards contract
        deal(_ajna, address(_ajnaRewards), 100_000_000 * 1e18);
        assertEq(_ajnaToken.balanceOf(address(_ajnaRewards)), 100_000_000 * 1e18);

        // instaantiate test minters
        _minterOne   = makeAddr("minterOne");
        _minterTwo   = makeAddr("minterTwo");
        _minterThree = makeAddr("minterThree");
    }

    function _depositNFT(address pool_, address owner_, uint256 tokenId_) internal {
        changePrank(owner_);

        // approve and deposit NFT into rewards contract
        _positionManager.approve(address(_ajnaRewards), tokenId_);
        vm.expectEmit(true, true, true, true);
        emit DepositToken(owner_, address(pool_), tokenId_);
        _ajnaRewards.depositNFT(tokenId_);

        // check deposit state
        (address owner, address pool, uint256 interactionBlock) = _ajnaRewards.getDepositInfo(tokenId_);
        assertEq(owner, owner_);
        assertEq(pool, address(pool_));
        assertEq(interactionBlock, block.number);

        // check token was transferred to rewards contract
        assertEq(_positionManager.ownerOf(tokenId_), address(_ajnaRewards));
    }

    function _mintAndApproveAjnaTokens(address operator_, address pool_, uint256 mintAmount_) internal {
        deal(_ajna, operator_, mintAmount_);
        changePrank(operator_);
        _ajnaToken.approve(pool_, type(uint256).max);
    }

    // TODO: dynamically set mint amount
    // TODO: fuzz or randomize the inputs to above function
    // function _getIndexes()
    // function _getAmounts()    
    function _mintAndMemorializePositionNFT(MintAndMemorializeParams memory params_) internal returns (uint256 tokenId_) {
        changePrank(params_.minter);

        Token collateral = Token(params_.pool.collateralAddress());
        Token quote = Token(params_.pool.quoteTokenAddress());

        // deal tokens to the minter
        deal(address(collateral), params_.minter, 250_000 * 1e18);
        deal(address(quote), params_.minter, 250_000 * 1e18);

        // approve tokens
        collateral.approve(address(params_.pool), type(uint256).max);
        quote.approve(address(params_.pool), type(uint256).max);

        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(params_.minter, address(params_.pool));
        tokenId_ = _positionManager.mint(mintParams);

        // TODO: make mint amounts dynamic
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

    // TODO: add support for multiple borrowers
    function _triggerReserveAuctions(TriggerReserveAcutionParams memory params_) internal returns (uint256 tokensToBurn_) {

        address borrower = makeAddr("borrower");

        changePrank(borrower);

        Token collateral = Token(params_.pool.collateralAddress());
        Token quote = Token(params_.pool.quoteTokenAddress());

        // deal tokens
        deal(address(collateral), borrower, 250_000 * 1e18);
        deal(address(quote), borrower, 250_000 * 1e18);

        // approve tokens
        collateral.approve(address(params_.pool), type(uint256).max);
        quote.approve(address(params_.pool), type(uint256).max);

        // borrower drawsDebt from the pool
        params_.pool.drawDebt(borrower, params_.borrowAmount, params_.limitIndex, params_.collateralToPledge);

        // allow time to pass for interest to accumulate
        skip(26 weeks);

        // TODO: calculate borrower debt

        // borrower repays some of their debt, providing reserves to be claimed
        // don't pull any collateral, as such functionality is unrelated to reserve auctions
        params_.pool.repayDebt(borrower, params_.borrowAmount / 2, 0);

        // provide ajna tokens to bidder
        _bidder    = makeAddr("bidder");
        _mintAndApproveAjnaTokens(_bidder, address(params_.pool), 900_000_000 * 10**18);

        // start reserve auction
        changePrank(_bidder);
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

        // minterTwo deposits their NFT into the rewards contract
        _depositNFT(address(_poolTwo), _minterTwo, tokenIdTwo);
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
            collateralToPledge: 10 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });
        uint256 tokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);

        // check only deposit owner can claim rewards
        vm.expectRevert(IAjnaRewards.NotOwnerOfToken.selector);
        _ajnaRewards.claimRewards(tokenIdOne);

        // TODO: check interest accrued by calling calculateRewardsEarned

        // claim rewards accrued since deposit
        changePrank(_minterOne);
        assertEq(_ajnaToken.balanceOf(_minterOne), 0);
        // vm.expectEmit(true, true, true, true);
        // emit ClaimRewards(_minterOne, address(_poolOne), tokenIdOne, 1000 );
        _ajnaRewards.claimRewards(tokenIdOne);
        assertGt(_ajnaToken.balanceOf(_minterOne), 0);

        // check deposit state
        (address owner, address pool, uint256 interactionBlock) = _ajnaRewards.getDepositInfo(tokenIdOne);
        assertEq(owner, _minterOne);
        assertEq(pool, address(_poolOne));
        assertEq(interactionBlock, block.number);
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
            collateralToPledge: 10 * 1e18,
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
            collateralToPledge: 10 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });
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



        // FIXME: this won't fire as checkpoints haven't loaded yet
        // check rewards state
        // uint256 remainingRewards = _ajnaRewards.calculateRewardsEarned(tokenIdOne);
        // assertEq(remainingRewards, 0);

        // TODO: test depositor 3
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

        // TODO: use singleton test params as argument for each meta method
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(mintMemorializeParams);
        _depositNFT(address(_poolOne), _minterOne, tokenIdOne);

        TriggerReserveAcutionParams memory triggerReserveAuctionParams = TriggerReserveAcutionParams({
            borrowAmount: 300 * 1e18,
            collateralToPledge: 10 * 1e18,
            limitIndex: 3,
            pool: _poolOne
        });


        // uint256 tokensToBurn = _triggerReserveAuctions(triggerReserveAuctionParams);




    }

    function testClaimRewardsFuzzy() external {
        // TODO: implement this
    }

    function testMultiplePools() external {
        // TODO: implement this
    }


}
