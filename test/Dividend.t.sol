// SPDX-License-Identifier: MIT
// BAISHOU - jalur DIVIDEN holder (pajak trading 2%/2% -> 1% burn + 1% dividen).
// Desain: POLA-BARU-ARUNIKA.md §2/§6/§10 - dividen pro-rata per token via
// accumulator claims (pola DividendPayingToken: magnifiedDividendPerShare).
// ⚠️ JUJUR (temuan NO-MISTAKE-CHECK §2.4): dividen adalah DEBU - volume
// 100 BNB/bulan -> holder cap ~$0,06/bulan. Dividen TIDAK PERNAH dijanjikan
// sebagai penghasilan. Mekanisme tetap dibangun (janji di manifesto), tapi
// narasi publik tidak boleh menjual dividen sebagai income.
// Mekanisme accumulator BELUM ADA di fork AIC (AIC: 1% kept -> minter lalu
// swapTax ke feeTreasury) - test di bawah ini spesifikasi.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";

contract DividendTest is BaishouTest {
    function test_SellTaxSplitBurnAndDividend() public {
        vm.skip(true, "TODO(final): jual 1% burn + 1% dividend pool - accumulator belum ada");
        // Target: jual 1.000.000 token ke pair -> 10.000 token burn (DEAD),
        // 10.000 token masuk dividend pool (bukan ke feeTreasury seperti AIC).
    }

    function test_DividendAccruesProRata() public {
        vm.skip(true, "TODO(final): claimDividend() pro-rata per token (magnifiedDividendPerShare)");
        // Target: alice pegang 2x token bob -> dividen alice 2x bob;
        // yang beli token di pasar sesudah dividen terkumpul TIDAK dapat
        // dividen periode lalu (accumulator, bukan snapshot retroaktif).
    }

    function test_DividendClaimDoesNotRequireSell() public {
        vm.skip(true, "TODO(final): klaim dividen kapan saja, tanpa jual token");
        // Target: claimDividend() transfer BNB dividen ke holder; klaim
        // berulang hanya membayar akumulasi baru sejak klaim terakhir.
    }

    function test_BuyTaxGoesToDividendPool() public {
        vm.skip(true, "TODO(final): beli 2% masuk dividend pool (bukan feeTreasury)");
        // Target: beli dari pair -> 2% token ke dividend pool contract;
        // tim 0% dari pajak trading (pendapatan tim HANYA treasury 15% mint).
    }

    function test_DividendIsDust() public {
        vm.skip(true, "TODO(dokumentasi): dividen = debu - test ini mengunci ekspektasi, bukan nominal");
        // Angka acuan: volume 100 BNB/bulan, pajak 2% -> pool dividen
        // ~2 BNB/bulan dibagi semua holder; holder cap (168 share) ~$0,06/bulan.
        // Test mengunci bahwa klaim bekerja untuk nominal kecil (tidak ada
        // minimum klaim yang mengunci debu selamanya) - ambang minimum klaim
        // mengikuti §10 #15 (gas cost), bukan angka yang mengada-ada.
    }
}
