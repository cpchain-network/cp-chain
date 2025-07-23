// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin-upgrades/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin-upgrades/contracts/access/OwnableUpgradeable.sol";
import "@openzeppelin-upgrades/contracts/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../../interfaces/IRewardManager.sol";
import "../../interfaces/IDelegationManager.sol";
import "../../interfaces/ICpChainDepositManager.sol";

abstract contract RewardManagerStorage is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    IRewardManager
{
    IDelegationManager public delegationManager;

    ICpChainDepositManager public cpChainDepositManager;

    uint256 public stakePercent;

    address public rewardManager;

    address public payFeeManager;

    mapping(address => uint256) public chainBaseStakeRewards;
    mapping(address => uint256) public operatorRewards;

    function _initializeRewardManagerStorage(
        IDelegationManager _delegationManager,
        ICpChainDepositManager _cpChainDepositManager
    ) internal {
        delegationManager = _delegationManager;
        cpChainDepositManager = _cpChainDepositManager;
    }

    uint256[100] private __gap;
}
