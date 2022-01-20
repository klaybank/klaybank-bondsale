// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "./library/Ownable.sol";
import "./library/SafeMath.sol";
import "./library/kip/SafeKIP7.sol";
import "./interface/IBondTreasury.sol";
import "./library/upgradeable/VersionedInitializable.sol";

contract BondTreasury is Ownable, VersionedInitializable, IBondTreasury {
    using SafeMath for uint256;
    using SafeKIP7 for IKIP7;

    uint256 public constant REVISION = 1;

    address public DAO;
    address public KBT;
    address[] internal _reserveTokens;
    mapping(address => bool) public isReserveToken;
    mapping(address => uint256) public tokenPaidAmounts;
    address[] internal _reserveDepositors;
    mapping(address => bool) public isReserveDepositor;

    function __initialize(
        address DAO_,
        address KBT_
    ) external initializer {
        _setInitialOwner();
        require(KBT_ != address(0), "BondTreasury: 0 address");
        DAO = DAO_;
        require(DAO_ != address(0), "BondTreasury: 0 address");
        KBT = KBT_;
    }

    function getBalance() external view returns (uint256) {
        return IKIP7(KBT).balanceOf(address(this));
    }

    function getRevision() internal pure override returns (uint256) {
        return REVISION;
    }

    function reserveTokens() external view returns (address[] memory) {
        return _reserveTokens;
    }

    function reserveDepositors() external view returns (address[] memory) {
        return _reserveDepositors;
    }

    function deposit(uint256 _amount, address _token, uint256 _pay) external override {
        require(isReserveToken[ _token ], "BondTreasury: not registered");
        require(isReserveDepositor[ msg.sender ], "BondTreasury: not authorized");

        IKIP7(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // mint KBT needed and store amount of rewards for distribution
        IKIP7(KBT).transfer(msg.sender, _pay);

        tokenPaidAmounts[_token] = tokenPaidAmounts[_token].add(_pay);
        emit Deposit(_token, _amount, _pay);
    }

    function register(address _token, address _depositor) external onlyOwner {
        require(_token != address(0) && _depositor != address(0), "BondTreasury: 0 address");
        require(!isReserveDepositor[_depositor], "BondTreasury: already registered");
        _register(_token, _depositor);
    }

    function _register(address _token, address _depositor) internal {
        if (!isReserveToken[_token]) {
            _reserveTokens.push(_token);
            isReserveToken[_token] = true;
        }
        address[] memory reserveDepositors_ = _reserveDepositors;
        bool exist = false;
        for (uint256 i = 0; i < reserveDepositors_.length; i++) {
            if (reserveDepositors_[i] == _depositor) {
                exist = true;
            }
        }
        if (!exist) {
            _reserveDepositors.push(_depositor);
        }
        isReserveDepositor[_depositor] = true;
    }

    function unregisterDepositor(address _depositor) external onlyOwner {
        require(isReserveDepositor[_depositor], "BondTreasury: not registered");
        isReserveDepositor[_depositor] = false;
    }

    /* ======= AUXILLIARY ======= */

    /**
     *  @notice allow anyone to send lost tokens (excluding principle or KBT) to the DAO
     *  @return bool
     */
    function recoverLostToken(address _token) external returns (bool) {
        require(_token != KBT, "BondTreasury: cannot withdraw KBT");
        require(!isReserveToken[_token], "BondTreasury: cannot withdraw reserve tokens");
        IKIP7(_token).safeTransfer(DAO, IKIP7(_token).balanceOf(address(this)));
        return true;
    }
}