// SPDX-License-Identifier: MIT
// BAISHOU - jalur MINT (pre-pool flat + kurva epoch).
// Desain: POLA-BARU-ARUNIKA.md §2/§3 - 16.800 share pertama @ 0,00168 BNB flat,
// 168.000 token/share; sesudah itu epoch +2% per 1.680 share, cap 0,00336 (2x).
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract MintTest is BaishouTest {
    function test_FlatPricePrePool() public {
        vm.skip(true, "TODO: parameterisasi - costOf(1) harus 0,00168 ether");
        assertEq(mint.costOf(1), 0.00168 ether, "1 share pre-pool = 0,00168 BNB");
        assertEq(mint.costOf(168), 168 * 0.00168 ether, "harga flat s.d. 16.800 share");
    }

    function test_Cap168PerAddress() public {
        vm.skip(true, "TODO: parameterisasi - quotaOf harus 168 per alamat");
        uint256 cost = mint.costOf(168);
        vm.prank(alice);
        mint.mint{value: cost}(168, address(0), cost);
        assertEq(mint.mintedCount(ALICE_ID), 168, "cap tercapai");
        uint256 cost1 = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentMint.Quota.selector);
        mint.mint{value: cost1}(1, address(0), cost1);
    }

    function test_MaxPerTxEqualsCap() public {
        vm.skip(true, "TODO: parameterisasi - MAX_PER_TX harus 168");
        uint256 cost = mint.costOf(169);
        vm.prank(alice);
        vm.expectRevert(AgentMint.BadShares.selector);
        mint.mint{value: cost}(169, address(0), cost);
    }

    function test_ReferralNotPaidInstantly() public {
        vm.skip(true, "TODO(final): referral 5% flat dibayar SAAT pool buka (escrow), bukan instan seperti AIC");
        // Target: alice mint 1 share dengan referrer bob.
        // - Segera sesudah mint: saldo BNB bob TIDAK berubah (komisi ditahan escrow).
        // - Sesudah pool buka (share 16.800): bob terima 5% dari pembayaran alice.
        // Fork AIC saat ini membayar rebate instan via _rebate() - test ini
        // SENGAJA gagal di fork sampai escrow ditulis.
        uint256 cost = mint.costOf(1);
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        mint.mint{value: cost}(1, bob, cost);
        assertEq(bob.balance, bobBefore, "referral ditahan escrow sampai pool buka");
    }

    function test_TreasuryNotPaidInstantly() public {
        vm.skip(true, "TODO(final): treasury 15% dibayar SAAT pool buka (escrow), bukan instan seperti AIC");
        // Target: sesudah mint pre-pool, saldo BNB treasury TIDAK berubah.
        // Fork AIC membayar _payTreasury() di tiap _mintShares - test ini
        // SENGAJA gagal di fork sampai escrow ditulis.
        uint256 cost = mint.costOf(1);
        uint256 treasuryBefore = treasury.balance;
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(treasury.balance, treasuryBefore, "treasury ditahan escrow sampai pool buka");
    }

    function test_GateIdOnlyCapped8400() public {
        vm.skip(true, "TODO(final): gate 24 jam ID-only max 8.400 share - fungsi gate belum ada di fork");
        // Target: 24 jam pertama hanya pemegang Agent ID bisa mint, dan
        // total mint dalam gate dibatasi 8.400 share. Setelah 24 jam ATAU
        // 8.400 share (mana dulu), semua wallet bisa mint.
        // Catatan: wallet tanpa Agent ID (stranger) harus revert NoAgent
        // selama gate; sesudah gate dibuka, stranger bisa mint.
    }

    function test_FreeMintOnePerAgentId() public {
        vm.skip(true, "TODO(final): freeMint 1.680 share (1 per Agent ID, first-come) - fungsi belum ada di fork");
        // Target: freeMint() untuk alice (Agent ID) berhasil 1x, terima
        // 16.800 token, tanpa BNB. Panggilan ke-2 revert (sudah klaim).
        // Stranger tanpa Agent ID revert NoAgent. Total free dibatasi 1.680.
    }
}
