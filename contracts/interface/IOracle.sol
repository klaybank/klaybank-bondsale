// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

interface IOracle {
    function getAssetPriceInUsd(address asset) external view returns (uint256);
}