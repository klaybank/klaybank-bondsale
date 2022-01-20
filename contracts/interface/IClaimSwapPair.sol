// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "../library/kip/IKIP7Detailed.sol";

interface IClaimSwapPair is IKIP7Detailed {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function token0() external view returns (address);
    function token1() external view returns (address);
}
