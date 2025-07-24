// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@/access/Pausable.sol";

import "./RewardManagerStorage.sol";
import "../../interfaces/ICpChainBase.sol";
import "../../interfaces/ICpChainDepositManager.sol";

contract RewardManager is RewardManagerStorage, Pausable {
    using SafeERC20 for IERC20;

    modifier onlyRewardManager() {
        require(
            msg.sender == address(rewardManager),
            "RewardManager.only reward manager can call this function"
        );
        _;
    }

    modifier onlyPayFeeManager() {
        require(
            msg.sender == address(payFeeManager),
            "RewardManager.only pay fee manager can call this function"
        );
        _;
    }

    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(
        address initialOwner,
        address _rewardManager,
        address _payFeeManager,
        uint256 _stakePercent,
        IPauserRegistry _pauserRegistry,
        IDelegationManager _delegationManager,
        ICpChainDepositManager _cpChainDepositManager
    ) external initializer {
        payFeeManager = _payFeeManager;
        rewardManager = _rewardManager;
        stakePercent = _stakePercent;
        _transferOwnership(initialOwner);
        _initializePauser(_pauserRegistry, UNPAUSE_ALL);
        _initializeRewardManagerStorage(
            _delegationManager,
            _cpChainDepositManager
        );
    }

    function payFee(
        address chainBase,
        address operator,
        uint256 baseFee
    ) external onlyPayFeeManager {
        uint256 totalShares = ICpChainBase(chainBase).totalShares();

        uint256 operatorShares = delegationManager.operatorShares(operator);

        require(
            totalShares > 0 && operatorShares > 0,
            "RewardManager payFee: one of totalShares and operatorShares is zero"
        );

        uint256 operatorTotalFee = (baseFee * operatorShares) / totalShares;


        uint256 stakeFee = (operatorTotalFee * stakePercent) / 100;

        _updateStakerReward(chainBase, stakeFee, totalShares);


        uint256 operatorFee = operatorTotalFee - stakeFee;

        operatorRewards[operator] += operatorFee;

        emit OperatorAndStakeReward(chainBase, operator, stakeFee, operatorFee);
    }

    function operatorClaimReward() external returns (bool) {
        uint256 claimAmount = operatorRewards[msg.sender];
        require(
            claimAmount > 0,
            "RewardManager operatorClaimReward: operator claim amount need more then zero"
        );
        require(
            address(this).balance >= claimAmount,
            "RewardManager operatorClaimReward: Reward Token balance insufficient"
        );
        operatorRewards[msg.sender] = 0;

        emit OperatorClaimReward(msg.sender, claimAmount);

        (bool success, ) = payable(msg.sender).call{value: claimAmount}("");

        return success;
    }

    function stakeHolderClaimReward(address chainBase) external returns (bool) {
        uint256 stakeHolderAmount = _stakeHolderAmount(msg.sender, chainBase);
        require(
            stakeHolderAmount > 0,
            "RewardManager operatorClaimReward: stake holder amount need more then zero"
        );
        require(
            address(this).balance >= stakeHolderAmount,
            "RewardManager operatorClaimReward: Reward Token balance insufficient"
        );

        emit StakeHolderClaimReward(msg.sender, chainBase, stakeHolderAmount);


        (bool success, ) = payable(msg.sender).call{value: stakeHolderAmount}(
            ""
        );


        return success;
    }

    function getStakeHolderAmount(
        address chainBase
    ) external view returns (uint256) {
        return _stakeHolderAmount(msg.sender, chainBase);
    }

    function _updateStakerReward(
        address chainBase,
        uint256 stakeFee,
        uint256 totalShares
    ) internal {
        uint256 length = ICpChainBase(chainBase).stakerListLength();

        for (uint256 i = 0; i < length; i++) {
            address staker = ICpChainBase(chainBase).stakerListFind(i);
            uint256 shares = cpChainDepositManager.getDeposits(
                ICpChainBase(chainBase).stakerListFind(i)
            );

            stakerRewards[chainBase][staker] +=
                (shares * stakeFee) /
                totalShares;
        }

    }

    function _stakeHolderAmount(
        address staker,
        address chainBase
    ) internal view returns (uint256) {
        return stakerRewards[chainBase][staker];
    }

    function updateStakePercent(
        uint256 _stakePercent
    ) external onlyRewardManager {
        stakePercent = _stakePercent;
    }
}
