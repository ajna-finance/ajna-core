// SPDX-License-Identifier: MIT

pragma solidity 0.8.11;

library Maths {
    uint256 public constant WAD = 10**18;
    uint256 public constant ONE_WAD = 1 * WAD;

    uint256 public constant RAY = 10**27;
    uint256 public constant ONE_RAY = 1 * RAY;

    uint256 public constant RAD = 10**45;
    uint256 public constant ONE_RAD = 1 * RAD;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }

    function wmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, y) / WAD;
    }

    function wdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, WAD) / y;
    }

    function max(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x >= y ? x : y;
    }

    function min(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = x <= y ? x : y;
    }

    function wad(uint256 x) internal pure returns (uint256) {
        return x * WAD;
    }

    function ray(uint256 x) internal pure returns (uint256) {
        return x * RAY;
    }

    function rmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, y) / RAY;
    }

    function rdiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, RAY) / y;
    }

    function rad(uint256 x) internal pure returns (uint256) {
        return x * RAD;
    }

    function rdmul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, y) / RAD;
    }

    function rddiv(uint256 x, uint256 y) internal pure returns (uint256 z) {
        z = mul(x, RAD) / y;
    }

    function wadToRay(uint256 x) internal pure returns (uint256) {
        return x * 10**9;
    }

    function wadToRad(uint256 x) internal pure returns (uint256) {
        return x * RAY;
    }

    function rayToWad(uint256 x) internal pure returns (uint256) {
        return x / 10**9;
    }

    function radToWad(uint256 x) internal pure returns (uint256) {
        return x / 10**27;
    }
}
