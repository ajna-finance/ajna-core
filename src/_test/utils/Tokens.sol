// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.11;

import {ERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract CollateralToken is ERC20 {
    constructor() ERC20("Collateral", "C") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract CollateralTokenWith6Decimals is CollateralToken {
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}

contract QuoteToken is ERC20 {
    constructor() ERC20("Quote", "Q") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}

contract QuoteTokenWith6Decimals is QuoteToken {
    function decimals() public view virtual override returns (uint8) {
        return 6;
    }
}
