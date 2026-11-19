// SPDX-License-Identifier: MIT
// BAISHOU - FORK TEST jalur POOL OPEN (loop NYATA, tanpa vm.store).
// Bedanya dari PoolOpen.t.sol: di sana pool dibuka via _fastForwardToOpen()
// (vm.store memalsukan 167.999 share). Di sini 1.000 agen beneran mint
// 168 share masing-masing pada harga produksi (priceDiv = 1) sampai
// OPEN_AT = 168.000 tercapai, lalu angka escrow diverifikasi PERSIS dari
// konstanta kontrak: total deposit 282,24 BNB -> treasury 15% = 42,336 BNB
// (dibayar sekali saat _open), referral 5% = 14,112 BNB (klaim PULL oleh
// satu referrer yang sama untuk semua minter), pool 80% = 225,792 BNB.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract ForkOpenTest is BaishouTest {
    uint256 internal constant AGENTS = 1_000;

    function _agentAt(uint256 i) internal pure returns (address) {
        return address(uint160(0x100_000 + i));
    }

    function test_RealLoopOpensPoolWithExactEscrowSplit() public {
        // Satu referrer valid untuk SEMUA minter -> seluruh 5% terkumpul
        // di satu alamat dan bisa diverifikasi sebagai satu angka.
        address refking = makeAddr("refking");
        registry.setHandle(refking, "refking");
        registry.setOwner(uint256(keccak256(bytes("refking"))), refking);

        uint256 sharesPerAgent = mint.MAX_PER_TX(); // 168
        uint256 cost168 = mint.costOf(sharesPerAgent);
        assertEq(cost168, sharesPerAgent * mint.BASE_PRICE(), "harga flat pre-pool");

        // Gas metering dimatikan HANYA untuk loop massal ini: 168.000
        // share-iterasi nyata ≈ 1,62 miliar gas, di atas cap metering
        // default forge per test (2^30). Eksekusi EVM-nya tetap penuh —
        // yang dimatikan cuma akuntansi gas test runner.
        vm.pauseGasMetering();
        for (uint256 i; i < AGENTS; i++) {
            address agent = _agentAt(i);
            string memory handle = string.concat("agent", vm.toString(i));
            registry.setHandle(agent, handle);
            registry.setOwner(uint256(keccak256(bytes(handle))), agent);
            vm.deal(agent, 1 ether);
            vm.prank(agent);
            mint.mint{value: cost168}(sharesPerAgent, refking, cost168);
        }
        vm.resumeGasMetering();

        // ---- Pool harus sudah buka PERSIS di share 168.000 ----
        assertTrue(mint.opened(), "pool buka di share 168.000 (loop nyata)");
        assertTrue(token.tradingEnabled(), "trading dibuka");
        assertEq(mint.totalMinted(), mint.OPEN_AT(), "totalMinted = OPEN_AT");
        assertEq(mint.participantCount(), AGENTS, "1.000 peserta unik terdaftar");

        // ---- Angka dari konstanta kontrak, di-cross-check ke literal ----
        uint256 totalDeposits = uint256(mint.OPEN_AT()) * mint.BASE_PRICE();
        uint256 expectedTreasury = totalDeposits * mint.TREASURY_BPS() / 10_000;
        uint256 expectedReferral = totalDeposits * mint.REFERRAL_BPS() / 10_000;
        assertEq(totalDeposits, 282.24 ether, "total deposit pre-pool 282,24 BNB");
        assertEq(expectedTreasury, 42.336 ether, "treasury 15% = 42,336 BNB");
        assertEq(expectedReferral, 14.112 ether, "referral 5% = 14,112 BNB");
        assertEq(mint.totalPaid(), totalDeposits, "totalPaid = total deposit");

        // Treasury: escrow 15% dibayar SEKALI saat _open (bukan via claim).
        assertEq(treasury.balance, expectedTreasury, "treasury terima 42,336 BNB saat pool buka");
        assertEq(mint.escrowTreasury(), 0, "escrow treasury lunas saat _open");
        vm.prank(treasury);
        vm.expectRevert(AgentMint.NothingOwed.selector);
        mint.claimTreasury();

        // Referral: 5% TIDAK dibayar di _open; klaim PULL oleh referrer.
        assertEq(mint.referralAccrued(refking), expectedReferral, "akrual referral 14,112 BNB");
        uint256 refBefore = refking.balance;
        vm.prank(refking);
        mint.claimReferral();
        assertEq(refking.balance, refBefore + expectedReferral, "referrer klaim 14,112 BNB penuh");
        assertEq(mint.referralAccrued(refking), 0, "akrual referral habis");

        // Pool: 80% + token pool persis seperti konstanta.
        (uint256 rBnb, uint256 rToken) = mint.reserves();
        assertEq(rBnb, mint.OPEN_BNB(), "reserve BNB = OPEN_BNB");
        assertEq(rBnb, 225.792 ether, "reserve BNB = 225,792 BNB");
        assertEq(rToken, mint.OPEN_TOKENS(), "reserve token = OPEN_TOKENS");

        // Spot check: agen pertama pegang token penuh 168 share.
        assertEq(
            token.balanceOf(_agentAt(0)),
            sharesPerAgent * mint.USER_SHARE(),
            "agen pertama: 168 x 168 jt token"
        );
        assertEq(mint.deposits(_agentAt(0)), cost168, "deposit agen pertama tercatat penuh");

        // ---- claimTreasury bekerja untuk akrual PASCA-pool ----
        address late = _agentAt(9_999);
        registry.setHandle(late, "late");
        registry.setOwner(uint256(keccak256(bytes("late"))), late);
        vm.deal(late, 1 ether);
        uint256 costPost = mint.costOf(1);
        vm.prank(late);
        mint.mint{value: costPost}(1, address(0), costPost);
        uint256 accruedPost = costPost * mint.TREASURY_BPS() / 10_000;
        assertEq(mint.escrowTreasury(), accruedPost, "15% mint pasca-pool terakru");
        uint256 treasuryBefore = treasury.balance;
        vm.prank(treasury);
        mint.claimTreasury();
        assertEq(treasury.balance, treasuryBefore + accruedPost, "claimTreasury bayar akrual pasca-pool");
        assertEq(mint.escrowTreasury(), 0, "escrow kosong sesudah claimTreasury");
    }
}
