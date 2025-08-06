// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "./utils/ExistingDeploymentParser.sol";

/**
 * @notice Script used for the first deployment of CpChainLayer core contracts to Cp Chain
 * forge script script/DeployerBasic.s.sol --rpc-url http://127.0.0.1:8545 --private-key $PRIVATE_KEY --broadcast -vvvv
 * forge script script/DeployerBasic.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast -vvvv
 */
contract DeployerBasic is ExistingDeploymentParser {
    function run() external virtual {
        _parseInitialDeploymentParams("script/configs/Deployment.config.json");

        // START RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.startBroadcast();

        emit log_named_address("Deployer Address", msg.sender);

        _deployFromScratch();

        // STOP RECORDING TRANSACTIONS FOR DEPLOYMENT
        vm.stopBroadcast();

        // Sanity Checks
//        _verifyContractPointers();
//        _verifyImplementations();
//        _verifyContractsInitialized();
//        _verifyInitializationParams();

        logAndOutputContractAddresses(
            "script/output/DeploymentBasic.config.json"
        );
    }

    /**
     * @notice Deploy CpChainLayer contracts from scratch for Cp Chain
     */
    function _deployFromScratch() internal {
        // Deploy ProxyAdmin, later set admins for all proxies to be executorMultisig
        cpChainLayerProxyAdmin = new ProxyAdmin(executorMultisig);

        // Set multisigs as pausers, executorMultisig as unpauser
        address[] memory pausers = new address[](3);
        pausers[0] = executorMultisig;
        pausers[1] = operationsMultisig;
        pausers[2] = pauserMultisig;
        address unpauser = executorMultisig;
        cpChainLayerPauserReg = new PauserRegistry(pausers, unpauser);

        emptyContract = new EmptyContract();

        // Deploy and upgrade chainBase
        TransparentUpgradeableProxy chainBaseBaseProxyInstance = new TransparentUpgradeableProxy(
                address(emptyContract),
                executorMultisig,
                ""
            );
        cpChainBase = CpChainBase(payable(address(chainBaseBaseProxyInstance)));
        chainBaseBaseProxyAdmin = ProxyAdmin(
            getProxyAdminAddress(address(chainBaseBaseProxyInstance))
        );

        TransparentUpgradeableProxy delegationManagerProxyInstance = new TransparentUpgradeableProxy(
                address(emptyContract),
                executorMultisig,
                ""
            );
        delegationManager = DelegationManager(
            payable(address(delegationManagerProxyInstance))
        );
        delegationManagerProxyAdmin = ProxyAdmin(
            getProxyAdminAddress(address(delegationManagerProxyInstance))
        );

        TransparentUpgradeableProxy cpChainDepositManagerProxyInstance = new TransparentUpgradeableProxy(
                address(emptyContract),
                executorMultisig,
                ""
            );
        cpChainDepositManager = CpChainDepositManager(
            payable(address(cpChainDepositManagerProxyInstance))
        );
        cpChainDepositManagerProxyAdmin = ProxyAdmin(
            getProxyAdminAddress(address(cpChainDepositManagerProxyInstance))
        );

        TransparentUpgradeableProxy rewardManagerProxyInstance = new TransparentUpgradeableProxy(
                address(emptyContract),
                executorMultisig,
                ""
            );
        rewardManager = RewardManager(
            payable(address(rewardManagerProxyInstance))
        );
        rewardManagerProxyAdmin = ProxyAdmin(
            getProxyAdminAddress(address(rewardManagerProxyInstance))
        );

        TransparentUpgradeableProxy slashingManagerProxyInstance = new TransparentUpgradeableProxy(
                address(emptyContract),
                executorMultisig,
                ""
            );
        slashingManager = SlashingManager(
            payable(address(slashingManagerProxyInstance))
        );
        slashingManagerProxyAdmin = ProxyAdmin(
            getProxyAdminAddress(address(slashingManagerProxyInstance))
        );

        delegationManagerImplementation = new DelegationManager();
        cpChainDepositManagerImplementation = new CpChainDepositManager();
        cpChainBaseImplementation = new CpChainBase();
        rewardManagerImplementation = new RewardManager();
        slashingManagerImplementation = new SlashingManager();

        // DelegationManager
        delegationManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(delegationManager))),
            address(delegationManagerImplementation),
            abi.encodeWithSelector(
                DelegationManager.initialize.selector,
                executorMultisig, // initialOwner
                cpChainLayerPauserReg,
                DELEGATION_MANAGER_INIT_PAUSED_STATUS,
                0,
                cpChainDepositManager,
                cpChainBase,
                slashingManager
            )
        );
        // CpChainDepositManager
        cpChainDepositManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(
                payable(address(cpChainDepositManager))
            ),
            address(cpChainDepositManagerImplementation),
            abi.encodeWithSelector(
                CpChainDepositManager.initialize.selector,
                msg.sender, //initialOwner, set to executorMultisig later after whitelisting strategies
                address(delegationManagerProxyInstance),
                address(chainBaseBaseProxyInstance)
            )
        );

        // CpChainBase
        chainBaseBaseProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(cpChainBase))),
            address(cpChainBaseImplementation),
            abi.encodeWithSelector(
                CpChainBase.initialize.selector,
                cpChainLayerPauserReg,
                CPCHAINBASE_MIN_DEPOSIT,
                CPCHAINBASE_MAX_DEPOSIT,
                cpChainDepositManager
            )
        );

//        // Deploy RewardManager proxy and implementation
//        rewardManagerProxyAdmin.upgradeAndCall(
//            ITransparentUpgradeableProxy(payable(address(rewardManager))),
//            address(rewardManagerImplementation),
//            abi.encodeWithSelector(
//                RewardManager.initialize.selector,
//                executorMultisig,
//                executorMultisig,
//                executorMultisig,
//                REWARD_MANAGER_STAKE_PERCENTAGE,
//                cpChainLayerPauserReg
//            )
//        );

        slashingManagerProxyAdmin.upgradeAndCall(
            ITransparentUpgradeableProxy(payable(address(slashingManager))),
            address(slashingManagerImplementation),
            abi.encodeWithSelector(
                SlashingManager.initialize.selector,
                executorMultisig,
                delegationManager,
                executorMultisig,
                1000,
                executorMultisig
            )
        );

        // Transfer ownership
        cpChainDepositManager.transferOwnership(executorMultisig);
        cpChainLayerProxyAdmin.transferOwnership(executorMultisig);
    }
}
