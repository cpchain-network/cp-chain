// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./ISignatureUtils.sol";
import "./ICpChainDepositManager.sol";

interface IDelegationManager is ISignatureUtils {
    struct OperatorDetails {
        address earningsReceiver;
        address delegationApprover;
        uint32 stakerOptOutWindowBlocks;
    }

    struct StakerDelegation {
        address staker;
        address operator;
        uint256 nonce;
        uint256 expiry;
    }

    struct DelegationApproval {
        address staker;
        address operator;
        bytes32 salt;
        uint256 expiry;
    }

    struct Withdrawal {
        address staker;
        address delegatedTo;
        address withdrawer;
        uint256 nonce;
        uint32 startBlock;
        uint256 shares;
    }

    struct QueuedWithdrawalParams {
        uint256 shares;
        address withdrawer;
    }

    event OperatorRegistered(
        address indexed operator,
        OperatorDetails operatorDetails
    );

    event OperatorDetailsModified(
        address indexed operator,
        OperatorDetails newOperatorDetails
    );

    event OperatorNodeUrlUpdated(address indexed operator, string metadataURI);

    event OperatorSharesIncreased(
        address indexed operator,
        address staker,
        uint256 shares
    );

    event OperatorSharesDecreased(
        address indexed operator,
        address staker,
        uint256 shares
    );

    event StakerDelegated(address indexed staker, address indexed operator);

    event StakerUndelegated(address indexed staker, address indexed operator);

    event StakerForceUndelegated(
        address indexed staker,
        address indexed operator
    );

    event WithdrawalQueued(bytes32 withdrawalRoot, Withdrawal withdrawal);

    event WithdrawalCompleted(address operator, address staker, uint256 shares);

    event WithdrawalMigrated(
        bytes32 oldWithdrawalRoot,
        bytes32 newWithdrawalRoot
    );

    event MinWithdrawalDelayBlocksSet(uint256 previousValue, uint256 newValue);

    event StrategyWithdrawalDelayBlocksSet(
        uint256 previousValue,
        uint256 newValue
    );

    function registerAsOperator(
        OperatorDetails calldata registeringOperatorDetails,
        string calldata metadataURI
    ) external;

    function modifyOperatorDetails(
        OperatorDetails calldata newOperatorDetails
    ) external;

    function updateOperatorNodeUrl(string calldata metadataURI) external;

    function delegateTo(
        address operator,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    function delegateToBySignature(
        address staker,
        address operator,
        SignatureWithExpiry memory stakerSignatureAndExpiry,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external;

    function undelegate(
        address staker
    ) external returns (bytes32 withdrawalRoot);

    function slashingStakingShares(address staker, uint256 shares) external;

    function queueWithdrawals(
        QueuedWithdrawalParams[] calldata queuedWithdrawalParams
    ) external returns (bytes32[] memory);

    function completeQueuedWithdrawal(Withdrawal calldata withdrawal) external;

    function completeQueuedWithdrawals(
        Withdrawal[] calldata withdrawals
    ) external;

    function increaseDelegatedShares(address staker, uint256 shares) external;

    function delegatedTo(address staker) external view returns (address);

    function operatorDetails(
        address operator
    ) external view returns (OperatorDetails memory);

    function earningsReceiver(address operator) external view returns (address);

    function delegationApprover(
        address operator
    ) external view returns (address);

    function stakerOptOutWindowBlocks(
        address operator
    ) external view returns (uint256);

    function getOperatorShares(
        address operator
    ) external view returns (uint256);

    function operatorShares(address operator) external view returns (uint256);

    function getStakerSharesOfOperator(
        address operator
    ) external view returns (address[] memory, uint256[] memory);

    function isDelegated(address staker) external view returns (bool);

    function isOperator(address operator) external view returns (bool);

    function stakerNonce(address staker) external view returns (uint256);

    function delegationApproverSaltIsSpent(
        address _delegationApprover,
        bytes32 salt
    ) external view returns (bool);

    function calculateCurrentStakerDelegationDigestHash(
        address staker,
        address operator,
        uint256 expiry
    ) external view returns (bytes32);

    function calculateStakerDelegationDigestHash(
        address staker,
        uint256 _stakerNonce,
        address operator,
        uint256 expiry
    ) external view returns (bytes32);

    function calculateDelegationApprovalDigestHash(
        address staker,
        address operator,
        address _delegationApprover,
        bytes32 approverSalt,
        uint256 expiry
    ) external view returns (bytes32);

    function DOMAIN_TYPEHASH() external view returns (bytes32);

    function STAKER_DELEGATION_TYPEHASH() external view returns (bytes32);

    function DELEGATION_APPROVAL_TYPEHASH() external view returns (bytes32);

    function domainSeparator() external view returns (bytes32);

    function cumulativeWithdrawalsQueued(
        address staker
    ) external view returns (uint256);

    function calculateWithdrawalRoot(
        Withdrawal memory withdrawal
    ) external pure returns (bytes32);
}
