// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC721Pool }        from "../../erc721/ERC721Pool.sol";
import { ERC721PoolFactory } from "../../erc721/ERC721PoolFactory.sol";

import { BucketMath } from "../../libraries/BucketMath.sol";
import { Maths }      from "../../libraries/Maths.sol";

import { ERC721DSTestPlus }                             from "./ERC721DSTestPlus.sol";
import { NFTCollateralToken, QuoteToken }            from "../utils/Tokens.sol";
import { UserWithNFTCollateral, UserWithQuoteTokenInNFTPool } from "../utils/Users.sol";

contract ERC721ScaledBorrowTest is ERC721DSTestPlus {

    function setup() external {

    }

    function testBorrow() external {

    }

    function testBorrowWithInterestAccumulation() external {

    }

    function testBorrowLimitReached() external {

    }

    function testBorrowBorrowerUnderCollateralized() external {

    }

    function testBorrowPoolUnderCollateralized() external {
        
    }

    function testRepay() external {

    }

    // TODO: add repay failure checks

}
