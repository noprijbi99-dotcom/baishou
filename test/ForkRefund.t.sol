// SPDX-License-Identifier: MIT
// BAISHOU - FORK TEST jalur EXIT 80% + REFUND GAGAL 100% (skenario gabungan
// multi-user, angka persis). Bedanya dari RefundExit/RefundFail.t.sol:
// di sini exit parsial, exit penuh, dan minter yang tidak exit dicampur
// dalam SATU skenario, lalu launch digagalkan dan SETIAP klaim refund
// diverifikasi = deposits + forfeitOf sampai wei terakhir, termasuk bukti
// solvabilitas escrow di tengah jalan (saldo WBNB kontrak == total
// kewajiban refund) dan saldo akhir kontrak == 0.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract ForkRefundTest is BaishouTest {
    function _totalObligations() internal view returns (uint256) {
        return mint.deposits(alice) + mint.deposits(bob) + mint.deposits(carol)
            + mint.forfeitOf(alice) + mint.forfeitOf(bob) + mint.forfeitOf(carol);
    }

    function test_ExitThenFailRefundDepositsPlusForfeit() public {
        // --- Fase 1: tiga minter masuk (bob pakai referrer alice) ---
        _mintAs(alice, 100, address(0)); // 0,168 BNB
        _mintAs(bob, 50, alice); // 0,084 BNB, 5% terakru ke alice
        _mintAs(carol, 20, address(0)); // 0,0336 BNB
        assertEq(mint.referralAccrued(alice), 0.0042 ether, "referral bob 5% terakru ke alice");

        // --- Fase 2: exit — carol keluar PENUH, alice keluar PARSIAL ---
        uint256 carolBefore = carol.balance;
        vm.prank(carol);
        mint.exit(20);
        assertEq(carol.balance, carolBefore + 0.02688 ether, "exit carol: kembali 80% persis");
        assertEq(mint.forfeitOf(carol), 0.00672 ether, "forfeit carol 20% tercatat");

        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        mint.exit(40);
        assertEq(alice.balance, aliceBefore + 0.05376 ether, "exit alice 40: kembali 80% persis");
        assertEq(mint.forfeitOf(alice), 0.01344 ether, "forfeit alice 20% tercatat");
        assertEq(mint.deposits(alice), 0.1008 ether, "deposit alice sisa 60 share");
        assertEq(mint.deposits(bob), 0.084 ether, "deposit bob utuh");

        // --- Bukti solvabilitas di tengah jalan: saldo WBNB kontrak ==
        //     total kewajiban refund (deposits + forfeit semua user). ---
        assertEq(_totalObligations(), 0.20496 ether, "total kewajiban 0,20496 BNB");
        assertEq(
            wbnb.balanceOf(address(mint)),
            _totalObligations(),
            "escrow menutup 100% kewajiban refund"
        );
        assertEq(treasury.balance, 0, "treasury belum terima apa pun");

        // --- Fase 3: deadline lewat tanpa target -> launch GAGAL ---
        vm.warp(mint.failureTime() + 1);
        assertTrue(mint.saleFailed(), "launch gagal");

        // Referral tetap TIDAK bisa diklaim: pool tidak pernah buka.
        vm.prank(alice);
        vm.expectRevert(AgentMint.NotOpen.selector);
        mint.claimReferral();

        // --- Fase 4: setiap user klaim deposits + forfeitOf, persis ---
        uint256 a0 = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, a0 + 0.11424 ether, "refund alice = 0,1008 + 0,01344");

        uint256 b0 = bob.balance;
        vm.prank(bob);
        mint.claimRefund();
        assertEq(bob.balance, b0 + 0.084 ether, "refund bob = deposit penuh (tidak pernah exit)");

        uint256 c0 = carol.balance;
        vm.prank(carol);
        mint.claimRefund();
        assertEq(carol.balance, c0 + 0.00672 ether, "refund carol = forfeit saja (sudah exit penuh)");

        // Posisi akhir: semua kewajiban lunas, kontrak kosong.
        assertEq(_totalObligations(), 0, "kewajiban refund lunas semua");
        assertEq(wbnb.balanceOf(address(mint)), 0, "escrow kontrak kosong total");
        assertEq(treasury.balance, 0, "treasury tetap 0 pada launch gagal");
    }

    function test_ExitFullPositionWithReferrerUnwindsEscrow() public {
        // Minter dengan referrer exit PENUH: potongan treasury + referral
        // yang sudah terakru harus ikut mundur, bukan menggantung.
        _mintAs(alice, 168, bob);
        assertGt(mint.escrowTreasury(), 0, "escrow treasury terisi");
        assertGt(mint.referralAccrued(bob), 0, "akrual referral terisi");
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.exit(168);
        assertEq(alice.balance, before + 0.225792 ether, "exit 168: 80% dari 0,28224");
        assertEq(mint.escrowTreasury(), 0, "escrow treasury mundur ke 0");
        assertEq(mint.referralAccrued(bob), 0, "akrual referral mundur ke 0");
        assertEq(mint.pendingBnb(), 0, "pending BNB mundur ke 0");
        assertEq(mint.forfeitPool(), 0.056448 ether, "forfeit 20% utuh di pool kondisional");
        // Solvabilitas: yang tersisa di kontrak == forfeit (kewajiban
        // refund satu-satunya yang tersisa).
        assertEq(wbnb.balanceOf(address(mint)), mint.forfeitOf(alice), "sisa escrow == forfeit alice");
    }
}
