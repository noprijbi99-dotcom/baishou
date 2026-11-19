// SPDX-License-Identifier: MIT
// BAISHOU - jalur POOL OPEN (buka pool di share 16.800).
// Desain: POLA-BARU-ARUNIKA.md §2/§3 - pool buka otomatis saat share 16.800:
// 22,5792 BNB + 2,25792 miliar token; LP 100% ke DEAD; trading dibuka;
// mint lanjut di kurva epoch; mint tutup 7 hari setelah pool buka ATAU 168.000 share.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract PoolOpenTest is BaishouTest {
    function test_PoolNotOpenInitially() public view {
        assertFalse(mint.opened(), "pool belum buka saat deploy");
    }

    function test_OpenEarlyRevertsWithNoMints() public {
        vm.prank(admin);
        vm.expectRevert(AgentMint.CannotOpenEarly.selector);
        mint.openEarly();
    }

    function test_PoolOpensAt16800Shares() public {
        vm.skip(true, "TODO: butuh 16.800 share mint (168 alamat x 100 tx di fork) - jalankan setelah parameterisasi, atau via priceDiv test");
        // Target: sesudah totalMinted == 16.800, opened() == true,
        // tradingEnabled() == true, dan reserves() == (22,5792 BNB, 2,25792 miliar token).
    }

    function test_LpBurnedToDead() public {
        vm.skip(true, "TODO: LP token pool harus 100% ke DEAD (0x000000000000000000000000000000000000dEaD)");
        // Target: balance LP (pair.totalSupply / balanceOf DEAD) == 100% supply LP.
    }

    function test_EpochPriceRises2PercentPer1680Shares() public {
        vm.skip(true, "TODO: parameterisasi - priceUnits epoch LINEAR +2% per 1.680 share");
        // Target: costOf(1) di share 16.801..18.480 == 0,00168 * 1,02;
        // di epoch ke-50 cap 0,00336 lalu datar (bukan naik terus).
    }

    function test_PriceCap2x() public {
        vm.skip(true, "TODO: parameterisasi - harga max 0,00336 BNB (2x), tercapai ~share 100.800");
        // Target: costOf(1) di share >= 100.800 selalu == 0,00336 ether.
    }

    function test_MintCloses7DaysAfterOpenOr168kShares() public {
        vm.skip(true, "TODO(final): mint tutup 7 hari setelah pool buka ATAU 168.000 share - fungsi penutup belum ada di fork");
        // Target: mint sesudah deadline/ sold out revert SoldOut; supply final, tidak ada dilusi.
    }

    function test_OnePairOnly() public {
        vm.skip(true, "TODO(final): SATU pair saja (token/WBNB); pair lain ditolak transfersClosed/PoolRejected");
        // Target: transfer ke pair palsu revert; setPoolBlocked tidak bisa memblokir pair resmi.
    }
}
