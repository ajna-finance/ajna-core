// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

interface IPool {
    function addQuoteToken(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external returns (uint256 lpTokens);

    function removeQuoteToken(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external;

    function addCollateral(uint256 _amount) external;

    function removeCollateral(uint256 _amount) external;

    function claimCollateral(
        address _recipient,
        uint256 _amount,
        uint256 _price
    ) external;

    function borrow(uint256 _amount, uint256 _stopPrice) external;

    function repay(uint256 _amount) external;

    function purchaseBid(uint256 _amount, uint256 _price) external;

    function getLPTokenBalance(address _owner, uint256 _price)
        external
        view
        returns (uint256 lpTokens);

    function getLPTokenExchangeValue(uint256 _lpTokens, uint256 _price)
        external
        view
        returns (uint256 _collateralTokens, uint256 _quoteTokens);

    function liquidate(address _borrower) external;
}