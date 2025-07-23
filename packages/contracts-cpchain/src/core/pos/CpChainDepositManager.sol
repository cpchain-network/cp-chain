// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/ReentrancyGuardUpgradeable.sol";

import "./CpChainDepositManagerStorage.sol";
import "../../libraries/EIP1271SignatureUtils.sol";

contract CpChainDepositManager is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    CpChainDepositManagerStorage
{
    uint8 internal constant PAUSED_DEPOSITS = 0;
    uint256 internal ORIGINAL_CHAIN_ID;

    modifier onlyDelegationManager() {
        require(msg.sender == address(delegation), "onlyDelegationManager");
        _;
    }

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address initialOwner,
        IDelegationManager _delegation,
        ICpChainBase _cpChainBase
    ) public initializer {
        _DOMAIN_SEPARATOR = _calculateDomainSeparator();
        _transferOwnership(initialOwner);
        _initCpChainDepositManagerStorage(_delegation, _cpChainBase);
    }

    receive() external payable {}

    function depositIntoCpChain(
        uint256 amount
    ) external payable nonReentrant returns (uint256 shares) {
        require(amount == msg.value, "deposit value not match amount");
        shares = _depositIntoCpChain(msg.sender, amount);
    }

    function depositIntoCpChainWithSignature(
        uint256 amount,
        address staker,
        uint256 expiry,
        bytes memory signature
    ) external payable nonReentrant returns (uint256 shares) {
        require(amount == msg.value, "deposit value not match amount");
        require(
            expiry >= block.timestamp,
            "CpChainDepositManager.depositIntoCpChainWithSignature: signature expired"
        );
        uint256 nonce = nonces[staker];

        bytes32 structHash = keccak256(
            abi.encode(DEPOSIT_TYPEHASH, staker, amount, nonce, expiry)
        );

        unchecked {
            nonces[staker] = nonce + 1;
        }

        bytes32 digestHash = keccak256(
            abi.encodePacked("\x19\x01", domainSeparator(), structHash)
        );

        EIP1271SignatureUtils.checkSignature_EIP1271(
            staker,
            digestHash,
            signature
        );

        shares = _depositIntoCpChain(staker, amount);
    }

    function removeShares(
        address staker,
        uint256 shareAmount
    ) external onlyDelegationManager {
        require(
            shareAmount != 0,
            "CpChainDepositManager.removeShares: shareAmount should not be zero!"
        );

        uint256 userShares = stakerCpChainBaseShares[staker];

        require(
            shareAmount <= userShares,
            "CpChainDepositManager._removeShares: shareAmount too high"
        );

        unchecked {
            userShares = userShares - shareAmount;
        }

        stakerCpChainBaseShares[staker] = userShares;

        if (userShares == 0) {
            delete stakerCpChainBaseShares[staker];
            cpChainBase.deleteStaker(staker);
        }
    }

    function addShares(
        address staker,
        uint256 shares
    ) external onlyDelegationManager {
        _addShares(staker, shares);
    }

    function withdrawSharesAsCp(
        address recipient,
        uint256 shares
    ) external onlyDelegationManager {
        cpChainBase.withdraw(recipient, shares);
    }

    function getDeposits(address staker) external view returns (uint256) {
        return stakerCpChainBaseShares[staker];
    }

    function domainSeparator() public view returns (bytes32) {
        if (block.chainid == ORIGINAL_CHAIN_ID) {
            return _DOMAIN_SEPARATOR;
        } else {
            return _calculateDomainSeparator();
        }
    }

    // ================= internal function =================
    function _depositIntoCpChain(
        address staker,
        uint256 amount
    ) internal returns (uint256 shares) {
        shares = cpChainBase.deposit{value: amount}(amount, staker);

        _addShares(staker, shares);

        delegation.increaseDelegatedShares(staker, shares);

        return shares;
    }

    function _addShares(address staker, uint256 shares) internal {
        require(
            staker != address(0),
            "CpChainDepositManager._addShares: staker cannot be zero address"
        );
        require(
            shares != 0,
            "CpChainDepositManager._addShares: shares should not be zero!"
        );
        stakerCpChainBaseShares[staker] += shares;
        emit Deposit(staker, cpChainBase, shares);
    }

    function _calculateDomainSeparator() internal view returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes("CpChain")),
                    block.chainid,
                    address(this)
                )
            );
    }
}
