// SPDX-License-Identifier: MIT
// BAISHOU - jalur REFUND EXIT (keluar sebelum pool buka, kembali 80%).
// Desain: POLA-BARU-ARUNIKA.md §2/§10 - minter pre-pool boleh exit sebelum
// pool buka, terima 80% kembali; 20% forfeit masuk LP KONDIONAL: kalau launch
// akhirnya GAGAL, exiters dapat 100% kembali (forfeit dikembalikan).
// Aturan exit-vs-target: exit hanya selama net shares (terjual - exit) < target;
// sesudah target tercapai, exit ditutup (yang sudah masuk, ikut).
// Fungsi exit() BELUM ADA di fork AIC - test di bawah ini spesifikasi.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";

contract RefundExitTest is BaishouTest {
    function test_Exit80PercentPrePool() public {
        vm.skip(true, "TODO(final): exit() belum ada - keluar pre-pool kembali 80%");
        // Target: alice mint 10 share (0,0168 BNB), exit() terima 0,01344 BNB;
        // 0,00336 BNB (20%) ditahan sebagai forfeit kondisional.
    }

    function test_ExitForfeitToLpConditionally() public {
        vm.skip(true, "TODO(final): forfeit 20% -> LP kalau launch sukses");
        // Target: launch sukses (pool buka) -> forfeit alice masuk LP;
        // LP bertambah sebesar forfeit yang terkumpul.
    }

    function test_ExitForfeitReturnedIfLaunchFails() public {
        vm.skip(true, "TODO(final): launch gagal -> exiters dapat 100% kembali");
        // Target: alice exit (terima 80%), lalu launch gagal -> alice
        // claimRefund() terima sisa 20% forfeit-nya. Total kembali 100%.
    }

    function test_ExitDisabledAfterTargetHit() public {
        vm.skip(true, "TODO(final): exit ditutup saat net shares >= 16.800 (target tercapai)");
        // Target: sesudah target tercapai, exit() revert - mencegah exit massal
        // membunuh launch yang sudah mencapai target (temuan NO-MISTAKE-CHECK §2.5).
    }

    function test_ExitAfterPoolOpenReverts() public {
        vm.skip(true, "TODO(final): exit() revert sesudah pool buka - yang berlaku tinggal jual di pasar");
    }

    function test_ExitBurnsSharesAndTokens() public {
        vm.skip(true, "TODO(final): exit() membakar share + token minter (tidak bisa exit lalu tetap pegang token)");
        // Target: sesudah exit, mintedCount alice berkurang, token balance
        // alice berkurang sejumlah share yang di-exit, totalMinted turun.
    }
}
