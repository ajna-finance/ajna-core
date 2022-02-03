// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20Pool} from "./ERC20Pool.sol";

contract ERC20PoolFactory {
    event PoolCreated(ERC20Pool pool);

    function deployPool(IERC20 underlying) external returns (ERC20Pool pool) {
        bytes32 salt = keccak256(abi.encode(underlying));

        pool = new ERC20Pool{salt: salt}(underlying);

        emit PoolCreated(pool);
    }

    function isPoolDeployed(ERC20Pool pool) external view returns (bool) {
        return address(pool).code.length > 0;
    }

    function calculatePoolAddress(IERC20 underlying) public view returns (address predictedAddress) {
        bytes32 salt = keccak256(abi.encode(underlying));
        bytes memory poolConstructorArgs = abi.encode(underlying);

        predictedAddress = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            address(this),
                            salt,
                            keccak256(abi.encodePacked(type(ERC20Pool).creationCode, poolConstructorArgs))
                        )
                    )
                )
            )
        );
    }
}
