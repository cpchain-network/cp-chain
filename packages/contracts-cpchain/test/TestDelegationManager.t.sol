// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "@/core/pos/CpChainBase.sol";
import "@/core/pos/CpChainDepositManager.sol";
import "@/core/pos/DelegationManager.sol";

import "@/access/PauserRegistry.sol";
import "@/interfaces/IDelegationManager.sol";
import "@/interfaces/ISlashingManager.sol";
import "@/interfaces/ISignatureUtils.sol";

import "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract CpDelegationManagerTest is Test {
    CpChainBase public cpChainBase;
    PauserRegistry public pauserregistry;
    CpChainDepositManager public cpChainDepositManager;
    DelegationManager public delegationManager;
    IDelegationManager.QueuedWithdrawalParams[] public params;
    IDelegationManager.Withdrawal[] public withdraws;

    address public user1 = address(0x01);
    address public pauser1 = address(0x02);
    address public pauser2 = address(0x03);
    address[] public pausers;
    address public unpauser = address(0x04);

    address public owner = address(0x05);
    address public slashingManager = address(0x06);
    address public operator = address(0x07);
    address public operator1 = address(0x08);

    function setUp() public {
        pausers.push(pauser1);
        pausers.push(pauser2);
        pauserregistry = new PauserRegistry(pausers, unpauser);

        CpChainBase logic1 = new CpChainBase();
        TransparentUpgradeableProxy proxy1 = new TransparentUpgradeableProxy(
            address(logic1),
            owner,
            ""
        );

        CpChainDepositManager logic2 = new CpChainDepositManager();
        TransparentUpgradeableProxy proxy2 = new TransparentUpgradeableProxy(
            address(logic2),
            owner,
            ""
        );

        DelegationManager logic3 = new DelegationManager();
        TransparentUpgradeableProxy proxy3 = new TransparentUpgradeableProxy(
            address(logic3),
            owner,
            ""
        );

        cpChainBase = CpChainBase(payable(address(proxy1)));
        cpChainDepositManager = CpChainDepositManager(payable(address(proxy2)));
        delegationManager = DelegationManager(payable(address(proxy3)));

        cpChainBase.initialize(
            IPauserRegistry(address(pauserregistry)),
            1 ether,
            10 ether,
            ICpChainDepositManager(address(cpChainDepositManager))
        );
        cpChainDepositManager.initialize(
            owner,
            IDelegationManager(address(delegationManager)),
            cpChainBase
        );
        delegationManager.initialize(
            owner,
            IPauserRegistry(address(pauserregistry)),
            0,
            0,
            cpChainDepositManager,
            cpChainBase,
            ISlashingManager(address(slashingManager))
        );

        vm.deal(user1, 100 ether);
        vm.deal(operator, 100 ether);
        vm.deal(operator1, 100 ether);
    }

    function testOperatorCanRegisterAndEmitEvents() public {
        DelegationManager.OperatorDetails memory od1 = IDelegationManager
            .OperatorDetails({
                earningsReceiver: operator,
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 100
            });
        DelegationManager.OperatorDetails memory od2 = IDelegationManager
            .OperatorDetails({
                earningsReceiver: address(0),
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 100
            });
        DelegationManager.OperatorDetails memory od3 = IDelegationManager
            .OperatorDetails({
                earningsReceiver: operator1,
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 180 days
            });
        string memory nodeUrl = "http://127.0.0.1:1234";

        vm.expectEmit(true, true, true, true);
        emit IDelegationManager.OperatorRegistered(operator, od1);
        vm.expectEmit(true, true, true, true);
        emit IDelegationManager.OperatorNodeUrlUpdated(operator, nodeUrl);

        vm.prank(operator);
        delegationManager.registerAsOperator(od1, nodeUrl);

        vm.prank(operator);
        vm.expectRevert(
            "DelegationManager.registerAsOperator: operator has already registered"
        );
        delegationManager.registerAsOperator(od2, nodeUrl);

        assertEq(true, delegationManager.isDelegated(operator));
        assertEq(true, delegationManager.isOperator(operator));

        vm.prank(operator1);
        vm.expectRevert(
            "DelegationManager._setOperatorDetails: cannot set `earningsReceiver` to zero address"
        );
        delegationManager.registerAsOperator(od2, nodeUrl);

        vm.prank(operator1);
        vm.expectRevert(
            "DelegationManager._setOperatorDetails: stakerOptOutWindowBlocks cannot be > MAX_STAKER_OPT_OUT_WINDOW_BLOCKS"
        );
        delegationManager.registerAsOperator(od3, nodeUrl);

        vm.prank(operator1);
        cpChainDepositManager.depositIntoCpChain{value: 2 ether}(2 ether);
        vm.prank(operator1);
        delegationManager.registerAsOperator(od1, nodeUrl);

        assertEq(delegationManager.getOperatorShares(operator1), 2 ether);
        assertEq(
            delegationManager.stakerDelegateSharesToOperator(
                operator1,
                operator1
            ),
            2 ether
        );

        address[2] memory stakerList;
        stakerList = [
            delegationManager.stakerList(0),
            delegationManager.stakerList(1)
        ];

        assertEq(stakerList[0], operator);
        assertEq(stakerList[1], operator1);

        // 修改 details
        IDelegationManager.OperatorDetails
            memory newDetails = IDelegationManager.OperatorDetails({
                earningsReceiver: operator,
                delegationApprover: address(4),
                stakerOptOutWindowBlocks: 150
            });

        vm.prank(operator);
        delegationManager.modifyOperatorDetails(newDetails);

        // 校验
        IDelegationManager.OperatorDetails memory readBack = delegationManager
            .operatorDetails(operator);
        assertEq(readBack.delegationApprover, address(4));
        assertEq(readBack.stakerOptOutWindowBlocks, 150);

        // 更新 URL
        string memory newUrl = "https://new.node.url";

        vm.expectEmit(true, true, true, true);
        emit IDelegationManager.OperatorNodeUrlUpdated(operator, newUrl);

        vm.prank(operator);
        delegationManager.updateOperatorNodeUrl(newUrl);
    }

    function testStakerCanDelegateToOperator() public {
        DelegationManager.OperatorDetails memory od = IDelegationManager
            .OperatorDetails({
                earningsReceiver: operator,
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 100
            });
        ISignatureUtils.SignatureWithExpiry memory emptySignatureAndExpiry;
        vm.startPrank(operator);
        delegationManager.registerAsOperator(od, "node-url");
        vm.startPrank(operator1);
        delegationManager.registerAsOperator(od, "node-url");

        vm.startPrank(user1);
        cpChainDepositManager.depositIntoCpChain{value: 2 ether}(2 ether);

        vm.startPrank(user1);
        vm.expectRevert(
            "DelegationManager._delegate: operator is not registered in CpChainLayer"
        );
        delegationManager.delegateTo(
            user1,
            emptySignatureAndExpiry,
            bytes32(0)
        );

        vm.startPrank(user1);
        delegationManager.delegateTo(
            operator,
            emptySignatureAndExpiry,
            bytes32(0)
        );
        assertEq(delegationManager.isDelegated(user1), true);
        assertEq(delegationManager.stakerList(2), user1);
        assertEq(delegationManager.getOperatorShares(operator), 2 ether);
        assertEq(
            delegationManager.stakerDelegateSharesToOperator(operator, user1),
            2 ether
        );

        vm.startPrank(user1);
        vm.expectRevert(
            "DelegationManager._delegate: staker is already actively delegated"
        );
        delegationManager.delegateTo(
            operator1,
            emptySignatureAndExpiry,
            bytes32(0)
        );
    }

    function testStakerCanUndelegate() public {
        _registerAndDelegate();

        vm.prank(user1);
        delegationManager.undelegate(user1);

        assertEq(delegationManager.isDelegated(user1), false);
        assertEq(delegationManager.delegatedTo(user1), address(0));
        assertEq(cpChainDepositManager.getDeposits(user1), 0);
        assertEq(delegationManager.cumulativeWithdrawalsQueued(user1), 1);
    }

    function testOperatorForceUndelegatesStaker() public {
        _registerAndDelegate();

        vm.prank(operator);
        delegationManager.undelegate(user1);

        assertEq(delegationManager.isDelegated(user1), false);
    }

    function testStakerCanUndelegateFail() public {
        _registerAndDelegate();

        vm.prank(address(0xE1));
        vm.expectRevert(
            "DelegationManager.undelegate: staker must be delegated to undelegate"
        );
        delegationManager.undelegate(address(0xE1));

        vm.expectRevert(
            "DelegationManager.undelegate: operators cannot be undelegated"
        );
        delegationManager.undelegate(operator);

        vm.expectRevert(
            "DelegationManager.undelegate: caller cannot undelegate staker"
        );
        delegationManager.undelegate(user1);
    }

    function _registerAndDelegate() internal {
        DelegationManager.OperatorDetails memory od = IDelegationManager
            .OperatorDetails({
                earningsReceiver: operator,
                delegationApprover: address(0),
                stakerOptOutWindowBlocks: 100
            });
        ISignatureUtils.SignatureWithExpiry memory emptySignatureAndExpiry;

        vm.prank(operator);
        delegationManager.registerAsOperator(od, "node-url");
        vm.prank(operator1);
        delegationManager.registerAsOperator(od, "node-url");

        vm.prank(user1);
        cpChainDepositManager.depositIntoCpChain{value: 2 ether}(2 ether);

        vm.prank(user1);
        delegationManager.delegateTo(
            operator,
            emptySignatureAndExpiry,
            bytes32(0)
        );

        assertEq(
            delegationManager.stakerDelegateSharesToOperator(operator, user1),
            2 ether
        );
    }

    function testIncreaseAndDecreaseShares() public {
        _registerAndDelegate();

        vm.prank(user1);
        vm.expectRevert("onlyStrategyManager");
        delegationManager.increaseDelegatedShares(user1, 100 ether);

        vm.prank(address(cpChainDepositManager));
        delegationManager.increaseDelegatedShares(user1, 100 ether);
        assertEq(delegationManager.getOperatorShares(operator), 102 ether);
        assertEq(
            delegationManager.stakerDelegateSharesToOperator(operator, user1),
            102 ether
        );

        vm.prank(user1);
        vm.expectRevert("onlyStrategyManager");
        delegationManager.decreaseDelegatedShares(user1, 40 ether);

        vm.prank(address(cpChainDepositManager));
        delegationManager.decreaseDelegatedShares(user1, 40 ether);
        assertEq(
            delegationManager.stakerDelegateSharesToOperator(operator, user1),
            62 ether
        );
    }

    function testOperatorDetailsQuery() public {
        _registerAndDelegate();

        DelegationManager.OperatorDetails memory od = delegationManager
            .operatorDetails(operator);
        assertEq(od.earningsReceiver, operator);
    }

    function testQueueAndCompleteWithdrawals() public {
        _registerAndDelegate();

        // Queue
        params.push(IDelegationManager.QueuedWithdrawalParams(1 ether, user1));
        vm.prank(user1);
        delegationManager.queueWithdrawals(params);

        assertEq(cpChainDepositManager.getDeposits(user1), 1 ether);
        assertEq(
            delegationManager.stakerDelegateSharesToOperator(operator, user1),
            1 ether
        );
        assertEq(delegationManager.getOperatorShares(operator), 1 ether);
        assertEq(user1.balance, 98 ether);

        // Advance blocks
        vm.roll(block.number + 200);

        IDelegationManager.Withdrawal memory withdrawal = IDelegationManager
            .Withdrawal({
                staker: user1,
                delegatedTo: operator,
                withdrawer: user1,
                nonce: 0,
                startBlock: uint32(block.number - 200),
                shares: 1 ether
            });
        IDelegationManager.Withdrawal memory withdrawalFake = IDelegationManager
            .Withdrawal({
                staker: user1,
                delegatedTo: operator,
                withdrawer: user1,
                nonce: 100,
                startBlock: uint32(block.number - 200),
                shares: 1 ether
            });

        vm.prank(user1);
        vm.expectRevert(
            "DelegationManager._completeQueuedWithdrawal: action is not in queue"
        );
        delegationManager.completeQueuedWithdrawal(withdrawalFake);

        vm.prank(operator);
        vm.expectRevert(
            "DelegationManager._completeQueuedWithdrawal: only withdrawer can complete action"
        );
        delegationManager.completeQueuedWithdrawal(withdrawal);

        vm.roll(0);
        vm.prank(user1);
        vm.expectRevert(
            "DelegationManager._completeQueuedWithdrawal: withdrawalDelayBlocks period has not yet passed for this chainBase"
        );
        delegationManager.completeQueuedWithdrawal(withdrawal);

        vm.prank(user1);
        vm.roll(block.number + 200);
        delegationManager.completeQueuedWithdrawal(withdrawal);
        assertEq(user1.balance, 99 ether);
    }

    function testQueueAndCompleteMulWithdrawals() public {
        _registerAndDelegate();

        // Queue
        params.push(IDelegationManager.QueuedWithdrawalParams(1 ether, user1));
        vm.prank(user1);
        delegationManager.queueWithdrawals(params);

        vm.prank(operator);
        vm.expectRevert("not authorized caller");
        delegationManager.queueWithdrawals(params);

        vm.prank(user1);
        delegationManager.queueWithdrawals(params);

        // Advance blocks
        vm.roll(block.number + 200);
        vm.prank(user1);
        withdraws.push(
            IDelegationManager.Withdrawal({
                staker: user1,
                delegatedTo: operator,
                withdrawer: user1,
                nonce: 0,
                startBlock: uint32(block.number - 200),
                shares: 1 ether
            })
        );
        withdraws.push(
            IDelegationManager.Withdrawal({
                staker: user1,
                delegatedTo: operator,
                withdrawer: user1,
                nonce: 1,
                startBlock: uint32(block.number - 200),
                shares: 1 ether
            })
        );

        delegationManager.completeQueuedWithdrawals(withdraws);

        assertEq(user1.balance, 100 ether);
    }

    function testOwnerCanSetWithdrawalDelayBlocks() public {
        uint256 newBlocks = 123;

        vm.prank(owner);
        delegationManager.setCpChainBaseWithdrawalDelayBlocks(newBlocks);
        assertEq(delegationManager.chainBaseWithdrawalDelayBlock(), newBlocks);

        vm.expectRevert();
        vm.prank(user1);
        delegationManager.setCpChainBaseWithdrawalDelayBlocks(456);

        vm.expectRevert(
            "DelegationManager._setCpChainBaseWithdrawalDelayBlocks: _withdrawalDelayBlocks cannot be > MAX_WITHDRAWAL_DELAY_BLOCKS"
        );
        vm.prank(owner);
        delegationManager.setCpChainBaseWithdrawalDelayBlocks(300000);
    }

    function testSlashingStakingShares() public {
        _registerAndDelegate();

        // slashingManager 触发惩罚
        vm.prank(slashingManager);
        delegationManager.slashingStakingShares(user1, 1 ether);

        assertEq(cpChainDepositManager.getDeposits(user1), 1 ether);
        assertEq(slashingManager.balance, 1 ether);

        vm.prank(user1);
        vm.expectRevert("onlySlashingManager");
        delegationManager.slashingStakingShares(user1, 1 ether);
    }

    function testDomainSeparatorUnchangedOnSameChain() public view {
        bytes32 sep1 = delegationManager.domainSeparator();
        bytes32 sep2 = delegationManager.domainSeparator();
        assertEq(sep1, sep2);
    }

    function testIsDelegatedReturnsTrueAfterDelegation() public {
        _registerAndDelegate();
        assertTrue(delegationManager.isDelegated(user1));
    }

    function testIsOperatorTrueAfterRegister() public {
        _registerAndDelegate();
        assertTrue(delegationManager.isOperator(operator));
    }

    function testOperatorDetailsReturnsCorrectStruct() public {
        _registerAndDelegate();
        DelegationManager.OperatorDetails memory od = delegationManager
            .operatorDetails(operator);
        assertEq(od.earningsReceiver, operator);
        assertEq(od.stakerOptOutWindowBlocks, 100);
    }

    function testEarningsReceiver() public {
        _registerAndDelegate();
        assertEq(delegationManager.earningsReceiver(operator), operator);
    }

    function testDelegationApproverDefaultIsZero() public {
        _registerAndDelegate();
        assertEq(delegationManager.delegationApprover(operator), address(0));
    }

    function testStakerOptOutWindowBlocksIsSet() public {
        _registerAndDelegate();
        assertEq(delegationManager.stakerOptOutWindowBlocks(operator), 100);
    }

    function testOperatorSharesIncreaseViaDelegate() public {
        _registerAndDelegate();
        assertGt(delegationManager.getOperatorShares(operator), 0); // 你可以 mock cpChainDepositManager 返回值
    }

    function testCalculateWithdrawalRootMatches() public view {
        IDelegationManager.Withdrawal memory w = IDelegationManager.Withdrawal({
            staker: address(10),
            delegatedTo: address(20),
            withdrawer: address(10),
            nonce: 1,
            startBlock: uint32(block.number),
            shares: 100
        });
        bytes32 expected = keccak256(abi.encode(w));
        assertEq(delegationManager.calculateWithdrawalRoot(w), expected);
    }

    function testCalculateCurrentStakerDelegationDigestHash() public {
        _registerAndDelegate();
        bytes32 digest = delegationManager
            .calculateCurrentStakerDelegationDigestHash(
                user1,
                operator,
                block.timestamp + 100
            );
        assertTrue(digest != bytes32(0));
    }

    function testCalculateStakerDelegationDigestHash() public view {
        bytes32 digest = delegationManager.calculateStakerDelegationDigestHash(
            user1,
            0,
            operator,
            block.timestamp + 100
        );
        assertTrue(digest != bytes32(0));
    }

    function testCalculateDelegationApprovalDigestHash() public view {
        bytes32 digest = delegationManager
            .calculateDelegationApprovalDigestHash(
                user1,
                operator,
                address(0),
                keccak256("salt"),
                block.timestamp + 100
            );
        assertTrue(digest != bytes32(0));
    }

    function testGetStakerSharesOfOperatorReturnsCorrectMapping() public {
        _registerAndDelegate();

        assertEq(
            delegationManager.stakerDelegateSharesToOperator(operator, user1),
            2 ether
        );

        vm.prank(address(cpChainDepositManager));
        delegationManager.increaseDelegatedShares(user1, 1 ether);

        (address[] memory stakers, uint256[] memory shares) = delegationManager
            .getStakerSharesOfOperator(operator);

        assertEq(stakers[0], operator);
        assertEq(stakers[1], operator1);
        assertEq(stakers[2], user1);

        assertEq(shares[0], 0);
        assertEq(shares[1], 0);
        assertEq(
            delegationManager.stakerDelegateSharesToOperator(operator, user1),
            3 ether
        );
        assertEq(shares[2], 3 ether);
    }
}
