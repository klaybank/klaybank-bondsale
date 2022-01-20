// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "./IKIP7.sol";

interface IKIP7Detailed is IKIP7 {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}
