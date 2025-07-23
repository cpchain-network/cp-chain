// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../../interfaces/ICpChainDepositManager.sol";
import "../../interfaces/IDelegationManager.sol";

abstract contract CpChainDepositManagerStorage is ICpChainDepositManager {
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    bytes32 public constant DEPOSIT_TYPEHASH =
        keccak256(
            "Deposit(address staker,address cpChainBase,uint256 amount,uint256 nonce,uint256 expiry)"
        );

    uint8 internal constant MAX_STAKER_STRATEGY_LIST_LENGTH = 32;

    bytes32 internal _DOMAIN_SEPARATOR;

    uint256 internal withdrawalDelayBlocks;

    IDelegationManager public delegation;

    ICpChainBase public cpChainBase;

    mapping(address => uint256) public nonces;

    mapping(address => uint256) public stakerCpChainBaseShares;

    mapping(bytes32 => bool) public withdrawalRootPending;

    mapping(address => uint256) internal numWithdrawalsQueued;

    function _initCpChainDepositManagerStorage(
        IDelegationManager _delegation,
        ICpChainBase _cpChainBase
    ) internal {
        delegation = _delegation;
        cpChainBase = _cpChainBase;
    }

    uint256[100] private __gap;
}
