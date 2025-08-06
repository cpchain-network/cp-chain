// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/ReentrancyGuardUpgradeable.sol";

import "@/libraries/EIP1271SignatureUtils.sol";
import "@/access/interfaces/IPauserRegistry.sol";
import "@/access/Pausable.sol";

import "./DelegationManagerStorage.sol";

contract DelegationManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    Pausable,
    DelegationManagerStorage
{
    uint8 internal constant PAUSED_NEW_DELEGATION = 0;

    uint8 internal constant PAUSED_ENTER_WITHDRAWAL_QUEUE = 1;

    uint8 internal constant PAUSED_EXIT_WITHDRAWAL_QUEUE = 2;

    uint256 internal ORIGINAL_CHAIN_ID;

    uint256 public constant MAX_STAKER_OPT_OUT_WINDOW_BLOCKS = (180 days) / 12;

    modifier onlyDepositManager() {
        require(
            msg.sender == address(cpChainDepositManager),
            "onlyDepositManager"
        );
        _;
    }

    modifier onlySlashingManager() {
        require(msg.sender == address(slashingManager), "onlySlashingManager");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    receive() external payable {}

    function initialize(
        address initialOwner,
        IPauserRegistry _pauserRegistry,
        uint256 initialPausedStatus,
        uint256 _withdrawalDelayBlock,
        ICpChainDepositManager _cpChainDepositManager,
        ICpChainBase _cpChainBase,
        ISlashingManager _slashingManager
    ) external initializer {
        _initializePauser(_pauserRegistry, initialPausedStatus);
        _DOMAIN_SEPARATOR = _calculateDomainSeparator();
        __Ownable_init(initialOwner);
        _setCpChainBaseWithdrawalDelayBlocks(_withdrawalDelayBlock);
        _initializeDelegationManagerStorage(
            _cpChainDepositManager,
            _cpChainBase,
            _slashingManager
        );

        ORIGINAL_CHAIN_ID = block.chainid;
    }

    /*******************************************************************************
                            EXTERNAL FUNCTIONS
    *******************************************************************************/
    function registerAsOperator(
        OperatorDetails calldata registeringOperatorDetails,
        string calldata nodeUrl
    ) external {
        require(
            _operatorDetails[msg.sender].earningsReceiver == address(0),
            "DelegationManager.registerAsOperator: operator has already registered"
        );
        _setOperatorDetails(msg.sender, registeringOperatorDetails);
        SignatureWithExpiry memory emptySignatureAndExpiry;
        _delegate(msg.sender, msg.sender, emptySignatureAndExpiry, bytes32(0));
        emit OperatorRegistered(msg.sender, registeringOperatorDetails);
        emit OperatorNodeUrlUpdated(msg.sender, nodeUrl);
    }

    function modifyOperatorDetails(
        OperatorDetails calldata newOperatorDetails
    ) external {
        require(
            isOperator(msg.sender),
            "DelegationManager.modifyOperatorDetails: caller must be an operator"
        );
        _setOperatorDetails(msg.sender, newOperatorDetails);
    }

    function updateOperatorNodeUrl(string calldata nodeUrl) external {
        require(
            isOperator(msg.sender),
            "DelegationManager.updateOperatorNodeUrl: caller must be an operator"
        );
        emit OperatorNodeUrlUpdated(msg.sender, nodeUrl);
    }

    function slashingStakingShares(
        address operator,
        address staker,
        uint256 shares
    ) external onlySlashingManager {

        if (operator != address(0)) {
            _decreaseOperatorShares(operator, staker, shares);
        }

        cpChainDepositManager.removeShares(staker, shares);

        cpChainDepositManager.withdrawSharesAsCp(
            address(slashingManager),
            shares
        );
    }

    function delegateTo(
        address operator,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external {
        _delegate(
            msg.sender,
            operator,
            approverSignatureAndExpiry,
            approverSalt
        );
    }

    function delegateToBySignature(
        address staker,
        address operator,
        SignatureWithExpiry memory stakerSignatureAndExpiry,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) external {
        require(
            stakerSignatureAndExpiry.expiry >= block.timestamp,
            "DelegationManager.delegateToBySignature: staker signature expired"
        );

        uint256 currentStakerNonce = stakerNonce[staker];
        bytes32 stakerDigestHash = calculateStakerDelegationDigestHash(
            staker,
            currentStakerNonce,
            operator,
            stakerSignatureAndExpiry.expiry
        );
        unchecked {
            stakerNonce[staker] = currentStakerNonce + 1;
        }

        EIP1271SignatureUtils.checkSignature_EIP1271(
            staker,
            stakerDigestHash,
            stakerSignatureAndExpiry.signature
        );

        _delegate(staker, operator, approverSignatureAndExpiry, approverSalt);
    }

    function undelegate(
        address staker
    ) external returns (bytes32 withdrawalRoot) {
        require(
            isDelegated(staker),
            "DelegationManager.undelegate: staker must be delegated to undelegate"
        );
        require(
            !isOperator(staker),
            "DelegationManager.undelegate: operators cannot be undelegated"
        );
        require(
            staker != address(0),
            "DelegationManager.undelegate: cannot undelegate zero address"
        );
        address operator = delegatedTo[staker];
        require(
            msg.sender == staker ||
                msg.sender == operator ||
                msg.sender == _operatorDetails[operator].delegationApprover,
            "DelegationManager.undelegate: caller cannot undelegate staker"
        );

        uint256 shares = cpChainDepositManager.getDeposits(staker);

        if (msg.sender != staker) {
            emit StakerForceUndelegated(staker, operator);
        }

        emit StakerUndelegated(staker, operator);

        delegatedTo[staker] = address(0);

        for (uint256 i = 0; i < stakerList.length; i++) {
            if (stakerList[i] == staker) {
                stakerList[i] = stakerList[stakerList.length - 1];
                stakerList.pop();
            }
        }

        withdrawalRoot = _removeSharesAndQueueWithdrawal({
            staker: staker,
            operator: operator,
            withdrawer: staker,
            shares: shares
        });

        return withdrawalRoot;
    }

    function queueWithdrawals(
        QueuedWithdrawalParams[] calldata queuedWithdrawalParams
    ) external whenNotPaused returns (bytes32[] memory) {
        bytes32[] memory withdrawalRoots = new bytes32[](
            queuedWithdrawalParams.length
        );

        address operator = delegatedTo[msg.sender];

        for (uint256 i = 0; i < queuedWithdrawalParams.length; i++) {
            require(
                queuedWithdrawalParams[i].withdrawer == msg.sender,
                "not authorized caller"
            );

            withdrawalRoots[i] = _removeSharesAndQueueWithdrawal({
                staker: queuedWithdrawalParams[i].withdrawer,
                operator: operator,
                withdrawer: queuedWithdrawalParams[i].withdrawer,
                shares: queuedWithdrawalParams[i].shares
            });
        }
        return withdrawalRoots;
    }

    function completeQueuedWithdrawal(
        Withdrawal calldata withdrawal
    ) external whenNotPaused nonReentrant {
        _completeQueuedWithdrawal(withdrawal);
    }

    function completeQueuedWithdrawals(
        Withdrawal[] calldata withdrawals
    ) external whenNotPaused nonReentrant {
        for (uint256 i = 0; i < withdrawals.length; ++i) {
            _completeQueuedWithdrawal(withdrawals[i]);
        }
    }

    function increaseDelegatedShares(
        address staker,
        uint256 shares
    ) external onlyDepositManager {
        if (isDelegated(staker)) {
            address operator = delegatedTo[staker];
            _increaseOperatorShares(operator, staker, shares);
        }
    }

    function decreaseDelegatedShares(
        address staker,
        uint256 shares
    ) external onlyDepositManager {
        if (isDelegated(staker)) {
            address operator = delegatedTo[staker];
            _decreaseOperatorShares({
                operator: operator,
                staker: staker,
                shares: shares
            });
        }
    }

    function setCpChainBaseWithdrawalDelayBlocks(
        uint256 withdrawalDelayBlock
    ) external onlyOwner {
        _setCpChainBaseWithdrawalDelayBlocks(withdrawalDelayBlock);
    }

    /*******************************************************************************
                            INTERNAL FUNCTIONS
    *******************************************************************************/
    function _setOperatorDetails(
        address operator,
        OperatorDetails calldata newOperatorDetails
    ) internal {
        require(
            newOperatorDetails.earningsReceiver != address(0),
            "DelegationManager._setOperatorDetails: cannot set `earningsReceiver` to zero address"
        );
        require(
            newOperatorDetails.stakerOptOutWindowBlocks <=
                MAX_STAKER_OPT_OUT_WINDOW_BLOCKS,
            "DelegationManager._setOperatorDetails: stakerOptOutWindowBlocks cannot be > MAX_STAKER_OPT_OUT_WINDOW_BLOCKS"
        );
        require(
            newOperatorDetails.stakerOptOutWindowBlocks >=
                _operatorDetails[operator].stakerOptOutWindowBlocks,
            "DelegationManager._setOperatorDetails: stakerOptOutWindowBlocks cannot be decreased"
        );
        _operatorDetails[operator] = newOperatorDetails;
        emit OperatorDetailsModified(msg.sender, newOperatorDetails);
    }

    function _delegate(
        address staker,
        address operator,
        SignatureWithExpiry memory approverSignatureAndExpiry,
        bytes32 approverSalt
    ) internal {
        require(
            !isDelegated(staker),
            "DelegationManager._delegate: staker is already actively delegated"
        );
        require(
            isOperator(operator),
            "DelegationManager._delegate: operator is not registered in CpChainLayer"
        );

        address _delegationApprover = _operatorDetails[operator]
            .delegationApprover;

        if (
            _delegationApprover != address(0) &&
            msg.sender != _delegationApprover &&
            msg.sender != operator
        ) {
            require(
                approverSignatureAndExpiry.expiry >= block.timestamp,
                "DelegationManager._delegate: approver signature expired"
            );

            require(
                !delegationApproverSaltIsSpent[_delegationApprover][
                    approverSalt
                ],
                "DelegationManager._delegate: approverSalt already spent"
            );
            delegationApproverSaltIsSpent[_delegationApprover][
                approverSalt
            ] = true;

            bytes32 approverDigestHash = calculateDelegationApprovalDigestHash(
                staker,
                operator,
                _delegationApprover,
                approverSalt,
                approverSignatureAndExpiry.expiry
            );

            EIP1271SignatureUtils.checkSignature_EIP1271(
                staker,
                approverDigestHash,
                approverSignatureAndExpiry.signature
            );
        }

        delegatedTo[staker] = operator;

        stakerList.push(staker);

        emit StakerDelegated(staker, operator);

        uint256 shares = cpChainDepositManager.getDeposits(staker);

        _increaseOperatorShares({
            operator: operator,
            staker: staker,
            shares: shares
        });
    }

    function _completeQueuedWithdrawal(
        Withdrawal calldata withdrawal
    ) internal {
        bytes32 withdrawalRoot = calculateWithdrawalRoot(withdrawal);

        require(
            pendingWithdrawals[withdrawalRoot],
            "DelegationManager._completeQueuedWithdrawal: action is not in queue"
        );

        require(
            msg.sender == withdrawal.withdrawer,
            "DelegationManager._completeQueuedWithdrawal: only withdrawer can complete action"
        );

        delete pendingWithdrawals[withdrawalRoot];

        address currentOperator = delegatedTo[msg.sender];

        require(
            withdrawal.startBlock + chainBaseWithdrawalDelayBlock <=
                block.number,
            "DelegationManager._completeQueuedWithdrawal: withdrawalDelayBlocks period has not yet passed for this chainBase"
        );

        _withdrawSharesAsCp(msg.sender, withdrawal.shares);

        emit WithdrawalCompleted(
            currentOperator,
            msg.sender,
            withdrawal.shares
        );
    }

    function _increaseOperatorShares(
        address operator,
        address staker,
        uint256 shares
    ) internal {
        operatorShares[operator] += shares;
        stakerDelegateSharesToOperator[operator][staker] += shares;
        emit OperatorSharesIncreased(operator, staker, shares);
    }

    function _decreaseOperatorShares(
        address operator,
        address staker,
        uint256 shares
    ) internal {
        operatorShares[operator] -= shares;
        stakerDelegateSharesToOperator[operator][staker] -= shares;
        emit OperatorSharesDecreased(operator, staker, shares);
    }

    function _removeSharesAndQueueWithdrawal(
        address staker,
        address operator,
        address withdrawer,
        uint256 shares
    ) internal returns (bytes32) {
        require(
            staker != address(0),
            "DelegationManager._removeSharesAndQueueWithdrawal: staker cannot be zero address"
        );

        if (operator != address(0)) {
            _decreaseOperatorShares(operator, staker, shares);
        }

        cpChainDepositManager.removeShares(staker, shares);

        uint256 nonce = cumulativeWithdrawalsQueued[staker];

        cumulativeWithdrawalsQueued[staker]++;

        Withdrawal memory withdrawal = Withdrawal({
            staker: staker,
            delegatedTo: operator,
            withdrawer: withdrawer,
            nonce: nonce,
            startBlock: uint32(block.number),
            shares: shares
        });

        bytes32 withdrawalRoot = calculateWithdrawalRoot(withdrawal);

        pendingWithdrawals[withdrawalRoot] = true;

        emit WithdrawalQueued(withdrawalRoot, withdrawal);

        return withdrawalRoot;
    }

    function _withdrawSharesAsCp(address withdrawer, uint256 shares) internal {
        cpChainDepositManager.withdrawSharesAsCp(withdrawer, shares);
    }

    function _setCpChainBaseWithdrawalDelayBlocks(
        uint256 _withdrawalDelayBlocks
    ) internal {
        uint256 prevStrategyWithdrawalDelayBlock = chainBaseWithdrawalDelayBlock;
        uint256 newStrategyWithdrawalDelayBlock = _withdrawalDelayBlocks;

        require(
            newStrategyWithdrawalDelayBlock <= MAX_WITHDRAWAL_DELAY_BLOCKS,
            "DelegationManager._setCpChainBaseWithdrawalDelayBlocks: _withdrawalDelayBlocks cannot be > MAX_WITHDRAWAL_DELAY_BLOCKS"
        );

        chainBaseWithdrawalDelayBlock = newStrategyWithdrawalDelayBlock;

        emit StrategyWithdrawalDelayBlocksSet(
            prevStrategyWithdrawalDelayBlock,
            newStrategyWithdrawalDelayBlock
        );
    }

    function getStakerSharesOfOperator(
        address operator
    ) external view returns (address[] memory, uint256[] memory) {
        uint256 stakerLen = stakerList.length;
        address[] memory stakers = new address[](stakerLen);
        uint256[] memory shares = new uint256[](stakerLen);

        for (uint256 i = 0; i < stakerLen; i++) {
            stakers[i] = stakerList[i];
            shares[i] = stakerDelegateSharesToOperator[operator][stakerList[i]];
        }
        return (stakers, shares);
    }

    /*******************************************************************************
                            VIEW FUNCTIONS
    *******************************************************************************/
    function domainSeparator() public view returns (bytes32) {
        return _calculateDomainSeparator();
    }

    function isDelegated(address staker) public view returns (bool) {
        return (delegatedTo[staker] != address(0));
    }

    function isOperator(address operator) public view returns (bool) {
        return (_operatorDetails[operator].earningsReceiver != address(0));
    }

    function operatorDetails(
        address operator
    ) external view returns (OperatorDetails memory) {
        return _operatorDetails[operator];
    }

    function earningsReceiver(
        address operator
    ) external view returns (address) {
        return _operatorDetails[operator].earningsReceiver;
    }

    function delegationApprover(
        address operator
    ) external view returns (address) {
        return _operatorDetails[operator].delegationApprover;
    }

    function stakerOptOutWindowBlocks(
        address operator
    ) external view returns (uint256) {
        return _operatorDetails[operator].stakerOptOutWindowBlocks;
    }

    function getOperatorShares(address operator) public view returns (uint256) {
        return operatorShares[operator];
    }

    function calculateWithdrawalRoot(
        Withdrawal memory withdrawal
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(withdrawal));
    }

    function calculateCurrentStakerDelegationDigestHash(
        address staker,
        address operator,
        uint256 expiry
    ) external view returns (bytes32) {
        uint256 currentStakerNonce = stakerNonce[staker];
        return
            calculateStakerDelegationDigestHash(
                staker,
                currentStakerNonce,
                operator,
                expiry
            );
    }

    function calculateStakerDelegationDigestHash(
        address staker,
        uint256 _stakerNonce,
        address operator,
        uint256 expiry
    ) public view returns (bytes32) {
        bytes32 stakerStructHash = keccak256(
            abi.encode(
                STAKER_DELEGATION_TYPEHASH,
                staker,
                operator,
                _stakerNonce,
                expiry
            )
        );

        bytes32 stakerDigestHash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator(), stakerStructHash)
        );
        return stakerDigestHash;
    }

    function calculateDelegationApprovalDigestHash(
        address staker,
        address operator,
        address _delegationApprover,
        bytes32 approverSalt,
        uint256 expiry
    ) public view returns (bytes32) {
        bytes32 approverStructHash = keccak256(
            abi.encode(
                DELEGATION_APPROVAL_TYPEHASH,
                staker,
                operator,
                _delegationApprover,
                approverSalt,
                expiry
            )
        );
        bytes32 approverDigestHash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator(), approverStructHash)
        );
        return approverDigestHash;
    }

    function _calculateDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes("CpChainLayer")),
                    block.chainid,
                    address(this)
                )
            );
    }
}
