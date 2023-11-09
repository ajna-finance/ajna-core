pragma solidity 0.8.18;

import { ERC20HelperContract, ERC20FuzzyHelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';
import 'src/interfaces/pool/commons/IPoolErrors.sol';

contract ERC20PoolBorrowerTPLessThanMinPrice is ERC20HelperContract {

    address internal _borrower;
    address internal _lender;

    function setUp() external {
        _startTest();

        _borrower  = makeAddr("borrower");
        _lender    = makeAddr("lender");

        _mintQuoteAndApproveTokens(_lender,  110 * 1e18);
        _mintCollateralAndApproveTokens(_borrower,  100_000 * 1e18);
    }

    function testTpLessThanMinPriceNoKickable() external tearDown {
        _addInitialLiquidity({
            from:   _lender,
            amount: 110 * 1e9,
            index:  MAX_FENWICK_INDEX
        });

        // Borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   100_000 * 1e18
        });

        _borrow({
            from:       _borrower,
            amount:     100 * 1e9,
            indexLimit: MAX_FENWICK_INDEX,
            newLup:     MIN_PRICE
        });

        (uint256 debt, uint256 collateral, ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        uint256 thresholdPrice = Maths.wdiv(debt, collateral);

        // Ensure borrower tp is less than min price
        assertLt(thresholdPrice, MIN_PRICE);

        // Lender cannot kick borrower with tp less than min price
        changePrank(_lender);
        vm.expectRevert(IPoolErrors.BorrowerOk.selector);
        _pool.lenderKick(MAX_FENWICK_INDEX, MAX_FENWICK_INDEX);
    }
}