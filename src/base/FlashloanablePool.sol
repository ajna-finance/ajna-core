// SPDX-License-Identifier: MIT

pragma solidity 0.8.14;

import '../base/Pool.sol';

abstract contract FlashloanablePool is Pool {
    function flashLoan(
        IERC3156FlashBorrower receiver_,
        address token_,
        uint256 amount_,
        bytes calldata data_
    ) external override nonReentrant returns (bool) {
        if (token_ != _getArgAddress(20)) revert FlashloanUnavailableForToken();

        _transferQuoteToken(address(receiver_), amount_);
        uint256 fee = _flashFee(amount_);
        
        if (receiver_.onFlashLoan(msg.sender, token_, amount_, fee, data_) != 
            keccak256("ERC3156FlashBorrower.onFlashLoan")) revert FlashloanCallbackFailed();

        _transferQuoteTokenFrom(address(receiver_), amount_ + fee);
        return true;
    }

    function _flashFee(uint256 amount_) internal view  returns (uint256) {
        return Maths.wmul(amount_, PoolUtils.feeRate(interestRate));
    }

    function flashFee(
        address token_,
        uint256 amount_
    ) external view override returns (uint256) {
        if (token_ != _getArgAddress(20)) revert FlashloanUnavailableForToken();
        return _flashFee(amount_);
    }

    function maxFlashLoan(
        address token_
    ) external view override returns (uint256 maxLoan_) {
        if (token_ == _getArgAddress(20)) maxLoan_ = _getPoolQuoteTokenBalance();
    }
}