// SPDX-License-Identifier: MIT
// BAISHOU - the REFUND EXIT path (exit before the pool opens, back 80%).
// FINAL design: pre-pool minters may exit before the pool opens, receive 80%;
// the 20% forfeit goes to CONDITIONAL LP: if the launch ultimately FAILS, exiters
// get 100% back (forfeit returned via claimRefund).
// Exit only while net shares (sold - exited) < the 168.000 target.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract RefundExitTest is BaishouTest {
    function test_Exit80PercentPrePool() public {
        _mintAs(alice, 10, address(0));
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.exit(10);
        assertEq(alice.balance, before + 0.0168 ether * 80 / 100, "kembali 80%");
        assertEq(mint.forfeitOf(alice), 0.0168 ether * 20 / 100, "20% forfeit tercatat");
        assertEq(mint.forfeitPool(), 0.0168 ether * 20 / 100, "forfeit pool terakumulasi");
        assertEq(mint.mintedCount(ALICE_ID), 0, "share alice habis");
        assertEq(mint.totalMinted(), 0, "totalMinted turun");
        assertEq(token.balanceOf(alice), 0, "token alice dibakar");
        assertEq(mint.deposits(alice), 0, "deposit alice habis");
    }

    function test_ExitBurnsSharesAndTokens() public {
        _mintAs(alice, 5, address(0));
        vm.prank(alice);
        mint.exit(2);
        assertEq(mint.mintedCount(ALICE_ID), 3, "sisa 3 share");
        assertEq(mint.totalMinted(), 3, "total 3 share");
        assertEq(token.balanceOf(alice), 3 * 168_000_000 ether, "sisa 3 x 168 jt token");
        assertEq(mint.deposits(alice), 3 * 0.00168 ether, "deposit sisa 3 share");
    }

    function test_ExitForfeitToLpConditionally() public {
        _mintAs(alice, 10, address(0));
        vm.prank(alice);
        mint.exit(10);
        uint256 forfeit = 0.0168 ether * 20 / 100;
        _openPool(carol);
        // Forfeit joins as bonus liquidity on top of OPEN_BNB.
        assertEq(wbnb.balanceOf(address(_pair())), mint.OPEN_BNB() + forfeit, "LP + forfeit");
        (uint256 rBnb,) = mint.reserves();
        assertEq(rBnb, mint.OPEN_BNB() + forfeit, "reserve BNB termasuk forfeit");
        assertEq(mint.forfeitPool(), 0, "forfeit pool kosong sesudah _open");
    }

    function test_ExitForfeitReturnedIfLaunchFails() public {
        _mintAs(alice, 10, address(0));
        vm.prank(alice);
        mint.exit(10);
        uint256 forfeit = 0.0168 ether * 20 / 100;
        vm.warp(vm.getBlockTimestamp() + 14 days + 1);
        assertTrue(mint.saleFailed(), "launch gagal");
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, before + forfeit, "forfeit 20% kembali");
        assertEq(mint.forfeitOf(alice), 0, "forfeit habis diklaim");
        // Total back: 80% (exit) + 20% (refund) = 100% of 0,0168.
    }

    function test_ExitDisabledAfterTargetHit() public {
        // Guard: net shares >= target -> exit closes (this state is only
        // reachable via store in tests; in production the pool opens immediately).
        _mintAs(alice, 10, address(0));
        vm.store(address(mint), bytes32(uint256(0)), bytes32(mint.OPEN_AT()));
        vm.prank(alice);
        vm.expectRevert(AgentMint.ExitClosed.selector);
        mint.exit(1);
    }

    function test_ExitAfterPoolOpenReverts() public {
        _mintAs(alice, 5, address(0));
        _openPool(carol);
        vm.prank(alice);
        vm.expectRevert(AgentMint.ExitClosed.selector);
        mint.exit(1);
    }

    function test_ExitWhilePausedWorks() public {
        _mintAs(alice, 5, address(0));
        vm.prank(admin);
        mint.setPaused(true);
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.exit(5);
        assertEq(alice.balance, before + 5 * 0.00168 ether * 80 / 100, "pause tidak blokir exit");
    }

    function test_ExitMoreThanOwnedReverts() public {
        _mintAs(alice, 2, address(0));
        vm.prank(alice);
        vm.expectRevert(AgentMint.BadShares.selector);
        mint.exit(3);
        vm.prank(alice);
        vm.expectRevert(AgentMint.BadShares.selector);
        mint.exit(0);
    }

    function test_ExitReducesEscrowSoTreasuryNotOverpaid() public {
        // Alice mints 10 with referrer bob, then exits all 10: the treasury
        // + referral escrow shrinks too, so _open does not overpay.
        _mintAs(alice, 10, bob);
        vm.prank(alice);
        mint.exit(10);
        assertEq(mint.escrowTreasury(), 0, "escrow treasury kembali 0");
        assertEq(mint.referralAccrued(bob), 0, "akrual referral kembali 0");
        assertEq(mint.pendingBnb(), 0, "pending BNB kembali 0");
    }
}
