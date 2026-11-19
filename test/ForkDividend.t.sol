// SPDX-License-Identifier: MIT
// BAISHOU - FORK TEST jalur DIVIDEN dari SWAP NYATA lewat pair.
// Bedanya dari Dividend.t.sol: di sana dividen kebanyakan disetor langsung
// (prank depositDividends) atau pajak disimulasikan via transfer biasa.
// Di sini rantainya PENUH seperti produksi:
//   pool dibuka lewat jalur mint NYATA sampai OPEN_AT (v2: openEarly
//   DIHAPUS — alice 168 share + _fillToOpen 999 agen) -> bob BELI token
//   lewat pair.swap() (pajak beli 2% masuk minter) -> swapTax() berulang
//   menjual token pajak jadi BNB -> BNB masuk dividend pool -> holder
//   (alice) claimDividend() di atas ambang minimum 0,001 BNB, dengan
//   delta saldo PERSIS sama dengan withdrawableDividendOf sesaat
//   sebelum klaim.
// Skala: alice memegang 168 share dari 168.000 (1/1800 dari supply),
// jadi volume swap dibuat besar (bob beli 9 triliun token) supaya
// dividen alice dari pajak swap beneran melewati ambang 0,001 BNB —
// bukan dari setoran artifisial. Pada produksi pun dividen per holder
// kecil memang debu (lihat catatan jujur di Dividend.t.sol); yang
// dibuktikan di sini adalah RANTAI mekanismenya bekerja end-to-end.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {MockPair} from "./mocks/Mocks.sol";

contract ForkDividendTest is BaishouTest {
    function test_SwapTaxToDividendClaimEndToEnd() public {
        // --- Pool buka via jalur nyata: alice 168 share + fill 999 agen ---
        _mintAs(alice, 168, address(0));
        _fillToOpen(address(0));
        assertTrue(mint.opened(), "pool buka di OPEN_AT (jalur nyata)");
        // Escrow treasury 15% dari 282,24 dibayar SEKALI saat _open.
        assertEq(treasury.balance, 42.336 ether, "treasury 15% dibayar saat pool buka");
        (uint256 rBnb0, uint256 rToken0) = mint.reserves();
        assertEq(rBnb0, 239.904 ether, "pool BNB = 85% x 282,24 (tanpa referrer)");
        assertEq(rToken0, mint.OPEN_TOKENS(), "pool token = OPEN_TOKENS");

        // --- Bob BELI lewat pair.swap(): WBNB masuk, token keluar ---
        MockPair pair = _pair();
        address pairAddr = address(pair);
        vm.prank(bob);
        wbnb.deposit{value: 96 ether}();
        vm.prank(bob);
        wbnb.transfer(pairAddr, 96 ether);
        uint256 buyOut = 9_000_000_000_000 ether; // 9 triliun token dari pool
        (uint256 out0, uint256 out1) =
            pair.token0() == address(token) ? (buyOut, uint256(0)) : (uint256(0), buyOut);
        pair.swap(out0, out1, bob, "");
        assertEq(token.balanceOf(bob), buyOut * 9_800 / 10_000, "bob terima 98% (pajak beli 2%)");
        assertEq(token.balanceOf(address(mint)), buyOut * 200 / 10_000, "pajak beli 2% di minter");

        // --- swapTax() berulang (satu per blok) sampai token pajak habis:
        //     token pajak -> BNB -> dividend pool. Bukan setoran langsung. ---
        uint256 swapped;
        for (uint256 i; i < 40; i++) {
            if (token.balanceOf(address(mint)) == 0) break;
            vm.roll(block.number + 1);
            try mint.swapTax() {
                swapped++;
            } catch {}
        }
        assertEq(token.balanceOf(address(mint)), 0, "pajak beli habis terjual semua");
        assertEq(swapped, 14, "PIN: 14x swapTax menghabiskan pajak beli 180 miliar");
        assertGt(token.totalDividends(), 0, "BNB hasil swap pajak masuk dividend pool");
        assertEq(feeTreasury.balance, 0, "feeTreasury tetap 0: pajak bukan buat tim");

        // --- Alice (holder) klaim di atas ambang minimum ---
        uint256 due = token.withdrawableDividendOf(alice);
        assertGe(due, token.MIN_DIVIDEND_CLAIM(), "dividen alice >= ambang 0,001 BNB");
        assertGt(token.withdrawableDividendOf(bob), 0, "bob (pembeli) juga terakru pro-rata");
        uint256 before = alice.balance;
        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, before + due, "klaim membayar PERSIS withdrawable");
        assertEq(token.withdrawableDividendOf(alice), 0, "tidak bisa klaim ganda");
    }
}
