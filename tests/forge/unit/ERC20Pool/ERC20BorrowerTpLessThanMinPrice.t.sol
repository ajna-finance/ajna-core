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

    function testTpLessThanMinPriceBorrowerKickable() external tearDown {
        _addInitialLiquidity({
            from:   _lender,
            amount: 1100 * 1e9,
            index:  2550
        });

        // Borrower adds collateral token and borrows
        _pledgeCollateral({
            from:     _borrower,
            borrower: _borrower,
            amount:   10 * 1e18
        });

        _borrow({
            from:       _borrower,
            amount:     900 * 1e9,
            indexLimit: 2550,
            newLup:     3_010.892022197881557845 * 1e18
        });

        (uint256 debt, uint256 collateral, , ) = _poolUtils.borrowerInfo(address(_pool), _borrower);
        uint256 debtToCollateral = Maths.wdiv(debt, collateral);

        // Ensure borrower tp is less than min price
        assertLt(Maths.wmul(debtToCollateral, COLLATERALIZATION_FACTOR), MIN_PRICE);

        // Lender can kick borrower with tp less than min price
        changePrank(_lender);
        _pool.lenderKick(2550, MAX_FENWICK_INDEX);
    }
}