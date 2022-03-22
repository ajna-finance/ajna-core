// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Pool} from "./ERC20Pool.sol";

contract ERC20PoolFactory {
    event PoolCreated(ERC20Pool pool);

    function deployPool(ERC20 collateral, ERC20 quote)
        external
        returns (ERC20Pool pool)
    {
        bytes32 salt = keccak256(abi.encode(collateral, quote));

        pool = new ERC20Pool{salt: salt}(collateral, quote);

        emit PoolCreated(pool);
    }

    function isPoolDeployed(ERC20Pool pool) external view returns (bool) {
        return address(pool).code.length > 0;
    }

    function calculatePoolAddress(ERC20 collateral, ERC20 quote)
        public
        view
        returns (address predictedAddress)
    {
        bytes memory poolConstructorArgs = abi.encode(collateral, quote);
        bytes32 salt = keccak256(poolConstructorArgs);

        predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(
                                abi.encodePacked(
                                    type(ERC20Pool).creationCode,
                                    poolConstructorArgs
                                )
                            )
                        )
                    )
                )
            )
        );
    }
}
