// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20PerpPool} from "./ERC20PerpPool.sol";

contract ERC20PoolFactory {
    event PoolCreated(ERC20PerpPool pool);

    function deployPool(IERC20 collateral, IERC20 quote) external returns (ERC20PerpPool pool) {
        bytes32 salt = keccak256(abi.encode(collateral, quote));

        pool = new ERC20PerpPool{salt: salt}(collateral, quote);

        emit PoolCreated(pool);
    }

    function isPoolDeployed(ERC20PerpPool pool) external view returns (bool) {
        return address(pool).code.length > 0;
    }

    function calculatePoolAddress(IERC20 collateral, IERC20 quote) public view returns (address predictedAddress) {
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
                            keccak256(abi.encodePacked(type(ERC20PerpPool).creationCode, poolConstructorArgs))
                        )
                    )
                )
            )
        );
    }
}
