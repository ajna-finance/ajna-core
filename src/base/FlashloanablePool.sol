// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.8.14;

import { Pool }                  from './Pool.sol';
import { IERC3156FlashBorrower } from '../interfaces/pool/IERC3156FlashBorrower.sol';

/**
 *  @title  Flashloanable Pool Contract
 *  @notice Pool contract with IERC3156 flash loans capabilities.
 *  @notice No fee is charged for taking flash loans from pool.
 *  @notice Flash loans can be taking in ERC20 quote and ERC20 collateral tokens.
 */
abstract contract FlashloanablePool is Pool {
    /**
     *  @notice Called by flashloan borrowers to borrow liquidity which must be repaid in the same transaction.
     *  @param  receiver_ Address of the contract which implements the appropriate interface to receive tokens.
     *  @param  token_    Address of the ERC20 token caller wants to borrow.
     *  @param  amount_   The amount of tokens to borrow.
     *  @param  data_     User-defined calldata passed to the receiver.
     *  @return True if successful.
     */
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

    /**
     *  @notice Returns 0, as no fee is charged for flashloans.
     */
    function flashFee(
        address token_,
        uint256
    ) external virtual view override returns (uint256) {
        if (token_ != _getArgAddress(QUOTE_ADDRESS)) revert FlashloanUnavailableForToken();
        return 0;
    }

    /**
     *  @notice Returns the amount of tokens available to be lent.
     *  @param  token_   Address of the ERC20 token to be lent.
     *  @return maxLoan_ The amount of `token_` that can be lent.
     */
     function maxFlashLoan(
        address token_
    ) external virtual view override returns (uint256 maxLoan_) {
        if (token_ == _getArgAddress(QUOTE_ADDRESS)) maxLoan_ = _getPoolQuoteTokenBalance();
    }
}