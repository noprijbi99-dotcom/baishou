// SPDX-License-Identifier: MIT
// BAISHOU - FORK TEST jalur DIVIDEN dari SWAP NYATA lewat pair.
// Bedanya dari Dividend.t.sol: di sana dividen kebanyakan disetor langsung
// (prank depositDividends) atau pajak disimulasikan via transfer biasa.
// Di sini rantainya PENUH seperti produksi:
//   pool dibuka kecil via openEarly -> bob BELI token lewat pair.swap()
//   (pajak beli 2% masuk minter) -> swapTax() berulang menjual token pajak
//   jadi BNB -> BNB masuk dividend pool -> holder (alice) claimDividend()
//   di atas ambang minimum 0,001 BNB, dengan delta saldo PERSIS sama
//   dengan withdrawableDividendOf sesaat sebelum klaim.
// Pool dibuka kecil SENGAJA: pada skala produksi (168.000 share) dividen
// per holder memang debu (lihat catatan jujur di Dividend.t.sol) —
// di sini fraksi supply alice besar supaya ambang 0,001 BNB terjangkau
// oleh pajak swap beneran, bukan setoran artifisial.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {MockPair} from "./mocks/Mocks.sol";

contract ForkDividendTest is BaishouTest {
    function test_SwapTaxToDividendClaimEndToEnd() public {
        // --- Pool buka kecil: alice 168 share, openEarly oleh admin ---
        _mintAs(alice, 168, address(0));
        vm.prank(admin);
        mint.openEarly();
        assertTrue(mint.opened(), "pool buka via openEarly");
        // Escrow treasury 15% dari 0,28224 dibayar saat _open.
        assertEq(treasury.balance, 0.042336 ether, "treasury 15% dibayar saat openEarly");
        (uint256 rBnb0, uint256 rToken0) = mint.reserves();
        assertEq(rBnb0, 0.239904 ether, "pool BNB = 85% x 0,28224 (tanpa referrer)");
        assertEq(rToken0, 168 * mint.POOL_SHARE(), "pool token = 168 x POOL_SHARE");

        // --- Bob BELI lewat pair.swap(): WBNB masuk, token keluar ---
        MockPair pair = _pair();
        address pairAddr = address(pair);
        vm.prank(bob);
        wbnb.deposit{value: 1 ether}();
        vm.prank(bob);
        wbnb.transfer(pairAddr, 0.2125 ether);
        uint256 buyOut = 20_000_000_000 ether; // 20 miliar token dari pool
        (uint256 out0, uint256 out1) =
            pair.token0() == address(token) ? (buyOut, uint256(0)) : (uint256(0), buyOut);
        pair.swap(out0, out1, bob, "");
        assertEq(token.balanceOf(bob), buyOut * 9_800 / 10_000, "bob terima 98% (pajak beli 2%)");
        assertEq(token.balanceOf(address(mint)), buyOut * 200 / 10_000, "pajak beli 2% di minter");

        // --- swapTax() berulang (satu per blok): token pajak -> BNB ->
        //     dividend pool. Bukan setoran langsung. ---
        uint256 swapped;
        for (uint256 i; i < 12; i++) {
            vm.roll(block.number + 1);
            try mint.swapTax() {
                swapped++;
            } catch {}
        }
        assertEq(swapped, 12, "12x swapTax berhasil");
        assertGt(token.totalDividends(), 0, "BNB hasil swap pajak masuk dividend pool");
        assertEq(feeTreasury.balance, 0, "feeTreasury tetap 0: pajak bukan buat tim");

        // --- Alice (holder terbesar) klaim di atas ambang minimum ---
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
