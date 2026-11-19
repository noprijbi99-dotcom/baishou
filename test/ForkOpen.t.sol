// SPDX-License-Identifier: MIT
// BAISHOU - FORK TEST of the POOL OPEN path (REAL loop, no vm.store).
// Unlike PoolOpen.t.sol: there the pool was opened via _fastForwardToOpen()
// (vm.store fakes 167.999 shares). Here 1.000 agents really mint
// 168 shares each at the production price (priceDiv = 1) until
// OPEN_AT = 168.000 is reached, then the escrow numbers are verified EXACTLY from
// contract constants: total deposits 282,24 BNB -> treasury 15% = 42,336 BNB
// (paid once at _open), referral 5% = 14,112 BNB (PULL claim by
// one and the same referrer for all minters), pool 80% = 225,792 BNB.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract ForkOpenTest is BaishouTest {
    uint256 internal constant AGENTS = 1_000;

    function _agentAt(uint256 i) internal pure returns (address) {
        return address(uint160(0x100_000 + i));
    }

    function test_RealLoopOpensPoolWithExactEscrowSplit() public {
        // One valid referrer for ALL minters -> the entire 5% accumulates
        // at one address and can be verified as a single number.
        address refking = makeAddr("refking");
        registry.setHandle(refking, "refking");
        registry.setOwner(uint256(keccak256(bytes("refking"))), refking);

        uint256 sharesPerAgent = mint.MAX_PER_TX(); // 168
        uint256 cost168 = mint.costOf(sharesPerAgent);
        assertEq(cost168, sharesPerAgent * mint.BASE_PRICE(), "harga flat pre-pool");

        // Gas metering is disabled ONLY for this mass loop: 168.000
        // real share-iterations ≈ 1,62 billion gas, above the default forge
        // per-test metering cap (2^30). The EVM execution is still complete —
        // only the test runner's gas accounting is disabled.
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

        // ---- The pool must already be open EXACTLY at share 168.000 ----
        assertTrue(mint.opened(), "pool buka di share 168.000 (loop nyata)");
        assertTrue(token.tradingEnabled(), "trading dibuka");
        assertEq(mint.totalMinted(), mint.OPEN_AT(), "totalMinted = OPEN_AT");
        assertEq(mint.participantCount(), AGENTS, "1.000 peserta unik terdaftar");

        // ---- Numbers from contract constants, cross-checked against literals ----
        uint256 totalDeposits = uint256(mint.OPEN_AT()) * mint.BASE_PRICE();
        uint256 expectedTreasury = totalDeposits * mint.TREASURY_BPS() / 10_000;
        uint256 expectedReferral = totalDeposits * mint.REFERRAL_BPS() / 10_000;
        assertEq(totalDeposits, 282.24 ether, "total deposit pre-pool 282,24 BNB");
        assertEq(expectedTreasury, 42.336 ether, "treasury 15% = 42,336 BNB");
        assertEq(expectedReferral, 14.112 ether, "referral 5% = 14,112 BNB");
        assertEq(mint.totalPaid(), totalDeposits, "totalPaid = total deposit");

        // Treasury: the 15% escrow is paid ONCE at _open (not via claim).
        assertEq(treasury.balance, expectedTreasury, "treasury terima 42,336 BNB saat pool buka");
        assertEq(mint.escrowTreasury(), 0, "escrow treasury lunas saat _open");
        vm.prank(treasury);
        vm.expectRevert(AgentMint.NothingOwed.selector);
        mint.claimTreasury();

        // Referral: the 5% is NOT paid at _open; PULL claim by the referrer.
        assertEq(mint.referralAccrued(refking), expectedReferral, "akrual referral 14,112 BNB");
        uint256 refBefore = refking.balance;
        vm.prank(refking);
        mint.claimReferral();
        assertEq(refking.balance, refBefore + expectedReferral, "referrer klaim 14,112 BNB penuh");
        assertEq(mint.referralAccrued(refking), 0, "akrual referral habis");

        // Pool: 80% + pool tokens exactly as the constants.
        (uint256 rBnb, uint256 rToken) = mint.reserves();
        assertEq(rBnb, mint.OPEN_BNB(), "reserve BNB = OPEN_BNB");
        assertEq(rBnb, 225.792 ether, "reserve BNB = 225,792 BNB");
        assertEq(rToken, mint.OPEN_TOKENS(), "reserve token = OPEN_TOKENS");

        // Spot check: the first agent holds the full tokens of 168 shares.
        assertEq(
            token.balanceOf(_agentAt(0)),
            sharesPerAgent * mint.USER_SHARE(),
            "agen pertama: 168 x 168 jt token"
        );
        assertEq(mint.deposits(_agentAt(0)), cost168, "deposit agen pertama tercatat penuh");

        // ---- claimTreasury works for POST-pool accrual ----
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
