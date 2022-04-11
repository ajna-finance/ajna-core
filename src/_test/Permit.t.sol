// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {DSTestPlus} from "./utils/DSTestPlus.sol";

import {UserWithCollateral, UserWithQuoteToken} from "./utils/Users.sol";
import {CollateralToken, QuoteToken} from "./utils/Tokens.sol";

import {ERC20Pool} from "../ERC20Pool.sol";
import {ERC20PoolFactory} from "../ERC20PoolFactory.sol";
import {PositionManager, IPositionManager} from "../PositionManager.sol";

import {AjnaToken} from "../tokens/Ajna.sol";


contract PermitTest is DSTestPlus {
    PositionManager internal positionManager;
    ERC20Pool internal pool;
    ERC20PoolFactory internal factory;

    CollateralToken internal collateral;
    QuoteToken internal quote;

    AjnaToken internal token = new AjnaToken(10_000 * 1e18);
    ERC20Pool internal ajnaTokenPool;


    // nonce for generating random addresses
    uint16 nonce = 0;
    function setUp() public {

        collateral = new CollateralToken();
        quote = new QuoteToken();

        factory = new ERC20PoolFactory();
        pool = factory.deployPool(collateral, quote);
        ajnaTokenPool = factory.deployPool(collateral, AjnaToken);
        positionManager = new PositionManager();
    }

    function generateAddress() private returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(
            uint160(
                uint256(
                    keccak256(abi.encodePacked(nonce, blockhash(block.number)))
                )
            )
        );
        nonce++;
    }

    function mintAndApproveQuoteTokens(
        address operator,
        uint256 mintAmount
    ) private {
        quote.mint(operator, mintAmount * 1e18);

        vm.prank(operator);
        quote.approve(address(pool), type(uint256).max);
        vm.prank(operator);
        quote.approve(address(positionManager), type(uint256).max);
    }

    function mintAndApproveCollateralTokens(
        UserWithCollateral operator,
        uint256 mintAmount
    ) private {
        collateral.mint(address(operator), mintAmount * 1e18);

        operator.approveToken(collateral, address(pool), mintAmount);
        operator.approveToken(collateral, address(positionManager), mintAmount);
    }

    // abstract away NFT Minting logic for use by multiple tests
    function mintNFT(address minter, address _pool)
        private
        returns (uint256 tokenId)
    {
        IPositionManager.MintParams memory mintParams = IPositionManager
            .MintParams(minter, _pool);

        vm.prank(mintParams.recipient);
        return positionManager.mint(mintParams);
    }

    function increaseLiquidityWithPermit() public {

    }


    // TODO: check test flow -> permit w/out contract call?
    // TODO: check how token approvals are handled
    // https://github.com/Rari-Capital/solmate/blob/7c34ed021cfeeefb1a4bff7e511a25ce8a68806b/src/test/ERC20.t.sol#L89-L103
    function testPermitEOA() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);
        address spender = generateAddress();
        address unapprovedSpender = generateAddress();

        mintAndApproveQuoteTokens(owner, 10000 * 1e18);
        mintAndApproveQuoteTokens(spender, 10000 * 1e18);

        bytes32 PERMIT_TYPEHASH = 0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;
        uint256 deadline = block.timestamp + 1000000;

        uint256 tokenId = mintNFT(owner, address(pool));

        // check EOA can be approved via Permit()
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    positionManager.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, spender, tokenId, 0, deadline))
                )
            )
        );

        (uint96 nonceBeforePermit,,) = positionManager.positions(tokenId);

        emit log_uint(nonceBeforePermit);

        positionManager.permit(spender, tokenId, deadline, v, r, s);

        // check that nonce has been incremented
        (uint96 nonceAfterPermit,,) = positionManager.positions(tokenId);
        assertEq(nonceAfterPermit, 1);
        assert(nonceAfterPermit > nonceBeforePermit);

        // check that spender was approved
        assertEq(positionManager.getApproved(tokenId), spender);
        assertTrue(positionManager.getApproved(tokenId) != unapprovedSpender);

        // check can add liquidity as approved spender
        IPositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParamsApproved = IPositionManager
                .IncreaseLiquidityParams(
                    tokenId,
                    owner,
                    address(pool),
                    (10000 * 1e18) / 4,
                    1_004.989662429170775094 * 10**18
                );

        uint256 balanceBeforeAdd = quote.balanceOf(owner);

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(owner, 10000 * 1e18 / 4, 1_004.989662429170775094 * 10**18);

        vm.prank(spender);
        positionManager.increaseLiquidity(increaseLiquidityParamsApproved);

        // check that quote tokens have been transferred from the owner
        assert(quote.balanceOf(owner) < balanceBeforeAdd);

        // attempt and fail to add liquidity as unapprovedSpender
        IPositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParamsUnapproved = IPositionManager
                .IncreaseLiquidityParams(
                    tokenId,
                    owner,
                    address(pool),
                    (10000 * 1e18) / 4,
                    1_004.989662429170775094 * 10**18
                );

        vm.prank(unapprovedSpender);
        vm.expectRevert("ajna/not-approved");
        positionManager.increaseLiquidity(increaseLiquidityParamsUnapproved);

        // // TODO: resolve stack too deep issue
        // // transfer again and check nonce and approvals
        // uint256 secondPrivateKey = 0xBE;
        // address secondOwner = vm.addr(secondPrivateKey);
        // mintAndApproveQuoteTokens(secondOwner, 10000 * 1e18);

        // // check second EOA can be approved via Permit()
        // (v, r, s) = vm.sign(
        //     secondPrivateKey,
        //     keccak256(
        //         abi.encodePacked(
        //             "\x19\x01",
        //             positionManager.DOMAIN_SEPARATOR(),
        //             keccak256(abi.encode(PERMIT_TYPEHASH, spender, tokenId, 0, deadline))
        //         )
        //     )
        // );
        // positionManager.permit(spender, tokenId, deadline, v, r, s);

    }

    // contracts don't have private keys, so will have to use EIP-1271 here
    // https://soliditydeveloper.com/meta-transactions
    function testPermitContract() public {
        // TODO: use the privateKey to generate salt so we know the contract address
        uint256 privateKey = 0xBEEF;
        UserWithQuoteToken minter = new UserWithQuoteToken();
        quote.mint(address(minter), 200_000 * 1e18);
        minter.approveToken(quote, address(pool), 200_000 * 1e18);

        uint256 liquidityToAdd = 10000 * 1e18;
        uint256 price = 1_004.989662429170775094 * 10**18;

        uint256 tokenId = mintNFT(address(minter), address(pool));

        UserWithQuoteToken contractSpender = new UserWithQuoteToken();
        UserWithQuoteToken unapprovedContractSpender = new UserWithQuoteToken();

        bytes32 PERMIT_TYPEHASH = 0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;
        uint256 deadline = block.timestamp + 1000000;

        // check EOA can be approved via Permit()
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    positionManager.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, address(contractSpender), tokenId, 0, deadline))
                )
            )
        );

        positionManager.permit(address(contractSpender), tokenId, deadline, v, r, s);

        // check that nonce has been incremented
        (uint96 nonces,,) = positionManager.positions(tokenId);
        assertEq(nonces, 1);

        // check that spender was approved
        assertEq(positionManager.getApproved(tokenId), address(contractSpender));
        assertTrue(positionManager.getApproved(tokenId) != address(unapprovedContractSpender));

        // check can add liquidity as approved contract spender
        IPositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParamsApproved = IPositionManager
                .IncreaseLiquidityParams(
                    tokenId,
                    address(minter),
                    address(pool),
                    liquidityToAdd,
                    price
                );

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(address(minter), liquidityToAdd, price);

        vm.prank(address(contractSpender));
        positionManager.increaseLiquidity(increaseLiquidityParamsApproved);
    }

    // TODO: test against Ajna token
    function testPermitERC20() public {

        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        token.transfer(owner, 1);
        assert(token.balanceOf(owner) > 0);

        // mint Ajna tokens to be used as quote tokens w/ permit functionality
        ajnaTokenPool;

    }

}