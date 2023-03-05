// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/interfaces/IERC1271.sol';

import { PositionManager } from "src/PositionManager.sol";

contract ContractNFTSpender {

    PositionManager positionManager;

    constructor(address positionManager_) {
        positionManager = PositionManager(positionManager_);
    }

    function transferFromWithPermit(
        address receiver_,
        uint256 tokenId_,
        uint256 deadline_,
        uint8 v_,
        bytes32 r_,
        bytes32 s_
    ) external {
        positionManager.permit(address(this), tokenId_, deadline_, v_, r_, s_);
        positionManager.transferFrom(msg.sender, receiver_, tokenId_);
    }

}
