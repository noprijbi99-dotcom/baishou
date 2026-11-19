// SPDX-License-Identifier: MIT
// BAISHOU - the FAILED REFUND path (the 168.000-share target is not reached
// within the 14-day sale window from startSale — v2).
// FINAL design: ALL paid mints refund 100% via PULL claims (each person claims
// themselves; 90-day claim window; leftovers unclaimed after 90 days
// are burned to the dead address - nobody profits from unclaimed refunds).
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract RefundFailTest is BaishouTest {
    function _fail() internal {
        vm.warp(vm.getBlockTimestamp() + 14 days + 1);
        assertTrue(mint.saleFailed(), "launch failed");
    }

    function test_FailRefund100PercentPull() public {
        _mintAs(alice, 10, address(0));
        uint256 paid = 10 * 0.00168 ether;
        _fail();
        assertEq(treasury.balance, 0, "treasury is NEVER paid");
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, before + paid, "refund 100% full");
        assertEq(mint.deposits(alice), 0, "deposit depleted after claim");
        // Second claim: nothing left.
        vm.prank(alice);
        vm.expectRevert(AgentMint.NothingOwed.selector);
        mint.claimRefund();
    }

    function test_FailRefundWindow90Days() public {
        _mintAs(alice, 10, address(0));
        _mintAs(bob, 10, address(0));
        // End of the window (inclusive): alice can still claim.
        vm.warp(mint.failureTime() + 90 days);
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, before + 10 * 0.00168 ether, "claim on day 90 succeeds");
        // One second past: bob is already too late.
        vm.warp(vm.getBlockTimestamp() + 1);
        vm.prank(bob);
        vm.expectRevert(AgentMint.RefundExpired.selector);
        mint.claimRefund();
    }

    function test_UnclaimedRefundBurnedToDead() public {
        _mintAs(alice, 10, address(0));
        _mintAs(bob, 10, address(0));
        uint256 escrow = 20 * 0.00168 ether;
        _fail();
        vm.warp(mint.failureTime() + 90 days + 1);
        address dead = mint.DEAD();
        uint256 deadBefore = dead.balance;
        vm.prank(stranger);
        mint.sweepUnclaimed();
        assertEq(dead.balance, deadBefore + escrow, "remaining escrow burned to DEAD");
        assertEq(wbnb.balanceOf(address(mint)), 0, "WBNB escrow empty");
        assertEq(treasury.balance, 0, "team receives nothing from sweep");
        assertEq(mint.pendingBnb(), 0, "pending BNB 0 after sweep");
    }

    function test_SweepTooEarlyReverts() public {
        _mintAs(alice, 10, address(0));
        _fail();
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotSweepable.selector);
        mint.sweepUnclaimed();
        vm.warp(mint.failureTime() + 90 days); // exactly at the boundary: still too early
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotSweepable.selector);
        mint.sweepUnclaimed();
    }

    function test_NoFailRefundAfterPoolOpens() public {
        _mintAs(alice, 10, address(0));
        _openPool(carol);
        vm.prank(alice);
        vm.expectRevert(AgentMint.NotFailed.selector);
        mint.claimRefund();
    }

    function test_ClaimRefundBeforeFailureReverts() public {
        _mintAs(alice, 10, address(0));
        vm.prank(alice);
        vm.expectRevert(AgentMint.NotFailed.selector);
        mint.claimRefund();
    }

    function test_RefundPullNeverPush() public {
        // PULL: alice's claim only pays alice; bob is unchanged.
        _mintAs(alice, 10, address(0));
        _mintAs(bob, 10, address(0));
        _fail();
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(bob.balance, bobBefore, "alice claim does not touch bob");
        assertGt(mint.deposits(bob), 0, "bob deposit still awaits its own claim");
    }

    function test_PauseNeverBlocksRefunds() public {
        _mintAs(alice, 10, address(0));
        _fail();
        vm.prank(admin);
        mint.setPaused(true);
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, before + 10 * 0.00168 ether, "pause does not block refund");
    }
}
