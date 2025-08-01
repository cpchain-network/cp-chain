// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/ReentrancyGuardUpgradeable.sol";

import "@/access/interfaces/IPauserRegistry.sol";
import "@/access/Pausable.sol";

import "./SlashingManagerStorage.sol";


contract SlashingManager is Initializable, OwnableUpgradeable, ReentrancyGuardUpgradeable, SlashingManagerStorage {
    modifier onlySlasher() {
        require(
            msg.sender == slasherAddress,
            "SlashingManager.onlySlasher: only slasher can do this operation"
        );
        _;
    }

    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(
        address initialOwner,
        IDelegationManager _delegationAddress,
        address _slasherAddress,
        uint256 _minWithdrawalAmount,
        address _slashingRecipient
    ) public initializer {
        slasherAddress = _slasherAddress;
        delegationManager = _delegationAddress;
        MIN_WITHDRAWAL_AMOUNT = _minWithdrawalAmount;
        slashingRecipient = _slashingRecipient;
        _transferOwnership(initialOwner);
    }

    function jail(address operator) external onlySlasher {
        isOperatorJail[operator] = true;
        emit IsJail(operator, true);
    }

    function unJail(address operator)  external onlySlasher {
        isOperatorJail[operator] = false;
        emit IsJail(operator, false);
    }

    function freezeAndSlashingShares(address operator, uint256 slashShare) external onlySlasher returns (uint256) {
        slashingOperatorShares[operator] = slashShare;

        (address[] memory stakers, uint256[] memory shares) = delegationManager.getStakerSharesOfOperator(operator);

        require(stakers.length == shares.length, "SlashingManager.freezeOperatorStakingShares: stakers and shares length must equal");

        uint256 totalShares = 0;
        for (uint256 i = 0; i < shares.length; i++) {
            totalShares += shares[i];
        }

        require(totalShares > 0, "SlashingManager.freezeOperatorStakingShares: No shares to distribute slashShare");

        for (uint256 i = 0; i < stakers.length; i++) {
            if (shares[i] > 0) {
                uint256 stakerSlashedShare = slashShare * shares[i] / totalShares;

                slashingStakerShares[stakers[i]] += stakerSlashedShare;

                delegationManager.slashingStakingShares(operator, stakers[i], stakerSlashedShare);

                emit SlashedShareDistributed(operator, stakers[i], stakerSlashedShare);
            }
        }

        emit SlashingOperatorStakingShares(
            operator,
            slashShare
        );
        return slashShare;
    }

    function updateSlashingRecipient(address _slashingRecipient) external onlySlasher {
        slashingRecipient = _slashingRecipient;
    }

    function withdraw() external {
        require(
            address(this).balance >= MIN_WITHDRAWAL_AMOUNT,
            "SlashingManager: withdrawal amount must be greater than minimum withdrawal amount"
        );

        uint256 amountToSend = address(this).balance;

        totalProcessedSlashingAmount += amountToSend;

        emit Withdrawal(amountToSend, slashingRecipient, msg.sender);

        (bool success, ) = payable(slashingRecipient).call{value: amountToSend}("");

        require(success, "FeeVault: SlashingManager to send ETH to recipient");
    }
}
