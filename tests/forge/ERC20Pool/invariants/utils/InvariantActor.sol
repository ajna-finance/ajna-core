pragma solidity 0.8.14;

import "forge-std/console.sol";

import { ERC20Pool }        from 'src/ERC20Pool.sol';
import { Token }            from '../../../utils/Tokens.sol';

// this contract acts as a single lender
contract InvariantActor {
    address internal _quote;
    address internal _pool;
    address internal _collateral;
    
    constructor(address pool, address quote, address collateral) {
        _pool       = pool;
        _quote      = quote;
        _collateral = collateral;
        Token(_quote).mint(address(this), 1e40);
        Token(_quote).approve(_pool, 1e40);
        Token(_collateral).mint(address(this), 1e40);
        Token(_collateral).approve(_pool, 1e40);
    }

    function addQuoteToken(uint256 amount_, uint256 bucketIndex_) external {
        console.log("A: add");
        ERC20Pool(_pool).addQuoteToken(amount_, bucketIndex_);
    }

    function removeQuoteToken(uint256 amount_, uint256 bucketIndex_) external {
        console.log("A: remove");
        ERC20Pool(_pool).removeQuoteToken(amount_, bucketIndex_);
    }

    function drawDebt(uint256 amountToBorrow_, uint256 limitIndex_, uint256 collateralToPledge_) external {
        console.log("A: draw");
        ERC20Pool(_pool).drawDebt(address(this), amountToBorrow_, limitIndex_, collateralToPledge_);
    }

    function repayDebt(uint256 amountToRepay_) external {
        console.log("A: repay");
        ERC20Pool(_pool).repayDebt(address(this), amountToRepay_, 0);
    }

    function kickAuction(address borrower_) external {
        console.log("A: kick");
        ERC20Pool(_pool).kick(borrower_);
    }

    function takeAuction(address borrower_, uint256 amount_, address taker_) external {
        console.log("A: take");
        ERC20Pool(_pool).take(borrower_, amount_, taker_, bytes(""));
    }

    function lenderLpBalance(uint256 bucketIndex_) external view returns(uint256 _lps) {
        console.log("A: lenderLpBalance");
        (_lps, ) = ERC20Pool(_pool).lenderInfo(bucketIndex_, address(this));
    }
}