// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/interfaces/IERC1271.sol';

import "@src/interfaces/rewards/IRewardsManager.sol";

contract ContractNFTSpender is IERC1271 {

    IRewardsManager rewardsManager;

    constructor(address rewardsManager_) {
        rewardsManager = IRewardsManager(rewardsManager_);
    }

    function transferAndStakeNFT(address NFTAddress_, address receiver_, uint256 tokenId_) external {
        IERC721 nft = IERC721(NFTAddress_);

        nft.transferFrom(address(this), receiver_, tokenId_);
    }

}
