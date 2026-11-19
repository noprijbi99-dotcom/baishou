// SPDX-License-Identifier: MIT
// BAISHOU - jalur DIVIDEN holder (pajak trading 2%/2% -> 1% burn + 1% dividen).
// Desain FINAL: dividen pro-rata per token via accumulator claims
// (magnifiedDividendPerShare). Pajak beli 2% + pajak jual 1% kept masuk
// minter, lalu swapTax() jual jadi BNB -> DIVIDEND POOL token (0% ke tim).
// ⚠️ JUJUR: dividen adalah DEBU - volume 100 BNB/bulan -> holder cap
// ~$0,06/bulan. Dividen TIDAK PERNAH dijanjikan sebagai penghasilan.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";

contract DividendTest is BaishouTest {
    function test_SellTaxSplitBurnAndDividend() public {
        _mintAs(alice, 10, address(0));
        _openPool(carol);
        uint256 sellAmount = 1_000_000 ether;
        uint256 deadBefore = token.balanceOf(mint.DEAD());
        uint256 minterBefore = token.balanceOf(address(mint));
        address pairAddr = address(_pair());
        vm.prank(alice);
        token.transfer(pairAddr, sellAmount);
        assertEq(token.balanceOf(mint.DEAD()), deadBefore + sellAmount * 100 / 10_000, "jual 1% burn");
        assertEq(
            token.balanceOf(address(mint)),
            minterBefore + sellAmount * 100 / 10_000,
            "jual 1% kept ke minter (dividend pool, bukan feeTreasury)"
        );
        assertEq(token.balanceOf(feeTreasury), 0, "feeTreasury tidak terima pajak");
    }

    function test_BuyTaxGoesToDividendPool() public {
        _mintAs(alice, 10, address(0));
        _openPool(carol);
        // Simulasi beli: pair -> alice, 2% dipotong ke minter.
        uint256 buyAmount = 1_000_000 ether;
        uint256 minterBefore = token.balanceOf(address(mint));
        vm.prank(address(_pair()));
        token.transfer(alice, buyAmount);
        assertEq(token.balanceOf(alice), buyAmount * 9_800 / 10_000 + 10 * 168_000_000 ether, "alice terima 98%");
        assertEq(
            token.balanceOf(address(mint)), minterBefore + buyAmount * 200 / 10_000, "beli 2% ke minter"
        );

        // swapTax(): token pajak dijual jadi BNB -> masuk DIVIDEND POOL
        // token, BUKAN ke feeTreasury. Reserves di-sync dulu karena
        // simulasi beli di atas adalah transfer biasa (bukan swap).
        _pair().sync();
        uint256 feeBefore = feeTreasury.balance;
        uint256 divBefore = token.totalDividends();
        vm.prank(alice);
        mint.swapTax();
        assertEq(feeTreasury.balance, feeBefore, "feeTreasury 0 dari swap pajak");
        assertGt(token.totalDividends(), divBefore, "BNB hasil swap masuk dividend pool");
    }

    function test_DividendAccruesProRata() public {
        _mintAs(alice, 2, address(0)); // 336 jt token
        _mintAs(bob, 1, address(0)); // 168 jt token
        _openPool(carol);
        // Setor dividen langsung via minter (1 BNB) untuk menguji accumulator.
        vm.deal(address(mint), 100 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 100 ether}();
        uint256 aliceWd = token.withdrawableDividendOf(alice);
        uint256 bobWd = token.withdrawableDividendOf(bob);
        assertGt(aliceWd, 0, "alice dapat dividen");
        assertGt(bobWd, 0, "bob dapat dividen");
        assertApproxEqAbs(aliceWd, 2 * bobWd, 10, "alice 2x bob (pro-rata token)");
        // Yang beli sesudah setoran tidak dapat dividen periode lalu:
        // carol (trigger mint 1 share) punya token, tapi ia mint SEBELUM
        // setoran — cek pendatang baru sesudah setoran.
        assertEq(token.withdrawableDividendOf(stranger), 0, "non-holder 0");
    }

    function test_DividendClaimDoesNotRequireSell() public {
        _mintAs(alice, 2, address(0));
        _openPool(carol);
        vm.deal(address(mint), 100 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 100 ether}();
        uint256 due = token.withdrawableDividendOf(alice);
        assertGe(due, token.MIN_DIVIDEND_CLAIM(), "akrual alice di atas min klaim");
        uint256 before = alice.balance;
        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, before + due, "klaim transfer BNB dividen");
        assertEq(token.withdrawableDividendOf(alice), 0, "habis diklaim");
        // Klaim berulang hanya membayar akumulasi BARU sejak klaim terakhir.
        vm.deal(address(mint), 100 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 100 ether}();
        uint256 due2 = token.withdrawableDividendOf(alice);
        assertGt(due2, 0, "akrual baru muncul");
        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, before + due + due2, "klaim ke-2 = akrual baru saja");
    }

    function test_DividendMinClaim() public {
        _mintAs(alice, 1, address(0));
        _openPool(carol);
        // Setoran debu: withdrawable alice di bawah 0,001 BNB -> revert,
        // tapi TIDAK hangus (tetap terakumulasi).
        vm.deal(address(mint), 0.0001 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 0.0001 ether}();
        uint256 due = token.withdrawableDividendOf(alice);
        assertGt(due, 0, "debu tetap terakumulasi");
        assertLt(due, token.MIN_DIVIDEND_CLAIM(), "debu di bawah min klaim");
        vm.prank(alice);
        vm.expectRevert(AgentToken.DividendTooSmall.selector);
        token.claimDividend();
        assertEq(token.withdrawableDividendOf(alice), due, "gagal klaim tidak menghanguskan");
        // Tambah setoran sampai melewati ambang -> klaim berhasil.
        vm.deal(address(mint), 1000 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 1000 ether}();
        assertGe(token.withdrawableDividendOf(alice), token.MIN_DIVIDEND_CLAIM(), "kini di atas ambang");
        vm.prank(alice);
        token.claimDividend();
        assertEq(token.withdrawableDividendOf(alice), 0, "habis diklaim");
    }

    function test_DividendNotDoubleClaimable() public {
        _mintAs(alice, 1, address(0));
        _openPool(carol);
        vm.deal(address(mint), 1000 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 1000 ether}();
        vm.prank(alice);
        token.claimDividend();
        vm.prank(alice);
        vm.expectRevert(AgentToken.DividendTooSmall.selector);
        token.claimDividend();
    }
}
