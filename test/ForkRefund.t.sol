// SPDX-License-Identifier: MIT
// BAISHOU - FORK TEST of the 80% EXIT + 100% FAILED REFUND paths (combined
// multi-user scenario, exact numbers). Unlike RefundExit/RefundFail.t.sol:
// here partial exits, full exits, and minters who do not exit are mixed
// in ONE scenario, then the launch is failed and EVERY refund claim
// is verified = deposits + forfeitOf to the last wei, including proof
// of escrow solvency mid-way (contract WBNB balance == total
// refund obligations) and a final contract balance == 0.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract ForkRefundTest is BaishouTest {
    function _totalObligations() internal view returns (uint256) {
        return mint.deposits(alice) + mint.deposits(bob) + mint.deposits(carol)
            + mint.forfeitOf(alice) + mint.forfeitOf(bob) + mint.forfeitOf(carol);
    }

    function test_ExitThenFailRefundDepositsPlusForfeit() public {
        // --- Phase 1: three minters enter (bob uses referrer alice) ---
        _mintAs(alice, 100, address(0)); // 0,168 BNB
        _mintAs(bob, 50, alice); // 0,084 BNB, 5% accrues to alice
        _mintAs(carol, 20, address(0)); // 0,0336 BNB
        assertEq(mint.referralAccrued(alice), 0.0042 ether, "bob referral 5% accrues to alice");

        // --- Phase 2: exit — carol exits FULLY, alice exits PARTIALLY ---
        uint256 carolBefore = carol.balance;
        vm.prank(carol);
        mint.exit(20);
        assertEq(carol.balance, carolBefore + 0.02688 ether, "exit carol: returns exactly 80%");
        assertEq(mint.forfeitOf(carol), 0.00672 ether, "carol forfeit 20% recorded");

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        mint.exit(40);
        assertEq(alice.balance, aliceBefore + 0.05376 ether, "exit alice 40: returns exactly 80%");
        assertEq(mint.forfeitOf(alice), 0.01344 ether, "alice forfeit 20% recorded");
        assertEq(mint.deposits(alice), 0.1008 ether, "alice deposit remaining 60 shares");
        assertEq(mint.deposits(bob), 0.084 ether, "bob deposit intact");

        // --- Mid-way solvency proof: contract WBNB balance ==
        //     total refund obligations (deposits + forfeit of all users). ---
        assertEq(_totalObligations(), 0.20496 ether, "total obligations 0,20496 BNB");
        assertEq(
            wbnb.balanceOf(address(mint)),
            _totalObligations(),
            "escrow covers 100% of refund obligations"
        );
        assertEq(treasury.balance, 0, "treasury has received nothing yet");

        // --- Phase 3: deadline passes without the target -> launch FAILS ---
        vm.warp(mint.failureTime() + 1);
        assertTrue(mint.saleFailed(), "launch failed");

        // Referral still CANNOT be claimed: the pool never opened.
        vm.prank(alice);
        vm.expectRevert(AgentMint.NotOpen.selector);
        mint.claimReferral();

        // --- Phase 4: every user claims deposits + forfeitOf, exactly ---
        uint256 a0 = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, a0 + 0.11424 ether, "refund alice = 0,1008 + 0,01344");

        uint256 b0 = bob.balance;
        vm.prank(bob);
        mint.claimRefund();
        assertEq(bob.balance, b0 + 0.084 ether, "refund bob = full deposit (never exited)");

        uint256 c0 = carol.balance;
        vm.prank(carol);
        mint.claimRefund();
        assertEq(carol.balance, c0 + 0.00672 ether, "refund carol = forfeit only (already fully exited)");

        // Final position: all obligations settled, contract empty.
        assertEq(_totalObligations(), 0, "refund obligations all settled");
        assertEq(wbnb.balanceOf(address(mint)), 0, "contract escrow totally empty");
        assertEq(treasury.balance, 0, "treasury stays 0 on failed launch");
    }

    function test_ExitFullPositionWithReferrerUnwindsEscrow() public {
        // A minter with a referrer exits FULLY: the already-accrued treasury + referral
        // cuts must roll back too, not hang.
        _mintAs(alice, 168, bob);
        assertGt(mint.escrowTreasury(), 0, "treasury escrow filled");
        assertGt(mint.referralAccrued(bob), 0, "referral accrual filled");
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.exit(168);
        assertEq(alice.balance, before + 0.225792 ether, "exit 168: 80% of 0,28224");
        assertEq(mint.escrowTreasury(), 0, "treasury escrow back to 0");
        assertEq(mint.referralAccrued(bob), 0, "referral accrual back to 0");
        assertEq(mint.pendingBnb(), 0, "pending BNB back to 0");
        assertEq(mint.forfeitPool(), 0.056448 ether, "forfeit 20% intact in conditional pool");
        // Solvency: what remains in the contract == forfeit (the only refund
        // obligation left).
        assertEq(wbnb.balanceOf(address(mint)), mint.forfeitOf(alice), "remaining escrow == alice forfeit");
    }
}
