// SPDX-License-Identifier: MIT
// BAISHOU - jalur RENOUNCE + PAUSE (admin minimal, trust-max).
// Desain: POLA-BARU-ARUNIKA.md §8/§10 - admin CUMA pause; renounce DITUNDA
// sampai review independen selesai (bukan fixed H+7); pause TIDAK PERNAH
// memblokir refund. Review dipesan saat pool buka, dibayar dari treasury.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

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

    function test_RenounceDelayedUntilReview() public {
        vm.skip(true, "TODO(final): renounce() harus TERKUNCI sampai review independen selesai - mekanisme gate belum diputuskan");
        // Target: renounce() revert sebelum review selesai (mis. flag
        // reviewPassed == false); sesudah review lolos, admin bisa renounce.
        // Fork AIC: renounce() langsung bisa - test ini SENGAJA gagal di fork.
        vm.prank(admin);
        vm.expectRevert();
        mint.renounce();
    }

    function test_PauseNeverBlocksRefunds() public {
        vm.skip(true, "TODO(final): pause tidak memblokir claimRefund()/exit() - lihat RefundFail.t.sol");
    }

    function test_RenounceReleasesBlocks() public {
        vm.skip(true, "TODO(final): sesudah renounce, token.disableBlocks() terpanggil dan transfer bebas");
        // Target: renounce() -> token.disableBlocks(); transfer holder->holder
        // dan ke pair mana pun tidak lagi revert PoolRejected.
    }

    function test_NoWithdrawFunction() public {
        vm.skip(true, "TODO(final): kontrak TIDAK PUNYA fungsi withdraw - dana hanya bisa ke deposan (refund) atau pool");
        // Aturan §8b: tidak ada jalan keluar dana selain refund/pool.
        // Test ini berupa audit statis (grep): tidak ada fungsi yang
        // mengirim BNB/token ke admin/treasury di luar jalur escrow->pool.
    }
}
