// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20Pool }        from 'src/erc20/ERC20Pool.sol';
import { ERC20PoolFactory } from 'src/erc20/ERC20PoolFactory.sol';

import 'src/AjnaRewards.sol';
import 'src/IAjnaRewards.sol';

import 'src/base/interfaces/IPositionManager.sol';
import 'src/base/PositionManager.sol';

import { DSTestPlus } from './utils/DSTestPlus.sol';
import { Token }      from './utils/Tokens.sol';

contract AjnaRewardsTest is DSTestPlus {

    // address          internal _ajna = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    address         internal _bidder;
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

    function setUp() external {
        _ajnaToken       = ERC20(_ajna);
        _positionManager = new PositionManager();
        _ajnaRewards     = new AjnaRewards(_ajna, _positionManager);

        _collateralOne = new Token("Collateral 1", "C1");
        _quoteOne      = new Token("Quote 1", "Q1");
        _poolOne       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(_collateralOne), address(_quoteOne), 0.05 * 10**18));

        _collateralTwo = new Token("Collateral 2", "C2");
        _quoteTwo      = new Token("Quote 2", "Q2");
        _poolTwo       = ERC20Pool(new ERC20PoolFactory(_ajna).deployPool(address(_collateralTwo), address(_quoteTwo), 0.05 * 10**18));

        _bidder    = makeAddr("bidder");
    }

    // TODO: dynamically set mint amount
    // TODO: fuzz or randomize the inputs to above function
    // function _getIndexes()
    // function _getAmounts()    
    function _mintAndMemorializePositionNFT(address minter_, ERC20Pool pool_, uint256[] memory indexes_) internal returns (uint256 tokenId_) {
        changePrank(minter_);

        Token collateral = Token(pool_.collateralAddress());
        Token quote = Token(pool_.quoteTokenAddress());

        // deal tokens
        deal(address(collateral), minter_, 250_000 * 1e18);
        deal(address(quote), minter_, 250_000 * 1e18);

        // approve tokens
        collateral.approve(address(pool_), type(uint256).max);
        quote.approve(address(pool_), type(uint256).max);

        IPositionManagerOwnerActions.MintParams memory mintParams = IPositionManagerOwnerActions.MintParams(minter_, address(pool_));
        tokenId_ = _positionManager.mint(mintParams);

        // TODO: make mint amounts dynamic
        for (uint256 i = 0; i < indexes_.length; i++) {
            pool_.addQuoteToken(1000 * 1e18, indexes_[i]);
            pool_.approveLpOwnership(address(_positionManager), indexes_[i], 1_000 * 1e27);
        }

        // construct memorialize params struct
        IPositionManagerOwnerActions.MemorializePositionsParams memory memorializeParams = IPositionManagerOwnerActions.MemorializePositionsParams(
            tokenId_, indexes_
        );

        _positionManager.memorializePositions(memorializeParams);
    }

    // TODO: add support for multiple borrowers
    function _triggerReserveAuctions(ERC20Pool pool_) internal {

        address borrower = makeAddr("borrower");

        changePrank(borrower);

        // TODO: determine how to randomize these values
        // borrower drawsDebt from the pool
        uint256 amountToBorrow = 300 * 1e18;
        uint256 limitIndex = 3;
        uint256 collateralToPledge = 10 * 1e18;
        pool_.drawDebt(borrower, amountToBorrow, limitIndex, collateralToPledge);

        // allow time to pass for interest to accumulate
        skip(26 weeks);

        // borrower repays some of their debt, providing reserves to be claimed
        // don't pull any collateral, as such functionality is unrelated to reserve auctions
        pool_.repayDebt(borrower, amountToBorrow / 2, 0);
    }

    function testDepositToken() external {
        skip(10);

        address testMinterOne = makeAddr("testMinterOne");
        address testMinterTwo = makeAddr("testMinterTwo");

        uint256[] memory depositIndexes = new uint256[](5);
        depositIndexes[0] = 9;
        depositIndexes[1] = 1;
        depositIndexes[2] = 2;
        depositIndexes[3] = 3;
        depositIndexes[4] = 4;
        uint256 tokenIdOne = _mintAndMemorializePositionNFT(testMinterOne, _poolOne, depositIndexes);

        depositIndexes = new uint256[](4);
        depositIndexes[0] = 5;
        depositIndexes[1] = 1;
        depositIndexes[2] = 3;
        depositIndexes[3] = 12;
        uint256 tokenIdTwo = _mintAndMemorializePositionNFT(testMinterTwo, _poolTwo, depositIndexes);

        // minterOne deposits their NFT into the rewards contract
        changePrank(testMinterOne);
        _positionManager.approve(address(_ajnaRewards), tokenIdOne);
        vm.expectEmit(true, true, true, true);
        emit DepositToken(testMinterOne, address(_poolOne), tokenIdOne);
        _ajnaRewards.depositNFT(tokenIdOne);
        (address owner, address pool, uint256 interactionBlock) = _ajnaRewards.getDepositInfo(tokenIdOne);
        assertEq(owner, testMinterOne);
        assertEq(pool, address(_poolOne));
        assertEq(interactionBlock, block.number);

        // minterTwo deposits their NFT into the rewards contract
        changePrank(testMinterTwo);
        _positionManager.approve(address(_ajnaRewards), tokenIdTwo);
        vm.expectEmit(true, true, true, true);
        emit DepositToken(testMinterTwo, address(_poolTwo), tokenIdTwo);        
        _ajnaRewards.depositNFT(tokenIdTwo);
        (owner, pool, interactionBlock) = _ajnaRewards.getDepositInfo(tokenIdTwo);
        assertEq(owner, testMinterTwo);
        assertEq(pool, address(_poolTwo));
        assertEq(interactionBlock, block.number);
    }

    function testWithdrawToken() external {

        // TODO: implement this test
    
    }

    function testCantWithdrawNonOwnedTokens() external {
        // TODO: implement this test
    }

    function testWithdrawAndClaimRewards() external {
        // TODO: implement this test
    }

    function testClaimRewards() external {

        // deposit NFTs into the rewards contract


        // trigger reserve auctions
        _triggerReserveAuctions(_poolOne);

        // TODO: implement this test
    
    }

}
