// SPDX-License-Identifier: MIT
// BAISHOU - jalur REFUND GAGAL (target 168.000 share tidak tercapai
// dalam jendela sale 14 hari sejak startSale — v2).
// Desain FINAL: SEMUA paid mint refund 100% via klaim PULL (tiap orang klaim
// sendiri; jendela klaim 90 hari; sisa yang tidak diklaim setelah 90 hari
// dibakar ke dead address - tidak ada yang diuntungkan dari refund tak diklaim).
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract RefundFailTest is BaishouTest {
    function _fail() internal {
        vm.warp(vm.getBlockTimestamp() + 14 days + 1);
        assertTrue(mint.saleFailed(), "launch gagal");
    }

    function test_FailRefund100PercentPull() public {
        _mintAs(alice, 10, address(0));
        uint256 paid = 10 * 0.00168 ether;
        _fail();
        assertEq(treasury.balance, 0, "treasury TIDAK pernah dibayar");
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, before + paid, "refund 100% penuh");
        assertEq(mint.deposits(alice), 0, "deposit habis sesudah klaim");
        // Klaim ke-2: tidak ada lagi.
        vm.prank(alice);
        vm.expectRevert(AgentMint.NothingOwed.selector);
        mint.claimRefund();
    }

    function test_FailRefundWindow90Days() public {
        _mintAs(alice, 10, address(0));
        _mintAs(bob, 10, address(0));
        // Batas akhir jendela (inklusif): alice masih bisa klaim.
        vm.warp(mint.failureTime() + 90 days);
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, before + 10 * 0.00168 ether, "klaim di hari ke-90 berhasil");
        // Selewat 1 detik: bob sudah terlambat.
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
        assertEq(dead.balance, deadBefore + escrow, "sisa escrow dibakar ke DEAD");
        assertEq(wbnb.balanceOf(address(mint)), 0, "escrow WBNB kosong");
        assertEq(treasury.balance, 0, "tim tidak menerima apa pun dari sweep");
        assertEq(mint.pendingBnb(), 0, "pending BNB 0 sesudah sweep");
    }

    function test_SweepTooEarlyReverts() public {
        _mintAs(alice, 10, address(0));
        _fail();
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotSweepable.selector);
        mint.sweepUnclaimed();
        vm.warp(mint.failureTime() + 90 days); // tepat di batas: masih terlalu dini
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
        // PULL: alice klaim hanya membayar alice; bob tidak berubah.
        _mintAs(alice, 10, address(0));
        _mintAs(bob, 10, address(0));
        _fail();
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(bob.balance, bobBefore, "klaim alice tidak menyentuh bob");
        assertGt(mint.deposits(bob), 0, "deposit bob tetap menunggu klaimnya sendiri");
    }

    function test_PauseNeverBlocksRefunds() public {
        _mintAs(alice, 10, address(0));
        _fail();
        vm.prank(admin);
        mint.setPaused(true);
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, before + 10 * 0.00168 ether, "pause tidak blokir refund");
    }
}
