pragma solidity 0.8.26;

import {Duration, Durations} from "contracts/types/Duration.sol";
import {Timestamp, Timestamps} from "contracts/types/Timestamp.sol";
import {AssetsAccounting} from "contracts/libraries/AssetsAccounting.sol";
import {EscrowState} from "contracts/libraries/EscrowState.sol";

import "test/kontrol/EscrowAccounting.t.sol";

contract EscrowOperationsTest is EscrowAccountingTest {
    function _tryLockStETH(Escrow escrow, uint256 amount) internal returns (bool) {
        try escrow.lockStETH(amount) {
            return true;
        } catch {
            return false;
        }
    }

    function _tryUnlockStETH(Escrow escrow) internal returns (bool) {
        try escrow.unlockStETH() {
            return true;
        } catch {
            return false;
        }
    }

    /**
     * Test that a staker cannot unlock funds from the escrow until SignallingEscrowMinLockTime has passed since the last time that user has locked tokens.
     */
    function testCannotUnlockBeforeMinLockTime() external {
        Escrow escrow = signallingEscrow;

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        this.stEthUserSetup(stEth, sender);
        this.escrowUserSetup(escrow, sender);

        AccountingRecord memory pre = this.saveAccountingRecord(sender, escrow);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);
        vm.assume(
            dualGovernance.getPersistedState() == State.RageQuit || dualGovernance.getEffectiveState() != State.RageQuit
        );

        Duration lockDuration = Duration.wrap(_getMinAssetsLockDuration(escrow));
        Timestamp lockPeriod = addTo(lockDuration, pre.userLastLockedTime);

        vm.assume(Timestamps.now() < lockPeriod);

        vm.prank(sender);
        vm.expectRevert(abi.encodeWithSelector(AssetsAccounting.MinAssetsLockDurationNotPassed.selector, lockPeriod));
        escrow.unlockStETH();
    }

    /**
     * Test that funds can neither be locked nor unlocked if the escrow is in the RageQuitEscrow state.
     */
    function testCannotLockUnlockInRageQuitEscrowState(uint256 amount) external {
        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        this.stEthUserSetup(stEth, sender);
        this.escrowUserSetup(signallingEscrow, sender);

        vm.assume(dualGovernance.getPersistedState() != State.RageQuit);
        vm.assume(dualGovernance.getEffectiveState() == State.RageQuit);

        vm.startPrank(sender);
        bool lockSuccess = _tryLockStETH(signallingEscrow, amount);
        bool unlockSuccess = _tryUnlockStETH(signallingEscrow);
        assert(!lockSuccess && !unlockSuccess);
        vm.stopPrank;
    }

    /**
     * Test that a user cannot withdraw funds from the escrow until the RageQuitEthClaimTimelock has elapsed after the RageQuitExtensionDelay period.
     */
    function testCannotWithdrawBeforeEthClaimTimelockElapsed() external {
        Escrow escrow = rageQuitEscrow;

        // Placeholder address to avoid complications with keccak of symbolic addresses
        address sender = address(uint160(uint256(keccak256("sender"))));
        kevm.symbolicStorage(sender);

        this.stEthUserSetup(stEth, sender);
        this.escrowUserSetup(escrow, sender);
        vm.assume(stEth.balanceOf(sender) < ethUpperBound);

        AccountingRecord memory pre = this.saveAccountingRecord(sender, escrow);
        vm.assume(pre.userSharesLocked > 0);
        vm.assume(pre.userSharesLocked <= pre.totalSharesLocked);
        uint256 userEth = stEth.getPooledEthByShares(pre.userSharesLocked);
        vm.assume(userEth <= pre.totalEth);
        vm.assume(userEth <= address(escrow).balance);

        this.escrowInvariants(Mode.Assume, escrow);
        this.escrowUserInvariants(Mode.Assume, escrow, sender);

        vm.assume(escrow.isRageQuitFinalized());

        uint256 rageQuitExtensionPeriodStartedAt = _getRageQuitExtensionPeriodStartedAt(escrow);
        uint256 rageQuitExtensionPeriodDuration = _getRageQuitExtensionPeriodDuration(escrow);
        uint256 rageQuitEthWithdrawalsDelay = _getRageQuitEthWithdrawalsDelay(escrow);
        uint256 ethWithdrawalsDelayEnd =
            rageQuitExtensionPeriodStartedAt + rageQuitExtensionPeriodDuration + rageQuitEthWithdrawalsDelay;

        // Duration overflow prevention requirement: EscrowState.sol:L153-154
        vm.assume(ethWithdrawalsDelayEnd < 2 ** 32);
        // Ensuring transfer can happen in the successful case
        vm.assume(sender.balance >= (pre.userSharesLocked * (2 ** 96)) / pre.totalSharesLocked);

        if (block.timestamp <= ethWithdrawalsDelayEnd) {
            vm.prank(sender);
            vm.expectRevert(EscrowState.EthWithdrawalsDelayNotPassed.selector);
            escrow.withdrawETH();
        } else {
            vm.prank(sender);
            escrow.withdrawETH();

            this.escrowInvariants(Mode.Assert, escrow);
            this.escrowUserInvariants(Mode.Assert, escrow, sender);

            AccountingRecord memory post = this.saveAccountingRecord(sender, escrow);
            assert(post.userSharesLocked == 0);
        }
    }
}
