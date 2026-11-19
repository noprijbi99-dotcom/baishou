// SPDX-License-Identifier: MIT
// BAISHOU - jalur REFUND GAGAL (target 16.800 share tidak tercapai 7 hari).
// Desain: POLA-BARU-ARUNIKA.md §2/§8b - SEMUA paid mint refund 100% via klaim
// PULL (tiap orang klaim sendiri; jendela klaim 90 hari; sisa yang tidak
// diklaim setelah 90 hari dibakar ke dead address - tidak ada yang diuntungkan
// dari refund yang tidak diklaim). Fungsi-fungsi ini BELUM ADA di fork AIC
// (AIC tidak punya refund gagal) - test di bawah ini spesifikasi, bukan kode jalan.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";

contract RefundFailTest is BaishouTest {
    function test_FailRefund100PercentPull() public {
        vm.skip(true, "TODO(final): claimRefund() belum ada - refund 100% PULL saat launch gagal");
        // Target: alice mint 10 share pre-pool (bayar 0,0168 BNB). Deadline
        // 7 hari lewat, totalMinted < 16.800. alice claimRefund() terima
        // 0,0168 BNB penuh. Treasury + referral TIDAK pernah dibayar (escrow).
    }

    function test_FailRefundWindow90Days() public {
        vm.skip(true, "TODO(final): jendela klaim refund 90 hari");
        // Target: claimRefund() berhasil dalam 90 hari sesudah gagal;
        // sesudah 90 hari revert (dana sisa masuk dead address).
    }

    function test_UnclaimedRefundBurnedToDead() public {
        vm.skip(true, "TODO(final): sisa refund tak diklaim -> DEAD, bukan ke tim");
        // Target: setelah 90 hari, siapa pun bisa memicu sweep sisa escrow
        // ke DEAD; saldo escrow kontrak == 0; tim tidak menerima apa pun.
    }

    function test_NoFailRefundAfterPoolOpens() public {
        vm.skip(true, "TODO(final): claimRefund() revert kalau pool sudah buka");
        // Target: launch sukses (pool buka) -> claimRefund() revert;
        // yang berlaku sesudah itu hanya exit 80% pre-pool (lihat RefundExit.t.sol)
        // dan jual di pasar.
    }

    function test_RefundPullNeverPush() public {
        vm.skip(true, "TODO(final): refund PULL - kontrak TIDAK PERNAH mass-push BNB ke banyak alamat");
        // Alasan keamanan (§8b): push massal = DoS kalau satu penerima
        // revert + gas tak terbatas. Tiap orang klaim sendiri.
    }

    function test_PauseNeverBlocksRefunds() public {
        vm.skip(true, "TODO(final): setPaused(true) TIDAK BOLEH memblokir claimRefund()");
        // Target: admin pause saat gagal -> claimRefund() tetap berhasil.
        // Ini aturan §8b: pause tidak pernah memblokir refund.
    }
}
