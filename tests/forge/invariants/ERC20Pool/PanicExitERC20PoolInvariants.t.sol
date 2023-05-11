// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import "@std/console.sol";

import { LiquidationInvariants }     from '../base/LiquidationInvariants.t.sol';
import { BaseInvariants }            from '../base/BaseInvariants.sol';
import { BasicInvariants }           from '../base/BasicInvariants.t.sol';
import { PanicExitERC20PoolHandler } from './handlers/PanicExitERC20PoolHandler.sol';
import { BasicERC20PoolInvariants }  from './BasicERC20PoolInvariants.t.sol';

contract PanicExitERC20PoolInvariants is BasicERC20PoolInvariants, LiquidationInvariants {
    
    PanicExitERC20PoolHandler internal _panicExitERC20PoolHandler;

    address[] internal _lenders;
    address[] internal _borrowers;

    uint16 internal constant LENDERS     = 2_000;
    uint16 internal constant LOANS_COUNT = 8_000;

    function setUp() public override(BaseInvariants, BasicERC20PoolInvariants) virtual {

        super.setUp();

        excludeContract(address(_basicERC20PoolHandler));

        _panicExitERC20PoolHandler = new PanicExitERC20PoolHandler(
            address(_erc20pool),
            address(_ajna),
            address(_quote),
            address(_collateral),
            address(_poolInfo),
            address(this)
        );
        _panicExitERC20PoolHandler.setUp();

        _handler = address(_panicExitERC20PoolHandler);
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = _panicExitERC20PoolHandler.repayLoan.selector;
        selectors[1] = _panicExitERC20PoolHandler.kickAuction.selector;
        selectors[2] = _panicExitERC20PoolHandler.kickWithDeposit.selector;

        targetSelector(FuzzSelector({
            addr: _handler,
            selectors: selectors
        }));
    }

    function invariant_call_summary() public virtual override(BasicInvariants, LiquidationInvariants) useCurrentTimestamp {
        console.log("\nCall Summary\n");
        console.log("--Lender----------");
        console.log("BPanicExitPoolHandler.kickAuction   ",  _panicExitERC20PoolHandler.numberOfCalls("BPanicExitPoolHandler.kickAuction"));
        console.log("BPanicExitPoolHandler.kickWithDeposit   ",  _panicExitERC20PoolHandler.numberOfCalls("BPanicExitPoolHandler.kickWithDeposit"));
        console.log("UBBasicHandler.addQuoteToken        ",  _panicExitERC20PoolHandler.numberOfCalls("UBBasicHandler.addQuoteToken"));
        console.log("--Borrower--------");
        console.log("BPanicExitPoolHandler.repayLoan     ",  _panicExitERC20PoolHandler.numberOfCalls("BPanicExitPoolHandler.repayLoan"));
        console.log("UBBasicHandler.drawDebt             ",  _panicExitERC20PoolHandler.numberOfCalls("UBBasicHandler.drawDebt"));
        console.log("UBBasicHandler.repayDebt            ",  _panicExitERC20PoolHandler.numberOfCalls("UBBasicHandler.repayDebt"));
        console.log("UBBasicHandler.pledgeCollateral     ",  _panicExitERC20PoolHandler.numberOfCalls("UBBasicHandler.pledgeCollateral"));
        console.log("UBBasicHandler.pullCollateral       ",  _panicExitERC20PoolHandler.numberOfCalls("UBBasicHandler.pullCollateral"));
        console.log("------------------");
        ( , , uint256 totalLoans) = _pool.loansInfo();
        console.log("loans", totalLoans);
        console.log("auctions", _pool.totalAuctionsInPool());
        console.log("t0Debt", _pool.totalT0Debt());
        console.log("t0Debt in auctions", _pool.totalT0DebtInAuction());
    }

}