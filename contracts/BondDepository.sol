// SPDX-License-Identifier: MIT

pragma solidity 0.7.5;

import "./library/kip/SafeKIP7.sol";
import "./library/SafeMath.sol";
import "./library/Ownable.sol";
import "./interface/IBondTreasury.sol";
import "./interface/IStakedToken.sol";
import "./interface/IOracle.sol";
import "./library/upgradeable/VersionedInitializable.sol";
import "./interface/IBondDepository.sol";

abstract contract BondDepository is Ownable, VersionedInitializable, IBondDepository {

    using SafeKIP7 for IKIP7;
    using SafeMath for uint;




    /* ======== EVENTS ======== */

    event BondCreated(address depositor, uint256 deposit, uint256 indexed payout, uint256 indexed expires, uint256 indexed priceInUSD);
    event BondRedeemed(address indexed recipient, uint256 payout, uint256 remaining);
    event BondPriceChanged(uint256 indexed priceInUSD, uint256 indexed debtRatio);
    event ControlVariableAdjustment(uint256 initialBCV, uint256 newBCV, uint256 adjustment, bool addition);




    /* ======== STATE VARIABLES ======== */

    address public DAO;
    address public KBT; // token given as payment for bond
    address public override principle; // token used to create bond
    address public treasury; // mints OHM when receives principle
    address public oracle;

    address public staking; // to auto-stake payout

    Terms public terms; // stores terms for new bonds
    Adjust public adjustment; // stores adjustment to BCV data

    mapping(address => Bond) public bondInfo; // stores bond information for depositors

    uint256 public totalDebt; // total value of outstanding bonds; used for pricing
    uint256 public lastDecay; // reference block for debt decay




    /* ======== STRUCTS ======== */

    // Info for creating new bonds
    struct Terms {
        uint256 controlVariable; // scaling variable for price in 10**2
        uint256 vestingTerm; // in blocks
        uint256 minimumPriceRate; // when calculate payout in 10**9
        uint256 maxPayout; // in ten thousandths of a %. i.e. 5000 = 0.5%
        uint256 fee; // as % of bond payout, in hundreths. (500 = 5% = 0.05 for every 1 paid)
        uint256 maxDebt; // 10**18 max debt amount
    }

    // Info for bond holder
    struct Bond {
        uint256 payout; // KBT remaining to be paid
        uint256 vesting; // Blocks left to vest
        uint256 lastBlock; // Last interaction
        uint256 pricePaid; // In USDT, for front end viewing
    }

    // Info for incremental adjustments to control variable
    struct Adjust {
        bool add; // addition or subtraction
        uint256 rate; // increment
        uint256 target; // BCV when adjustment finished
        uint256 buffer; // minimum length (in blocks) between adjustments
        uint256 lastBlock; // block when last adjustment made
    }




    /* ======== INITIALIZATION ======== */

    function __initialize(
        address _KBT,
        address _DAO,
        address _principle,
        address _staking,
        address _treasury,
        address _oracle
    ) external initializer {
        _setInitialOwner();
        require(_KBT != address(0));
        KBT = _KBT;
        require(_DAO != address(0));
        DAO = _DAO;
        require(_principle != address(0));
        principle = _principle;
        require(_staking != address(0));
        staking = _staking;
        require(_treasury != address(0));
        treasury = _treasury;
        require(_oracle != address(0));
        oracle = _oracle;
    }

    /**
     *  @notice initializes bond parameters
     *  @param _controlVariable uint256
     *  @param _vestingTerm uint256
     *  @param _minimumPriceRate uint256
     *  @param _maxPayout uint256
     *  @param _fee uint256
     *  @param _maxDebt uint256
     *  @param _initialDebt uint256
     */
    function initializeBondTerms(
        uint256 _controlVariable,
        uint256 _vestingTerm,
        uint256 _minimumPriceRate,
        uint256 _maxPayout,
        uint256 _fee,
        uint256 _maxDebt,
        uint256 _initialDebt
    ) external onlyOwner() {
        require(terms.controlVariable == 0, "BondDepository: bonds must be initialized from 0");
        require(_maxPayout <= 10000, "BondDepository: payout cannot be above 1 percent");
        require(_fee <= 10000, "BondDepository: DAO fee cannot exceed payout");
        require(_minimumPriceRate <= 10**9, "BondDepository: min discount rate exceed");
        terms = Terms ({
            controlVariable: _controlVariable,
            vestingTerm: _vestingTerm,
            minimumPriceRate: _minimumPriceRate,
            maxPayout: _maxPayout,
            fee: _fee,
            maxDebt: _maxDebt
        });
        totalDebt = _initialDebt;
        lastDecay = block.number;
    }




    /* ======== POLICY FUNCTIONS ======== */

    enum PARAMETER { VESTING, PAYOUT, FEE, DEBT, MIN }
    /**
     *  @notice set parameters for new bonds
     *  @param _parameter PARAMETER
     *  @param _input uint256
     */
    function setBondTerms(PARAMETER _parameter, uint256 _input) external onlyOwner() {
        if (_parameter == PARAMETER.VESTING) { // 0
            terms.vestingTerm = _input;
        } else if (_parameter == PARAMETER.PAYOUT) { // 1
            require(_input <= 10000, "BondDepository: payout cannot be above 1 percent");
            terms.maxPayout = _input;
        } else if (_parameter == PARAMETER.FEE) { // 2
            require(_input <= 10000, "BondDepository: DAO fee cannot exceed payout");
            terms.fee = _input;
        } else if (_parameter == PARAMETER.DEBT) { // 3
            terms.maxDebt = _input;
        } else if (_parameter == PARAMETER.MIN) { // 4
            require(_input <= 10**9, "BondDepository: min discount rate exceed");
            terms.minimumPriceRate = _input;
        }
    }

    /**
     *  @notice set control variable adjustment
     *  @param _addition bool
     *  @param _increment uint256
     *  @param _target uint256
     *  @param _buffer uint256
     */
    function setAdjustment (
        bool _addition,
        uint256 _increment,
        uint256 _target,
        uint256 _buffer
    ) external onlyOwner() {
        require(_increment <= terms.controlVariable.mul(25).div(1000), "BondDepository: increment too large");
        require(_addition ? (_target > terms.controlVariable) : (_target < terms.controlVariable), "BondDepository: wrong target value");

        adjustment = Adjust({
            add: _addition,
            rate: _increment,
            target: _target,
            buffer: _buffer,
            lastBlock: block.number
        });
    }

    /**
     *  @notice set contract for auto stake
     *  @param _staking address
     */
    function setStaking(address _staking) external onlyOwner() {
        require(_staking != address(0));
        staking = _staking;
    }




    /* ======== USER FUNCTIONS ======== */

    /**
     *  @notice deposit bond
     *  @param _amount uint256 in 10 ** 18 precision
     *  @param _maxPrice uint256
     *  @param _depositor address
     *  @return uint256
     */
    function deposit(
        uint256 _amount,
        uint256 _maxPrice,
        address _depositor
    ) external override returns (uint256) {
        require(_depositor != address(0), "BondDepository: Invalid address");

        decayDebt();
        require(totalDebt <= terms.maxDebt, "BondDepository: Max capacity reached");

        uint256 priceInUSD = bondPrice();

        require(_maxPrice >= priceInUSD, "BondDepository: Slippage limit: more than max price"); // slippage protection

        uint256 principleValue = assetPrice().mul(_amount).div(10**6); // returns principle value, in USD, 10**18
        uint256 payout = payoutFor(principleValue); // payout to bonder is computed, bond amount

        require(payout >= 10 ** 16, "BondDepository: Bond too small"); // must be > 0.01 KBT (underflow protection)
        require(payout <= maxPayout(), "BondDepository: Bond too large"); // size protection because there is no slippage

        // profits are calculated
        uint256 fee = payout.mul(terms.fee).div(10000);

        /**
            asset carries risk and is not minted against
            asset transferred to treasury and rewards minted as payout
         */
        IKIP7(principle).safeTransferFrom(msg.sender, address(this), _amount);
        IKIP7(principle).approve(address(treasury), _amount);
        IBondTreasury(treasury).deposit(_amount, principle, payout.add(fee));

        if (fee != 0) { // fee is transferred to dao
            IKIP7(KBT).safeTransfer(DAO, fee);
        }

        // total debt is increased
        totalDebt = totalDebt.add(payout);

        // depositor info is stored
        bondInfo[_depositor] = Bond({
            payout: bondInfo[_depositor].payout.add(payout),
            vesting: terms.vestingTerm,
            lastBlock: block.number,
            pricePaid: priceInUSD
        });

        // indexed events are emitted
        emit BondCreated(_depositor, _amount, payout, block.number.add(terms.vestingTerm), priceInUSD);
        emit BondPriceChanged(bondPrice(), debtRatio());

        adjust(); // control variable is adjusted
        return payout;
    }

    /**
     *  @notice redeem bond for user
     *  @param _recipient address
     *  @param _stake bool
     *  @return uint256
     */
    function redeem(address _recipient, bool _stake) external returns (uint256) {
        Bond memory info = bondInfo[_recipient];
        uint256 percentVested = percentVestedFor(_recipient); // (blocks since last interaction / vesting term remaining)

        if (percentVested >= 10000) { // if fully vested
            delete bondInfo[_recipient]; // delete user info
            emit BondRedeemed(_recipient, info.payout, 0); // emit bond data
            return stakeOrSend(_recipient, _stake, info.payout); // pay user everything due

        } else { // if unfinished
            // calculate payout vested
            uint256 payout = info.payout.mul(percentVested).div(10000);

            // store updated deposit info
            bondInfo[_recipient] = Bond({
                payout: info.payout.sub(payout),
                vesting: info.vesting.sub(block.number.sub(info.lastBlock)),
                lastBlock: block.number,
                pricePaid: info.pricePaid
            });

            emit BondRedeemed(_recipient, payout, bondInfo[_recipient].payout);
            return stakeOrSend(_recipient, _stake, payout);
        }
    }




    /* ======== INTERNAL HELPER FUNCTIONS ======== */

    /**
     *  @notice allow user to stake payout automatically
     *  @param _stake bool
     *  @param _amount uint256
     *  @return uint256
     */
    function stakeOrSend(address _recipient, bool _stake, uint256 _amount) internal returns (uint256) {
        if (!_stake) { // if user does not want to stake
            IKIP7(KBT).transfer(_recipient, _amount); // send payout
        } else { // if user wants to stake
            IKIP7(KBT).approve(staking, _amount);
            IStakedToken(staking).stake(_recipient, _amount);
        }
        return _amount;
    }

    /**
     *  @notice makes incremental adjustment to control variable
     */
    function adjust() internal {
        uint256 blockCanAdjust = adjustment.lastBlock.add(adjustment.buffer);
        if (adjustment.rate != 0 && block.number >= blockCanAdjust) {
            uint256 initial = terms.controlVariable;
            if (adjustment.add) {
                terms.controlVariable = terms.controlVariable.add(adjustment.rate);
                if (terms.controlVariable >= adjustment.target) {
                    adjustment.rate = 0;
                }
            } else {
                terms.controlVariable = terms.controlVariable.sub(adjustment.rate);
                if (terms.controlVariable <= adjustment.target) {
                    adjustment.rate = 0;
                }
            }
            adjustment.lastBlock = block.number;
            emit ControlVariableAdjustment(initial, terms.controlVariable, adjustment.rate, adjustment.add);
        }
    }

    /**
     *  @notice reduce total debt
     */
    function decayDebt() internal {
        totalDebt = totalDebt.sub(debtDecay());
        lastDecay = block.number;
    }




    /* ======== VIEW FUNCTIONS ======== */

    function NAME() external pure virtual returns(string memory);

    /**
     *  @notice determine maximum bond size
     *  @return uint256
     */
    function maxPayout() public view returns (uint256) {
        return IKIP7(KBT).totalSupply().mul(terms.maxPayout).div(1000000);
    }

    /**
     *  @notice calculate interest due for new bond
     *  @param _value uint256 10**18 precision
     *  @return uint256 10**18 precision
     */
    function payoutFor(uint256 _value) public view returns (uint256) {
        return _value.mul(1e18).div(bondPrice()).div(1e12);
    }

    /**
     *  @notice returns kbt price in usd
     *  @return uint256 in 10**6 precision
     */
    function kbtPrice() public view returns (uint256) {
        return IOracle(oracle).getAssetPriceInUsd(KBT);
    }

    /**
     *  @notice calculate current bond premium
     *  @return price_ uint256 in 10**6 precision in usd
     */
    function bondPrice() public view returns (uint256 price_) {
        uint256 _kbtPrice = kbtPrice();
        uint256 _priceRate = priceRate();
        price_ = _kbtPrice.mul(_priceRate).div(10**9);
    }

    /**
     *  @notice calculate bond price rate
     *  @return rate_ uint256 in 10**9 precision
     */
    function priceRate() public view returns (uint256 rate_) {
        rate_ = terms.controlVariable.mul(debtRatio()).div(100);
        if (rate_ < terms.minimumPriceRate) {
            rate_ = terms.minimumPriceRate;
        }
    }

    /**
     *  @notice get asset price from klaybank oracle
     *  @return uint256 in 10 ** 6 precision
     */
    function assetPrice() public view returns (uint256) {
        return IOracle(oracle).getAssetPriceInUsd(principle);
    }

    /**
     *  @notice calculate current ratio of debt to KBT supply
     *  @return debtRatio_ uint256 in 10 ** 9 precision
     */
    function debtRatio() public view returns (uint256 debtRatio_) {
        debtRatio_ = currentDebt().mul(1e9).mul(1e18).div(IKIP7(KBT).totalSupply()).div(1e18);
    }

    /**
     *  @notice calculate debt factoring in decay
     *  @return uint256 in 10 ** 18 precision
     */
    function currentDebt() public view returns (uint256) {
        return totalDebt.sub(debtDecay());
    }

    /**
     *  @notice amount to decay total debt by
     *  @return decay_ uint256
     */
    function debtDecay() public view returns (uint256 decay_) {
        uint256 blocksSinceLast = block.number.sub(lastDecay);
        decay_ = totalDebt.mul(blocksSinceLast).div(terms.vestingTerm);
        if (decay_ > totalDebt) {
            decay_ = totalDebt;
        }
    }


    /**
     *  @notice calculate how far into vesting a depositor is
     *  @param _depositor address
     *  @return percentVested_ uint256
     */
    function percentVestedFor(address _depositor) public view returns (uint256 percentVested_) {
        Bond memory bond = bondInfo[_depositor];
        uint256 blocksSinceLast = block.number.sub(bond.lastBlock);
        uint256 vesting = bond.vesting;

        if (vesting > 0) {
            percentVested_ = blocksSinceLast.mul(10000).div(vesting);
        } else {
            percentVested_ = 0;
        }
    }

    /**
     *  @notice calculate amount of KBT available for claim by depositor
     *  @param _depositor address
     *  @return pendingPayout_ uint256
     */
    function pendingPayoutFor(address _depositor) external view returns (uint256 pendingPayout_) {
        uint256 percentVested = percentVestedFor(_depositor);
        uint256 payout = bondInfo[_depositor].payout;

        if (percentVested >= 10000) {
            pendingPayout_ = payout;
        } else {
            pendingPayout_ = payout.mul(percentVested).div(10000);
        }
    }




    /* ======= AUXILLIARY ======= */

    /**
     *  @notice allow anyone to send lost tokens (excluding principle or KBT) to the DAO
     *  @return bool
     */
    function recoverLostToken(address _token) external returns (bool) {
        require(_token != KBT, "BondTreasury: cannot withdraw KBT");
        require(_token != principle, "BondTreasury: cannot withdraw principle");
        IKIP7(_token).safeTransfer(DAO, IKIP7(_token).balanceOf(address(this)));
        return true;
    }
}