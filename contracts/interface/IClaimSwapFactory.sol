// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

interface IClaimSwapFactory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    function addLiquidityKLAY(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountKLAYMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountKLAY, uint256 liquidity);
}
