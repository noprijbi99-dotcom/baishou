// SPDX-License-Identifier: MIT
// BAISHOU - WAVE-3 PIN: menutup dua catatan audit substantif VERIFY-2.md.
//
// W2 (ForkOpen.t.sol:98-106 versi lama): akrual claimTreasury PASCA-pool
// dulu dihitung 100% dari getter kontrak (costOf, TREASURY_BPS) tanpa
// jangkar literal. Di sini harga kurva + potongan 15% dihitung ULANG dari
// literal spek (BASE 0,00168 BNB; LINEAR +0,0000336/epoch 16.800 share;
// cap 0,00336) oleh fungsi _spec* di file ini — BUKAN dari costOf — lalu
// payout claimTreasury di-pin ke literal keras 0,025704 BNB.
//
// W4 (ForkDividend.t.sol:61-68 versi lama): jumlah klaim dividen dulu
// sirkular (due dibaca dari withdrawableDividendOf). Di sini ekspektasi
// dihitung INDEPENDEN: model bayangan (shadow) memelihara reserves pair,
// saldo pajak minter, totalSupply, dan magnifiedDividendPerShare dari
// angka-angka setup literal + rumus AMM/akumulator spek. Saldo pair ikut
// pro-rata karena akumulator membagi atas totalSupply (termasuk token di
// pair) — itu tercermin persis di model: mdps naik sebesar
// (setoran x 2^128) / totalSupply saat setoran. Token "burn" hasil pajak
// jual juga TETAP di totalSupply (transfer ke DEAD, bukan _burn) dan ikut
// pro-rata — model menahan supply konstan karenanya. Klaim alice diassert
// == floor(saldo alice x mdps bayangan / 2^128); koreksi alice = 0 (token
// diterima saat mdps = 0, tidak pernah dipindah), withdrawn = 0.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {MockPair} from "./mocks/Mocks.sol";

contract Wave3PinTest is BaishouTest {
    // ================= W2: pin akrual treasury pasca-pool =================

    uint256 internal constant SPEC_BASE_PRICE = 0.00168 ether; // literal spek
    uint256 internal constant SPEC_OPEN_AT = 168_000;
    uint256 internal constant SPEC_EPOCH_SHARES = 16_800;

    /// @dev Kurva spek ditulis ulang dari literal: n <= 168.000 -> 100;
    ///      epoch = (n-168.001)/16.800 + 1; units = min(100 + 2*epoch, 200).
    function _specUnits(uint256 n) internal pure returns (uint256) {
        if (n <= SPEC_OPEN_AT) return 100;
        uint256 epoch = (n - SPEC_OPEN_AT - 1) / SPEC_EPOCH_SHARES + 1;
        uint256 units = 100 + 2 * epoch;
        return units > 200 ? 200 : units;
    }

    function _specCost(uint256 firstShare, uint256 shares) internal pure returns (uint256 cost) {
        uint256 unit = SPEC_BASE_PRICE / 100;
        for (uint256 i; i < shares; i++) {
            cost += _specUnits(firstShare + i) * unit;
        }
    }

    /// @dev Potongan treasury per share persis seperti spek: pay x 15%,
    ///      floor per share, lalu dijumlahkan.
    function _specTreasury(uint256 firstShare, uint256 shares) internal pure returns (uint256 acc) {
        uint256 unit = SPEC_BASE_PRICE / 100;
        for (uint256 i; i < shares; i++) {
            uint256 pay = _specUnits(firstShare + i) * unit;
            acc += pay * 1_500 / 10_000;
        }
    }

    function test_W2_PostPoolTreasuryAccrualPinnedLiteral() public {
        _openPool(alice); // totalMinted = 168.000, pool buka

        // Jangkar awal (literal): trigger mint 1 share flat -> cut 15% =
        // 0,000252 BNB dibayar ke treasury saat _open; escrow kembali 0.
        assertEq(treasury.balance, 0.000252 ether, "cut trigger dibayar saat open");
        assertEq(mint.escrowTreasury(), 0, "prasyarat: escrow 0 sesudah open");

        // Mint pasca-pool: 100 share oleh bob = share #168.001..#168.100,
        // semuanya epoch 1 -> units 102 -> 0,0017136 BNB/share.
        uint256 firstShare = 168_001;
        uint256 shares = 100;
        uint256 expectedCost = _specCost(firstShare, shares);
        assertEq(expectedCost, 0.17136 ether, "PIN W2: biaya spek 100 share epoch-1");
        uint256 expectedTreasury = _specTreasury(firstShare, shares);
        assertEq(expectedTreasury, 0.025704 ether, "PIN W2: akrual spek = 15% x 0,17136");

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        mint.mint{value: expectedCost}(shares, address(0), expectedCost);
        assertEq(bob.balance, bobBefore - expectedCost, "bob bayar persis biaya spek (refund 0)");
        assertEq(token.balanceOf(bob), 16_800_000_000 ether, "bob terima 100 x 168 jt token");
        assertEq(mint.escrowTreasury(), expectedTreasury, "escrow terakru = angka spek");

        uint256 treasuryBefore = treasury.balance;
        vm.prank(treasury);
        mint.claimTreasury();
        assertEq(
            treasury.balance,
            treasuryBefore + 0.025704 ether,
            "PIN W2: claimTreasury membayar 0,025704 BNB persis"
        );
        assertEq(mint.escrowTreasury(), 0, "escrow habis sesudah klaim");

        vm.prank(treasury);
        vm.expectRevert(AgentMint.NothingOwed.selector);
        mint.claimTreasury();
    }

    // ================= W4: pin jumlah klaim dividen =======================

    uint256 internal constant SPEC_MAGNITUDE = 2 ** 128; // literal spek akumulator

    /// @dev Rumus AMM spek (PancakeMath.amountOut, fee swap test = 30 bps
    ///      dari Config setUp) ditulis ulang dari parameter setup.
    function _specAmountOut(uint256 amtIn, uint256 rIn, uint256 rOut) internal pure returns (uint256) {
        uint256 inWithFee = amtIn * (10_000 - 30);
        return (inWithFee * rOut) / (rIn * 10_000 + inWithFee);
    }

    /// @dev Jual seluruh token pajak minter via swapTax() sungguhan, sambil
    ///      memajukan model bayangan: cap per panggilan = reserve token
    ///      pair x 10/10.000 (TAX_SWAP_BPS spek), BNB keluar via rumus AMM,
    ///      mdps naik (D x 2^128)/supply — supply KONSTAN selama flush
    ///      (jual pajak = transfer, bukan burn).
    function _flushTaxShadow(uint256 rT, uint256 rW, uint256 minterBal, uint256 supply, uint256 mdps, uint256 totalDep)
        internal
        returns (uint256, uint256, uint256, uint256)
    {
        while (minterBal > 0) {
            uint256 cap = rT * 10 / 10_000;
            uint256 amt = minterBal < cap ? minterBal : cap;
            vm.roll(block.number + 1);
            mint.swapTax();
            uint256 d = _specAmountOut(amt, rT, rW);
            mdps += (d * SPEC_MAGNITUDE) / supply;
            totalDep += d;
            rT += amt;
            rW -= d;
            minterBal -= amt;
        }
        return (rT, rW, mdps, totalDep);
    }

    function test_W4_DividendClaimMatchesIndependentComputation() public {
        // ---- Setup deterministik: pool buka via jalur NYATA (v2:
        //      openEarly dihapus) — alice 168 share + fill 999 agen.
        //      Supply total = user 28,224 T + pool 22,5792 T; seed pool
        //      239,904 BNB (semua mint tanpa referrer). ----
        _mintAs(alice, 168, address(0));
        _fillToOpen(address(0));
        MockPair pair = _pair();
        address pairAddr = address(pair);

        uint256 aliceTokens = 28_224_000_000 ether; // 168 x 168.000.000 (literal)
        uint256 supply0 = 50_803_200_000_000 ether; // 28,224 T user + 22,5792 T pool
        assertEq(token.balanceOf(alice), aliceTokens, "setup: saldo alice literal");
        assertEq(token.totalSupply(), supply0, "setup: supply awal literal");
        (uint256 rBnb0, uint256 rToken0) = mint.reserves();
        assertEq(rBnb0, 239.904 ether, "setup: reserve BNB literal (jangkar model)");
        assertEq(rToken0, 22_579_200_000_000 ether, "setup: reserve token literal (jangkar model)");

        // ---- Bob BELI 9 triliun token (gross) dari pair; bayar 96 BNB ----
        vm.prank(bob);
        wbnb.deposit{value: 96 ether}();
        vm.prank(bob);
        wbnb.transfer(pairAddr, 96 ether);
        uint256 buyGross = 9_000_000_000_000 ether;
        (uint256 out0, uint256 out1) =
            pair.token0() == address(token) ? (buyGross, uint256(0)) : (uint256(0), buyGross);
        pair.swap(out0, out1, bob, "");
        // Split spek beli 2%: 180 miliar ke minter, 8,82 triliun ke bob.
        assertEq(token.balanceOf(address(mint)), 180_000_000_000 ether, "setup: pajak beli 2%");
        assertEq(token.balanceOf(bob), 8_820_000_000_000 ether, "setup: bob terima 98%");

        // ---- Flush pajak beli -> dividend pool (model bayangan) ----
        uint256 rT = 13_579_200_000_000 ether; // 22_579_200_000_000 - 9_000_000_000_000
        uint256 rW = 335.904 ether; // 239,904 (pool open) + 96 (bayaran bob)
        uint256 mdps;
        uint256 totalDep;
        (rT, rW, mdps, totalDep) = _flushTaxShadow(rT, rW, 180_000_000_000 ether, supply0, 0, 0);
        assertEq(token.balanceOf(address(mint)), 0, "model: pajak beli habis terjual");

        // ---- Bob JUAL 2 triliun token: split spek 1% burn + 1% kept ----
        // CATATAN MODEL: "burn" di AgentToken adalah transfer ke DEAD,
        // BUKAN _burn — tokennya TETAP ada di totalSupply dan ikut
        // pro-rata dividen (tidak pernah diklaim DEAD). Jadi supply
        // TIDAK turun; penyebut akumulator tetap supply0 di flush kedua.
        vm.prank(bob);
        token.transfer(pairAddr, 2_000_000_000_000 ether);
        (uint256 w0, uint256 w1) =
            pair.token0() == address(wbnb) ? (uint256(20 ether), uint256(0)) : (uint256(0), uint256(20 ether));
        pair.swap(w0, w1, bob, ""); // bob ambil 20 BNB (parameter setup)
        assertEq(token.balanceOf(token.DEAD()), 20_000_000_000 ether, "setup: burn 1% parkir di DEAD");
        assertEq(token.totalSupply(), supply0, "setup: supply tetap (burn = transfer ke DEAD)");
        assertEq(token.balanceOf(address(mint)), 20_000_000_000 ether, "setup: kept 1% di minter");
        rT += 1_960_000_000_000 ether; // net token masuk pair (2 T - 1% - 1%)
        rW -= 20 ether;

        // ---- Flush pajak jual -> dividend pool (penyebut tetap supply0) ----
        (rT, rW, mdps, totalDep) = _flushTaxShadow(rT, rW, 20_000_000_000 ether, supply0, mdps, totalDep);
        assertEq(token.balanceOf(address(mint)), 0, "model: pajak jual habis terjual");
        // Validasi model: total setoran versi kontrak == versi bayangan.
        assertEq(token.totalDividends(), totalDep, "model: total setoran dividen cocok");

        // ---- Ekspektasi alice: pro-rata murni atas mdps bayangan ----
        // Pair memegang ~35% supply pada titik ini dan ikut pro-rata —
        // sudah tercermin karena mdps membagi atas totalSupply PENUH.
        uint256 expected = aliceTokens * mdps / SPEC_MAGNITUDE;
        assertEq(expected, 2_653_293_237_882_583, "PIN W4 (v2, pool nyata): ekspektasi literal 0,002653293237882583 BNB");
        assertGe(expected, 0.001 ether, "ekspektasi di atas ambang klaim minimum");
        uint256 before = alice.balance;
        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, before + expected, "PIN W4: klaim alice == hitungan independen");
        assertEq(token.withdrawableDividendOf(alice), 0, "habis diklaim, tidak bisa ganda");
    }
}
