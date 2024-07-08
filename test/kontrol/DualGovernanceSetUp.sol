pragma solidity 0.8.23;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import "contracts/Configuration.sol";
import "contracts/DualGovernance.sol";
import "contracts/EmergencyProtectedTimelock.sol";
import "contracts/Escrow.sol";
import "contracts/model/StETHModel.sol";
import "contracts/model/WstETHAdapted.sol";
import "contracts/model/WithdrawalQueueModel.sol";

import "test/kontrol/StorageSetup.sol";

contract DualGovernanceSetUp is StorageSetup {
    using DualGovernanceState for DualGovernanceState.Store;

    Configuration config;
    DualGovernance dualGovernance;
    EmergencyProtectedTimelock timelock;
    StETHModel stEth;
    WstETHAdapted wstEth;
    WithdrawalQueueModel withdrawalQueue;
    IEscrow signallingEscrow;
    IEscrow rageQuitEscrow;

    function setUp() public {
        stEth = new StETHModel();
        wstEth = new WstETHAdapted(IStETH(stEth));
        withdrawalQueue = new WithdrawalQueueModel();

        // Placeholder addresses
        address adminExecutor = address(uint160(uint256(keccak256("adminExecutor"))));
        address emergencyGovernance = address(uint160(uint256(keccak256("emergencyGovernance"))));
        address adminProposer = address(uint160(uint256(keccak256("adminProposer"))));

        config = new Configuration(adminExecutor, emergencyGovernance, new address[](0));
        timelock = new EmergencyProtectedTimelock(address(config));
        Escrow escrowMasterCopy = new Escrow(address(stEth), address(wstEth), address(withdrawalQueue), address(config));
        dualGovernance =
            new DualGovernance(address(config), address(timelock), address(escrowMasterCopy), adminProposer);
        signallingEscrow = IEscrow(_loadAddress(address(dualGovernance), 5));
        rageQuitEscrow = IEscrow(Clones.clone(address(escrowMasterCopy)));

        // ?STORAGE
        // ?WORD: totalPooledEther
        // ?WORD0: totalShares
        // ?WORD1: shares[signallingEscrow]
        _stEthStorageSetup(stEth, signallingEscrow);

        // ?STORAGE0
        // ?WORD2: lastStateChangeTime
        // ?WORD3: lastSubStateActivationTime
        // ?WORD4: lastStateReactivationTime
        // ?WORD5: lastVetoSignallingTime
        // ?WORD6: rageQuitSequenceNumber
        // ?WORD7: currentState
        _dualGovernanceStorageSetup(dualGovernance, timelock, stEth, signallingEscrow, rageQuitEscrow);

        // ?STORAGE1
        // ?WORD8: totalSharesLocked
        // ?WORD9: totalClaimedEthAmount
        // ?WORD10: withdrawalRequestCount
        // ?WORD11: lastWithdrawalRequestSubmitted
        // ?WORD12: claimedWithdrawalRequests
        // ?WORD13: rageQuitExtensionDelayPeriodEnd
        // ?WORD14: rageQuitEthClaimTimelockStart
        _signallingEscrowStorageSetup(signallingEscrow, dualGovernance, stEth);

        // ?STORAGE2
        // ?WORD15: totalSharesLocked
        // ?WORD16: totalClaimedEthAmount
        // ?WORD17: withdrawalRequestCount
        // ?WORD18: lastWithdrawalRequestSubmitted
        // ?WORD19: claimedWithdrawalRequests
        // ?WORD20: rageQuitExtensionDelayPeriodEnd
        // ?WORD21: rageQuitEthClaimTimelockStart
        _rageQuitEscrowStorageSetup(rageQuitEscrow, dualGovernance, stEth);

        // ?STORAGE3
        kevm.symbolicStorage(address(timelock));

        kevm.symbolicStorage(address(withdrawalQueue));
    }
}
