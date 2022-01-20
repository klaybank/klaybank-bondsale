// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "./library/upgradeable/VersionedInitializable.sol";
import "./interface/IClaimSwapZap.sol";
import "./interface/IBondDepository.sol";
import "./interface/IClaimSwapPair.sol";
import "./library/ReentrancyGuard.sol";
import "./library/Ownable.sol";
import "./library/SafeMath.sol";

contract ClaimSwapBondZap is ReentrancyGuard, VersionedInitializable, Ownable {
    using SafeMath for uint256;
    uint256 public constant REVISION = 1;

    IClaimSwapZap public immutable ClaimSwapZap;

    constructor(address _claimSwapZap) {
        ClaimSwapZap = IClaimSwapZap(_claimSwapZap);
    }

    function __initialize() public initializer {
        _setInitialOwner();
    }

    function getRevision() internal pure override returns (uint256) {
        return REVISION;
    }

    function thisBalance() internal view returns (uint256) {
        address _this = address(this);
        return _this.balance;
    }

    function getBalance(address _token) public view returns (uint256) {
        if (_token == address(0)) {
            return thisBalance();
        } else {
            return IKIP7(_token).balanceOf(address(this));
        }
    }

    function zapToBond(
        address _depository,
        address _token,
        uint256 _amount,
        uint256 _minAmount,
        uint256 _maxPrice
    ) external payable nonReentrant {
        if (_token == address(0)) {
            require(_amount == msg.value, "ClaimSwapKlayKbtLpDepository: wrong msg.value");
            require(_amount > 0, "ClaimSwapKlayKbtLpDepository: 0 msg.value");
        } else {
            require(msg.value == 0, "ClaimSwapKlayKbtLpDepository: msg.value not allowed");
            IKIP7(_token).transferFrom(msg.sender, address(this), _amount);
            IKIP7(_token).approve(address(ClaimSwapZap), _amount);
        }
        IClaimSwapPair Pair = IClaimSwapPair(IBondDepository(_depository).principle());
        uint256 beforeFromTokenBalance = getBalance(_token);
        uint256 lpBought = ClaimSwapZap.zapIn{value: msg.value}(address(this), _token, Pair.token0(), Pair.token1(), _amount, _minAmount);
        Pair.approve(_depository, lpBought);
        IBondDepository(_depository).deposit(lpBought, _maxPrice, msg.sender);
        uint256 leftOver = getBalance(_token).sub(beforeFromTokenBalance.sub(_amount));
        _sendToken(_token, msg.sender, leftOver);
    }

    function estimatePoolTokens(
        address _fromTokenAddress,
        address _token0,
        address _token1,
        uint256 _amount
    ) external view returns (uint256) {
        return ClaimSwapZap.estimatePoolTokens(_fromTokenAddress, _token0, _token1, _amount);
    }

    function estimatePoolTokensInverse(
        address _fromTokenAddress,
        address _token0,
        address _token1,
        uint256 _lpAmount
    ) external view returns (uint256) {
        return ClaimSwapZap.estimatePoolTokensInverse(_fromTokenAddress, _token0, _token1, _lpAmount);
    }

    receive() external payable {}

    function _sendToken(address _token, address _to, uint256 _amount) internal {
        if (_amount == 0) {
            return;
        }
        if (_token == address(0)) {
            (bool success,) = _to.call{value: _amount}("");
            require(success, "ClaimSwapKlayKbtLpDepository: send klay failed");
        } else {
            IKIP7(_token).transfer(_to, _amount);
        }
    }

    function withdraw(address _token) external onlyOwner {
        uint256 amount = this.getBalance(_token);
        _sendToken(_token, msg.sender, amount);
    }
}
