// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.14;

import './DSTestPlus.sol';

import 'src/libraries/Auctions.sol';

contract QueueInstance is DSTestPlus {
    using Auctions for Auctions.Data;

    Auctions.Data private auctions;

    function kick(address borrower_) external returns (uint256, uint256) {
        return auctions.kick(
            borrower_,
            1,
            1,
            1,
            1
        );
    }

    function remove(address borrower_) external {
        auctions._removeAuction(borrower_);
    }

    function getHead() external view returns (address) {
        return auctions.head;
    }

    function isActive(address borrower_) external view returns (bool kicked_) {
        kicked_ = auctions.liquidations[borrower_].kickTime != 0;
    }

    function get(
        address borrower_
    )
        external
        view
        returns (
            address,
            uint256,
            uint256,
            uint256,
            uint256,
            address,
            address
        )
    {
        Auctions.Liquidation memory liquidation = auctions.liquidations[borrower_];
        return (
            liquidation.kicker,
            liquidation.bondFactor,
            liquidation.kickTime,
            liquidation.kickMomp,
            liquidation.neutralPrice,
            liquidation.prev,
            liquidation.next
        );
    }
}

