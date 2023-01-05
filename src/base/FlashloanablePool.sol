// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { Pool }                  from 'src/base/Pool.sol';
import { IERC3156FlashBorrower } from 'src/base/interfaces/IERC3156FlashBorrower.sol';

abstract contract FlashloanablePool is Pool {
    function flashLoan(
        IERC3156FlashBorrower receiver_,
        address token_,
        uint256 amount_,
        bytes calldata data_
    ) external virtual override nonReentrant returns (bool) {
        if (token_ == _getArgAddress(QUOTE_ADDRESS)) return _flashLoanQuoteToken(receiver_, token_, amount_, data_);
        revert FlashloanUnavailableForToken();
    }

    function _flashLoanQuoteToken(IERC3156FlashBorrower receiver_,
        address token_,
        uint256 amount_,
        bytes calldata data_
    ) internal returns (bool) {
        _transferQuoteToken(address(receiver_), amount_);
        
        if (receiver_.onFlashLoan(msg.sender, token_, amount_, 0, data_) != 
            keccak256("ERC3156FlashBorrower.onFlashLoan")) revert FlashloanCallbackFailed();

        _transferQuoteTokenFrom(address(receiver_), amount_);
        return true;
    }

    function flashFee(
        address token_,
        uint256
    ) external virtual view override returns (uint256) {
        if (token_ != _getArgAddress(QUOTE_ADDRESS)) revert FlashloanUnavailableForToken();
        return 0;
    }

    function maxFlashLoan(
        address token_
    ) external virtual view override returns (uint256 maxLoan_) {
        if (token_ == _getArgAddress(QUOTE_ADDRESS)) maxLoan_ = _getPoolQuoteTokenBalance();
    }
}