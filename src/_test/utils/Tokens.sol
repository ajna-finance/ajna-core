// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.14;

import { ERC20 }  from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC721 } from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract CollateralToken is ERC20 {

    constructor() ERC20("Collateral", "C") {}

    function mint(address to_, uint256 amount_) public {
        _mint(to_, amount_);
    }

}

contract QuoteToken is ERC20 {

    constructor() ERC20("Quote", "Q") {}

    function mint(address to_, uint256 amount_) public {
        _mint(to_, amount_);
    }

}

contract NFTCollateralToken is ERC721 {

    /// @dev The ID of the next token that will be minted. Skips 0
    uint176 private _nextId = 1;

    constructor() ERC721("NFTCollateral", "NFTC") {}

    function mint(address to_, uint256 amount_) public {
        for (uint256 i = 0; i < amount_; ++i) {
            _safeMint(to_, _nextId++);
        }
    }
}

contract TokenWithNDecimals is ERC20 {

    uint8 _decimals;

    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to_, uint256 amount_) public {
        _mint(to_, amount_);
    }

}

