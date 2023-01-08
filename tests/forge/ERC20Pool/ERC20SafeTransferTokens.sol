// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import { ERC20HelperContract } from './ERC20DSTestPlus.sol';

import 'src/ERC20Pool.sol';
import 'src/ERC20PoolFactory.sol';

interface IUSDT {
    function transfer(address _to, uint _value) external;
    function transferFrom(address _from, address _to, uint _value) external;
    function approve(address _to, uint _value) external;
    function balanceOf(address account) external view returns (uint);
    function totalSupply() external returns (uint);
}

contract ERC20SafeTransferTokens is ERC20HelperContract {

    address internal _lender;
    address internal _borrower;
    IUSDT   internal usdt;
    // USDT is non-standard erc20, methods don't return a bool
    address internal USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    function setUp() external {
        _lender      = makeAddr("lender");
        _borrower    = makeAddr("borrower");
        usdt         = IUSDT(USDT);
    }

    function testNonStandardERC20QuoteTokenTransfers() external {
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(address(_collateral), address(usdt), 0.05 * 10**18));

        deal(address(usdt), _lender, 1_000 * 1e18);
        changePrank(_lender);

        usdt.approve(address(pool), 1_000 * 1e18);

        pool.addQuoteToken(1_000 * 1e18, 2549);

        changePrank(_borrower);

        deal(address(_collateral), _borrower, 1_000 * 1e18);
        _collateral.approve(address(pool), type(uint256).max);

        pool.drawDebt(_borrower, 10 * 1e18, 2549, 1_000 * 1e18);(_borrower, 1_000 * 1e18);
    }

    function testNonStandardERC20CollateralTokenTransfers() external {
        ERC20Pool pool = ERC20Pool(_poolFactory.deployPool(address(usdt), address(_quote), 0.05 * 10**18));

        deal(address(_quote), _lender, 1_000 * 1e18);
        changePrank(_lender);

        _quote.approve(address(pool), 1_000 * 1e18);

        pool.addQuoteToken(1_000 * 1e18, 2549);

        changePrank(_borrower);

        deal(address(usdt), _borrower, 1_000 * 1e18);
        usdt.approve(address(pool), 1_000 * 1e18);

        pool.drawDebt(_borrower, 10 * 1e18, 2549, 1_000 * 1e18);(_borrower, 1_000 * 1e18);
    }
}