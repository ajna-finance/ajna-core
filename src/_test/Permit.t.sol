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

    AjnaToken internal ajnaToken = new AjnaToken(10_000 * 1e18);
    ERC20Pool internal ajnaTokenPool;

    bytes32 internal constant PERMIT_NFT_TYPEHASH =
        0x49ecf333e5b8c95c40fdafc95c1ad136e8914a8fb55e9dc8bb01eaa83a2df9ad;

    // nonce for generating random addresses
    uint16 nonce = 0;

    function setUp() public {
        collateral = new CollateralToken();
        quote = new QuoteToken();

        factory = new ERC20PoolFactory();
        pool = factory.deployPool(address(collateral), address(quote));
        ajnaTokenPool = factory.deployPool(address(collateral), address(ajnaToken));

        positionManager = new PositionManager();
    }

    function generateAddress() private returns (address addr) {
        // https://ethereum.stackexchange.com/questions/72940/solidity-how-do-i-generate-a-random-address
        addr = address(
            uint160(uint256(keccak256(abi.encodePacked(nonce, blockhash(block.number)))))
        );
        nonce++;
    }

    function mintAndApproveQuoteTokens(address operator, uint256 mintAmount) private {
        quote.mint(operator, mintAmount * 1e18);

        vm.prank(operator);
        quote.approve(address(pool), type(uint256).max);
        vm.prank(operator);
        quote.approve(address(positionManager), type(uint256).max);
    }

    function mintAndApproveCollateralTokens(UserWithCollateral operator, uint256 mintAmount)
        private
    {
        collateral.mint(address(operator), mintAmount * 1e18);

        operator.approveToken(collateral, address(pool), mintAmount);
        operator.approveToken(collateral, address(positionManager), mintAmount);
    }

    // abstract away NFT Minting logic for use by multiple tests
    function mintNFT(address minter, address _pool) private returns (uint256 tokenId) {
        IPositionManager.MintParams memory mintParams = IPositionManager.MintParams(minter, _pool);

        vm.prank(mintParams.recipient);
        return positionManager.mint(mintParams);
    }

    // @notice: owner, spender, and unapproved spender mint, approve
    // @notice: and increase liquidity testing permission
    // @notice:  position manager reverts:
    // @notice:     attempts to increase liquidity unapproved spender
    // https://github.com/Rari-Capital/solmate/blob/7c34ed021cfeeefb1a4bff7e511a25ce8a68806b/src/test/ERC20.t.sol#L89-L103
    function testPermitAjnaNFTByEOA() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);
        address spender = generateAddress();
        address unapprovedSpender = generateAddress();

        mintAndApproveQuoteTokens(owner, 10000 * 1e18);
        mintAndApproveQuoteTokens(spender, 10000 * 1e18);

        uint256 deadline = block.timestamp + 1000000;

        uint256 tokenId = mintNFT(owner, address(pool));

        // check EOA can be approved via Permit()
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    positionManager.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_NFT_TYPEHASH, spender, tokenId, 0, deadline))
                )
            )
        );

        (uint96 nonceBeforePermit, , ) = positionManager.positions(tokenId);

        positionManager.permit(spender, tokenId, deadline, v, r, s);

        // check that nonce has been incremented
        (uint96 nonceAfterPermit, , ) = positionManager.positions(tokenId);
        assertEq(nonceAfterPermit, 1);
        assert(nonceAfterPermit > nonceBeforePermit);

        // check that spender was approved
        assertEq(positionManager.getApproved(tokenId), spender);
        assertTrue(positionManager.getApproved(tokenId) != unapprovedSpender);

        // check can add liquidity as approved spender
        IPositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParamsApproved = IPositionManager.IncreaseLiquidityParams(
                tokenId,
                owner,
                address(pool),
                (10000 * 1e18) / 4,
                1_004.989662429170775094 * 10**18
            );

        uint256 balanceBeforeAdd = quote.balanceOf(owner);

        vm.expectEmit(true, true, true, true);
        emit IncreaseLiquidity(owner, (10000 * 1e18) / 4, 1_004.989662429170775094 * 10**18);

        vm.prank(spender);
        positionManager.increaseLiquidity(increaseLiquidityParamsApproved);

        // check that quote tokens have been transferred from the owner
        assert(quote.balanceOf(owner) < balanceBeforeAdd);

        // attempt and fail to add liquidity as unapprovedSpender
        IPositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParamsUnapproved = IPositionManager.IncreaseLiquidityParams(
                tokenId,
                owner,
                address(pool),
                (10000 * 1e18) / 4,
                1_004.989662429170775094 * 10**18
            );

        vm.prank(unapprovedSpender);
        vm.expectRevert(PositionManager.NotApproved.selector);
        positionManager.increaseLiquidity(increaseLiquidityParamsUnapproved);
    }

    // @notice: owner, newowner, spender, unapproved spender testing permission
    // @notice: generate permit sig and allow approved spender to transfer NFT
    // @notice: unapproved spender reverts:
    // @notice:     attempts to transfer NFT when not permitted
    function testSafeTransferFromWithPermit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);
        address newOwner = generateAddress();
        address spender = generateAddress();
        address unapprovedSpender = generateAddress();

        mintAndApproveQuoteTokens(owner, 10000 * 1e18);

        uint256 deadline = block.timestamp + 1000000;
        uint256 tokenId = mintNFT(owner, address(pool));

        // generate permit signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    positionManager.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_NFT_TYPEHASH, spender, tokenId, 0, deadline))
                )
            )
        );

        // it should block an unapproved spender from interacting with the NFT
        vm.expectRevert("ERC721: transfer caller is not owner nor approved");
        vm.prank(unapprovedSpender);
        positionManager.safeTransferFromWithPermit(
            owner,
            newOwner,
            spender,
            tokenId,
            deadline,
            v,
            r,
            s
        );

        // it should allow the permitted spender to interact with the NFT
        vm.prank(spender);
        positionManager.safeTransferFromWithPermit(
            owner,
            newOwner,
            spender,
            tokenId,
            deadline,
            v,
            r,
            s
        );

        (, address ownerAfterTransfer, ) = positionManager.positions(tokenId);
        assertEq(newOwner, ownerAfterTransfer);
        assert(ownerAfterTransfer != owner);
    }

    // @notice: Tests that contract can be approved to increase liquidity
    // TODO: finish implementing -> Requires updating test contracts to have an owner set to our private key, with that owner then signing a message hash provided by a contract view function.
    // contracts don't have private keys, so will have to use EIP-1271 here
    // https://soliditydeveloper.com/meta-transactions
    // https://github.com/gnosis/safe-contracts/blob/186a21a74b327f17fc41217a927dea7064f74604/contracts/examples/libraries/SignMessage.sol#L9
    function xtestPermitAjnaNFTByContract() public {
        uint256 privateKey = 0xBEEF;
        UserWithQuoteToken minter = new UserWithQuoteToken();
        quote.mint(address(minter), 200_000 * 1e18);
        minter.approveToken(quote, address(pool), 200_000 * 1e18);

        uint256 liquidityToAdd = 10000 * 1e18;
        uint256 price = 1_004.989662429170775094 * 10**18;

        uint256 tokenId = mintNFT(address(minter), address(pool));

        UserWithQuoteToken contractSpender = new UserWithQuoteToken();
        UserWithQuoteToken unapprovedContractSpender = new UserWithQuoteToken();

        uint256 deadline = block.timestamp + 1000000;

        // check EOA can be approved via Permit()
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    positionManager.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(
                            PERMIT_NFT_TYPEHASH,
                            address(contractSpender),
                            tokenId,
                            0,
                            deadline
                        )
                    )
                )
            )
        );

        positionManager.permit(address(contractSpender), tokenId, deadline, v, r, s);

        // check that nonce has been incremented
        (uint96 nonces, , ) = positionManager.positions(tokenId);
        assertEq(nonces, 1);

        // check that spender was approved
        assertEq(positionManager.getApproved(tokenId), address(contractSpender));
        assertTrue(positionManager.getApproved(tokenId) != address(unapprovedContractSpender));

        // check can add liquidity as approved contract spender
        IPositionManager.IncreaseLiquidityParams
            memory increaseLiquidityParamsApproved = IPositionManager.IncreaseLiquidityParams(
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

    // @notice: Tests that Ajna token can be permitted for use by another EOA
    function testPermitAjnaERC20() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        address spender = generateAddress();
        address unapprovedSpender = generateAddress();

        ajnaToken.transfer(owner, 1 * 1e18);
        assert(ajnaToken.balanceOf(owner) > 0);

        bytes32 PERMIT_ERC20_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        uint256 deadline = block.timestamp + 1000000;
        uint256 permitAmount = 10 * 1e18;

        mintNFT(owner, address(pool));

        // check EOA can be approved via Permit()
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    ajnaToken.DOMAIN_SEPARATOR(),
                    keccak256(
                        abi.encode(PERMIT_ERC20_TYPEHASH, owner, spender, permitAmount, 0, deadline)
                    )
                )
            )
        );

        uint256 nonceBeforePermit = ajnaToken.nonces(owner);

        ajnaToken.permit(owner, spender, permitAmount, deadline, v, r, s);

        uint256 nonceAfterPermit = ajnaToken.nonces(owner);

        // check permit nonce has incremented
        assert(nonceAfterPermit > nonceBeforePermit);
        assertEq(nonceAfterPermit, 1);

        // check that spender was approved
        assert(ajnaToken.allowance(owner, spender) > 0);
        assert(ajnaToken.allowance(owner, unapprovedSpender) == 0);
    }
}
