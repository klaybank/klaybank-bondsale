// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

interface IBondDepository {
    function principle() external view returns (address);
    function deposit(
        uint256 _amount,
        uint256 _maxPrice,
        address _depositor
    ) external returns (uint256);
}