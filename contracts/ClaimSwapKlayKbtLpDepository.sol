// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "./BondDepository.sol";
import "./interface/IClaimSwapZap.sol";
import "./interface/IClaimSwapPair.sol";

contract ClaimSwapKlayKbtLpDepository is BondDepository {
    uint256 public constant REVISION = 1;

    function getRevision() internal pure override returns (uint256) {
        return REVISION;
    }

    function NAME() external pure override returns (string memory) {
        return "ClaimSwap KLAY-KBT LP Depository";
    }
}
