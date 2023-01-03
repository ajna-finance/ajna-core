// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "@std/Test.sol";
import { IERC20 } from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

import { NFTCollateralToken } from '../utils/Tokens.sol';

import { ERC721Pool }         from 'src/erc721/ERC721Pool.sol';
import { ERC721PoolFactory }  from 'src/erc721/ERC721PoolFactory.sol';

import 'src/base/PoolInfoUtils.sol';
import "./NFTTakeExample.sol";

contract ERC721TakeWithExternalLiquidityTest is Test {
    // pool events
    event Take(address indexed borrower, uint256 amount, uint256 collateral, uint256 bondChange, bool isReward);

    address constant AJNA = 0x9a96ec9B57Fb64FbC60B423d1f4da7691Bd35079;
    address constant DAI  = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    IERC20  private  dai  = IERC20(DAI);
    NFTCollateralToken private nftc;

    ERC721Pool internal _ajnaPool;

    address internal _borrower;
    address internal _borrower2;
    address internal _lender;

    function setUp() external {
        vm.createSelectFork(vm.envString("ETH_RPC_URL"));
        nftc = new NFTCollateralToken();
        vm.makePersistent(address(nftc));
        uint256[] memory tokenIds;
        _ajnaPool = ERC721Pool(new ERC721PoolFactory(AJNA).deployPool(address(nftc), DAI, tokenIds, 0.07 * 10**18));

        // fund lenders
        _lender = makeAddr("lender");
        changePrank(_lender);
        deal(DAI, _lender, 100_000 * 1e18);
        dai.approve(address(_ajnaPool), type(uint256).max);

        // fund borrowers    
        _borrower  = makeAddr("borrower");    
        nftc.mint(_borrower, 3);
        changePrank(_borrower);
        nftc.setApprovalForAll(address(_ajnaPool), true);

        // TODO: eliminate this borrower once the MOMP calculation bug is resolved
        _borrower2 = makeAddr("borrower2");
        nftc.mint(_borrower2, 5);
        changePrank(_borrower2);
        nftc.setApprovalForAll(address(_ajnaPool), true);

        // lender adds liquidity
        uint256 bucketId = _indexOf(1_000 * 1e18);
        assertEq(bucketId, 2770);
        changePrank(_lender);
        _ajnaPool.addQuoteToken(50_000 * 1e18, 2770);

        // borrower adds collateral token and borrows with a low collateralization ratio
        uint256[] memory tokenIdsToAdd = new uint256[](2);
        tokenIdsToAdd[0] = 1;
        tokenIdsToAdd[1] = 3;
        changePrank(_borrower);
        _ajnaPool.drawDebt(_borrower, 1_999 * 1e18, 3232, tokenIdsToAdd);

        // borrower2 adds collateral and borrows a trivial amount
        tokenIdsToAdd[0] = 4;
        tokenIdsToAdd[1] = 5;
        changePrank(_borrower2);
        _ajnaPool.drawDebt(_borrower2, 5 * 1e18, 3232, tokenIdsToAdd);

        // enough time passes that the borrower becomes undercollateralized
        skip(60 days);
        // lender kicks the liquidation
        changePrank(_lender);
        _ajnaPool.kick(_borrower);
        // price becomes favorable
        skip(8 hours);
    }

    function testTakeNFTFromContractWithAtomicSwap() external {
        // instantiate and fund a hypothetical NFT marketplace
        NFTMarketPlace marketPlace = new NFTMarketPlace(dai);
        deal(DAI, address(marketPlace), 25_000 * 1e18);

        // instantiate a taker contract which implements IERC721Taker and uses this marketplace
        NFTTakeExample taker = new NFTTakeExample(address(marketPlace));
        changePrank(address(taker));
        assertEq(dai.balanceOf(address(taker)), 0);
        dai.approve(address(_ajnaPool), type(uint256).max);
        nftc.setApprovalForAll(address(marketPlace), true);

        // call take using taker contract
        bytes memory data = abi.encode(address(_ajnaPool));
        vm.expectEmit(true, true, false, true);
        uint256 quoteTokenPaid = 541.649286848478143296 * 1e18;
        uint256 collateralPurchased = 2 * 1e18;
        uint256 bondChange = 5.416492868484781433 * 1e18;
        emit Take(_borrower, quoteTokenPaid, collateralPurchased, bondChange, true);
        _ajnaPool.take(_borrower, 2, address(taker), data);

        // confirm we earned some quote token
        assertEq(dai.balanceOf(address(taker)), 958.350713151521856704 * 1e18);
    }
}
