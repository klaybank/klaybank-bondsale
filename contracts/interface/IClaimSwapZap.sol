// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.7.5;

interface IClaimSwapZap {
    function zapIn(
        address _recipient,
        address _fromTokenAddress,
        address _token0,
        address _token1,
        uint256 _amount,
        uint256 _minPoolTokens
    ) external payable returns (uint256);

    function estimatePoolTokens(
        address _fromTokenAddress,
        address _token0,
        address _token1,
        uint256 _amount
    ) external view returns (uint256);

    function estimatePoolTokensInverse(
        address _fromTokenAddress,
        address _token0,
        address _token1,
        uint256 _lpAmount
    ) external view returns (uint256);
}
