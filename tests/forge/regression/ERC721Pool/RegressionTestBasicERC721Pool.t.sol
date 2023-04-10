// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.14;

import { BasicERC721PoolInvariants } from "../../invariants/ERC721Pool/BasicERC721PoolInvariants.t.sol";
import "@std/console.sol";

contract RegressionTestBasicERC721Pool is BasicERC721PoolInvariants { 

    function setUp() public override { 
        super.setUp();
    }

    function test_regression_out_of_gas() external {
        _basicERC721PoolHandler.drawDebt(6251, 2506);
        _basicERC721PoolHandler.drawDebt(5442742850703661819442539517113510923065138686636336073122798635, 3);

        invariant_total_interest_earned_I2();
    }

    function test_regression_evm_revert_1() external {
        _basicERC721PoolHandler.drawDebt(0, 29877144463);
        _basicERC721PoolHandler.pledgeCollateral(100624244233299028269006266668516084952761091228519326135843410608001865053305, 110349606679412691172957834289542550319383271247755660854362242977991410021907);
        _basicERC721PoolHandler.removeCollateral(42212314027849728920517595654376688, 82763479476530761653416180818770120221606073479896485216701663210067343854940, 2804);
        invariant_quoteTokenBalance_QT1();

        /* Logs for removeQuoteToken
         Deposits available --> 59754288926
         Pool Balance       --> 29877144463
         LUP                --> 99836282890
         HTP                --> 29905872487 */
        _basicERC721PoolHandler.removeQuoteToken(0, 115792089237316195423570985008687907853269984665640564039457584007913129639934, 1206432074572207884421188737151329072317831713860321643282);
    }

}