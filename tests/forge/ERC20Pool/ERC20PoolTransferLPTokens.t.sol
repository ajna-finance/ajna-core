// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/libraries/helpers/PoolHelper.sol';

contract ERC20PoolTransferLPTokensTest is ERC20HelperContract {

    address internal _lender;
    address internal _lender1;
    address internal _lender2;

    function setUp() external {
        _lender  = makeAddr("lender");
        _lender1 = makeAddr("lender1");
        _lender2 = makeAddr("lender2");

        _mintQuoteAndApproveTokens(_lender,  200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender1, 200_000 * 1e18);
        _mintQuoteAndApproveTokens(_lender2, 200_000 * 1e18);
    }

    /********************************/
    /*** Transfer LP Tokens Tests ***/
    /********************************/

    function testTransferLPTokensToZeroAddress() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is not set
        _assertTransferNoAllowanceRevert(
            {
                operator: _lender,
                from:     _lender1,
                to:       _lender2,
                indexes:  indexes
            }
        );

        // should fail if allowed owner is set to 0x
        changePrank(_lender1);
        _pool.approveLpOwnership(address(0), indexes[0], 1_000 * 1e18);

        _assertTransferNoAllowanceRevert(
            {
                operator: _lender,
                from:     _lender1,
                to:       _lender2,
                indexes:  indexes
            }
        );
    }

    function testTransferLPTokensToUnallowedAddress() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        // should fail if allowed owner is set to lender2 address but trying to transfer to lender address
        changePrank(_lender1);
        _pool.approveLpOwnership(_lender2, indexes[0], 1_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 1_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[2], 1_000 * 1e27);

        _assertTransferNoAllowanceRevert(
            {
                operator: _lender,
                from:     _lender1,
                to:       _lender2,
                indexes:  indexes
            }
        );
    }

    function testTransferLPTokensToInvalidIndex() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 9999;
        indexes[1] = 2550;
        indexes[2] = 2552;

        // should fail since 9999 is not a valid index
        changePrank(_lender1);
        _pool.approveLpOwnership(_lender2, indexes[0], 1_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 1_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[2], 1_000 * 1e27);

        _assertTransferInvalidIndexRevert(
            {
                operator: _lender,
                from:     _lender1,
                to:       _lender2,
                indexes:  indexes
            }
        );
    }

    function testTransferLPTokensGreaterThanBalance() external tearDown {
        uint256[] memory indexes = new uint256[](2);
        indexes[0] = 2550;
        indexes[1] = 2551;

        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 10_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 20_000 * 1e18,
                index:  indexes[1]
            }
        );

        // set allowed owner to lender2 address
        _pool.approveLpOwnership(_lender2, indexes[0], 10_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 30_000 * 1e27);

        _assertTransferNoAllowanceRevert(
            {
                operator: _lender2,
                from:     _lender1,
                to:       _lender2,
                indexes:  indexes
            }
        );
    }

    function testTransferLPTokensForAllIndexes() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        skip(1 hours);

        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 10_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 20_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 30_000 * 1e18,
                index:  indexes[2]
            }
        );

        // check lenders lp balance
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[0],
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[1],
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[2],
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );

        // set allowed owner to lender2 address
        _pool.approveLpOwnership(_lender2, indexes[0], 10_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 20_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[2], 30_000 * 1e27);

        // transfer LP tokens for all indexes
        _transferLpTokens(
            {
                operator:  _lender,
                from:      _lender1,
                to:        _lender2,
                indexes:   indexes,
                lpBalance: 60_000 * 1e27
            }
        );

        // check that old token ownership was removed - a new transfer should fail
        _assertTransferNoAllowanceRevert(
            {
                operator: _lender,
                from:     _lender1,
                to:       _lender2,
                indexes:  indexes
            }
        );

        // check lenders lp balance
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[0],
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[1],
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[2],
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
    }

    function testTransferLPTokensForTwoIndexes() external tearDown {
        uint256[] memory depositIndexes = new uint256[](3);
        depositIndexes[0] = 2550;
        depositIndexes[1] = 2551;
        depositIndexes[2] = 2552;

        uint256[] memory transferIndexes = new uint256[](2);
        transferIndexes[0] = 2550;
        transferIndexes[1] = 2552;

        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 10_000 * 1e18,
                index:  depositIndexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 20_000 * 1e18,
                index:  depositIndexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 30_000 * 1e18,
                index:  depositIndexes[2]
            }
        );

        // check lenders lp balance
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       depositIndexes[0],
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       depositIndexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       depositIndexes[1],
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       depositIndexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       depositIndexes[2],
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       depositIndexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );

        // set allowed owner to lender2 address
        _pool.approveLpOwnership(_lender2, transferIndexes[0], 10_000 * 1e27);
        _pool.approveLpOwnership(_lender2, transferIndexes[1], 30_000 * 1e27);

        // transfer LP tokens for 2 indexes
        _transferLpTokens(
            {
                operator:  _lender,
                from:      _lender1,
                to:        _lender2,
                indexes:   transferIndexes,
                lpBalance: 40_000 * 1e27
            }
        );

        // check that old token ownership was removed - transfer with same indexes should fail
        _assertTransferNoAllowanceRevert(
            {
                operator: _lender,
                from:     _lender1,
                to:       _lender2,
                indexes:  transferIndexes
            }
        );

        // check lenders lp balance
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       depositIndexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       depositIndexes[0],
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       depositIndexes[1],
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       depositIndexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       depositIndexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       depositIndexes[2],
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime
            }
        );
    }

    function testTransferLPTokensToLenderWithLPTokens() external tearDown {
        uint256[] memory indexes = new uint256[](3);
        indexes[0] = 2550;
        indexes[1] = 2551;
        indexes[2] = 2552;

        skip(1 hours);

        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 10_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 20_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender1,
                amount: 30_000 * 1e18,
                index:  indexes[2]
            }
        );

        skip(1 hours);

        _addInitialLiquidity(
            {
                from:   _lender2,
                amount: 5_000 * 1e18,
                index:  indexes[0]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender2,
                amount: 10_000 * 1e18,
                index:  indexes[1]
            }
        );
        _addInitialLiquidity(
            {
                from:   _lender2,
                amount: 15_000 * 1e18,
                index:  indexes[2]
            }
        );

        // check lenders lp balance
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[0],
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[0],
                lpBalance:   5_000 * 1e27,
                depositTime: _startTime + 2 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[1],
                lpBalance:   20_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[1],
                lpBalance:   10_000 * 1e27,
                depositTime: _startTime + 2 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[2],
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime + 1 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[2],
                lpBalance:   15_000 * 1e27,
                depositTime: _startTime + 2 hours
            }
        );

        // set allowed owner to lender2 address
        changePrank(_lender1);
        _pool.approveLpOwnership(_lender2, indexes[0], 10_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[1], 20_000 * 1e27);
        _pool.approveLpOwnership(_lender2, indexes[2], 30_000 * 1e27);

        // transfer LP tokens for all indexes
        _transferLpTokens(
            {
                operator:  _lender,
                from:      _lender1,
                to:        _lender2,
                indexes:   indexes,
                lpBalance: 60_000 * 1e27
            }
        );

        // check that old token ownership was removed - transfer with same indexes should fail
        _assertTransferNoAllowanceRevert(
            {
                operator: _lender,
                from:     _lender1,
                to:       _lender2,
                indexes:  indexes
            }
        );

        // check lenders lp balance
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[0],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[0],
                lpBalance:   15_000 * 1e27,
                depositTime: _startTime + 2 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[1],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[1],
                lpBalance:   30_000 * 1e27,
                depositTime: _startTime + 2 hours
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender1,
                index:       indexes[2],
                lpBalance:   0,
                depositTime: 0
            }
        );
        _assertLenderLpBalance(
            {
                lender:      _lender2,
                index:       indexes[2],
                lpBalance:   45_000 * 1e27,
                depositTime: _startTime + 2 hours
            }
        );
    }
}
