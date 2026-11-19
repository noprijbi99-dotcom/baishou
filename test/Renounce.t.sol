// SPDX-License-Identifier: MIT
// BAISHOU - jalur RENOUNCE + PAUSE (admin minimal, trust-max).
// Desain FINAL: admin CUMA pause; renounce DITUNDA sampai review independen
// selesai (flag reviewPassed, bukan fixed H+7); pause TIDAK PERNAH memblokir
// refund/exit. TIDAK ADA fungsi withdraw/drain di kontrak.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockPair, MockWBNB} from "./mocks/Mocks.sol";

contract RenounceTest is BaishouTest {
    function test_RenounceOnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotAdmin.selector);
        mint.renounce();
    }

    function test_PauseOnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotAdmin.selector);
        mint.setPaused(true);
    }

    function test_SetReviewPassedOnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotAdmin.selector);
        mint.setReviewPassed(true);
    }

    function test_RenounceDelayedUntilReview() public {
        assertFalse(mint.reviewPassed(), "review belum lolos saat deploy");
        vm.prank(admin);
        vm.expectRevert(AgentMint.ReviewNotPassed.selector);
        mint.renounce();
        assertFalse(mint.renounced(), "tetap belum renounce");
        vm.prank(admin);
        mint.setReviewPassed(true);
        assertTrue(mint.reviewPassed(), "review lolos");
        vm.prank(admin);
        mint.renounce();
        assertTrue(mint.renounced(), "renounce berhasil sesudah review");
    }

    function test_PauseNeverBlocksExit() public {
        _mintAs(alice, 5, address(0));
        vm.prank(admin);
        mint.setPaused(true);
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.exit(5);
        assertEq(alice.balance, before + 5 * 0.00168 ether * 80 / 100, "pause tidak blokir exit");
    }

    function test_RenounceReleasesBlocks() public {
        _mintAs(alice, 5, address(0));
        _openPool(carol);
        // Alamat berkode non-pair yang diblokir admin: transfer ditolak
        // selama blocks aktif (bukan pair palsu — pair lain tetap ditolak
        // selamanya oleh aturan satu-pair, bahkan sesudah renounce).
        MockWBNB dummy = new MockWBNB();
        address dummyAddr = address(dummy);
        vm.prank(admin);
        mint.setPoolBlocked(dummyAddr, true);
        vm.prank(alice);
        vm.expectRevert(AgentToken.PoolRejected.selector);
        token.transfer(dummyAddr, 1 ether);
        // Sesudah review + renounce, blokir dilepas (disableBlocks).
        vm.prank(admin);
        mint.setReviewPassed(true);
        vm.prank(admin);
        mint.renounce();
        assertTrue(token.blocksDisabled(), "blocks dimatikan saat renounce");
        vm.prank(alice);
        token.transfer(dummyAddr, 1 ether);
        assertEq(token.balanceOf(dummyAddr), 1 ether, "transfer ke ex-blocked jalan");
    }

    function test_NoWithdrawFunction() public {
        // §8b: TIDAK ADA jalan keluar dana selain refund/pool. Buktikan
        // tidak ada fungsi withdraw/drain yang bisa dipanggil siapa pun.
        (bool okWithdraw,) = address(mint).call(abi.encodeWithSignature("withdraw(uint256)", 1));
        assertFalse(okWithdraw, "tidak ada withdraw(uint256)");
        (bool okDrain,) = address(mint).call(abi.encodeWithSignature("drain()"));
        assertFalse(okDrain, "tidak ada drain()");
        (bool okRescue,) = address(mint).call(abi.encodeWithSignature("rescueTokens(address)", address(token)));
        assertFalse(okRescue, "tidak ada rescueTokens(address)");
        // Admin pun tidak bisa memanggil jalur apa pun untuk menarik escrow.
        assertEq(mint.escrowTreasury(), 0, "escrow kosong di awal");
    }
}
