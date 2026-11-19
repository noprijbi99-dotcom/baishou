// SPDX-License-Identifier: MIT
// BAISHOU - the POOL OPEN path (pool opens at share 168.000).
// FINAL design: the pool opens automatically at share 168.000: 225,792 BNB +
// 22,5792 trillion tokens; LP 100% to DEAD; trading opens; mint continues on
// the epoch curve; mint closes 7 days after the pool opens OR 1.680.000 shares.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockPair} from "./mocks/Mocks.sol";

contract PoolOpenTest is BaishouTest {
    function test_PoolNotOpenInitially() public view {
        assertFalse(mint.opened(), "pool belum buka saat deploy");
    }

    // v2: openEarly REMOVED (RT-02) — no more early pool-open path;
    // the pool ONLY opens when mint reaches OPEN_AT (tested below + ForkOpen).

    function test_PoolOpensAt168000Shares() public {
        _openPool(carol);
        assertTrue(mint.opened(), "pool buka di share 168.000");
        assertTrue(token.tradingEnabled(), "trading dibuka saat pool buka");
        assertEq(mint.totalMinted(), 168_000, "total 168.000 share");
        (uint256 rBnb, uint256 rToken) = mint.reserves();
        assertEq(rBnb, mint.OPEN_BNB(), "reserve BNB = 225,792");
        assertEq(rToken, mint.OPEN_TOKENS(), "reserve token = 22,5792 triliun");
        assertEq(token.balanceOf(address(_pair())), mint.OPEN_TOKENS(), "pair pegang token pool");
        assertEq(wbnb.balanceOf(address(_pair())), mint.OPEN_BNB(), "pair pegang WBNB pool");
    }

    function test_LpBurnedToDead() public {
        _openPool(carol);
        MockPair p = _pair();
        assertEq(p.totalSupply(), 1000, "LP tercetak (mock: 1000)");
        assertEq(p.balanceOf(mint.DEAD()), 1000, "100% LP ke DEAD");
        assertEq(p.balanceOf(address(mint)), 0, "minter tidak pegang LP");
    }

    function test_EpochPriceRises2PercentPer16800Shares() public {
        assertEq(mint.priceUnits(168_000), 100, "flat sampai share 168.000");
        assertEq(mint.priceUnits(168_001), 102, "epoch 1: +2%");
        assertEq(mint.priceUnits(184_800), 102, "epoch 1 sampai share 184.800");
        assertEq(mint.priceUnits(184_801), 104, "epoch 2: +4%");
        assertEq(mint.priceUnits(201_600), 104, "epoch 2 sampai share 201.600");
        // costOf mid epoch 1 (totalMinted = 168.000 -> next share 102).
        vm.store(address(mint), bytes32(uint256(0)), bytes32(uint256(168_000)));
        assertEq(mint.costOf(1), 0.00168 ether * 102 / 100, "1 share epoch 1 = 0,0017136");
    }

    function test_PriceCap2x() public {
        assertEq(mint.priceUnits(1_008_000), 200, "cap 2x tercapai di share 1.008.000");
        assertEq(mint.priceUnits(1_008_001), 200, "tetap 200 sesudah cap");
        assertEq(mint.priceUnits(1_680_000), 200, "tetap 200 sampai sold out");
        vm.store(address(mint), bytes32(uint256(0)), bytes32(uint256(1_007_999)));
        assertEq(mint.costOf(1), 0.00336 ether, "harga max 0,00336 BNB (2x)");
        vm.store(address(mint), bytes32(uint256(0)), bytes32(uint256(1_500_000)));
        assertEq(mint.costOf(1), 0.00336 ether, "harga datar di cap");
    }

    function test_MintCloses7DaysAfterOpenOr168kShares() public {
        _openPool(carol);
        assertFalse(mint.mintClosed(), "mint masih buka tepat saat pool buka");
        vm.warp(vm.getBlockTimestamp() + 7 days + 1);
        assertTrue(mint.mintClosed(), "mint tutup 7 hari sesudah pool buka");
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentMint.SoldOut.selector);
        mint.mint{value: cost}(1, address(0), cost);
    }

    function test_MintClosesAtTotalShares() public {
        _openPool(carol);
        vm.store(address(mint), bytes32(uint256(0)), bytes32(mint.TOTAL_SHARES()));
        assertTrue(mint.mintClosed(), "mint tutup saat 1.680.000 share");
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentMint.SoldOut.selector);
        mint.mint{value: cost}(1, address(0), cost);
    }

    function test_OnePairOnly() public {
        _openPool(carol);
        // A fake pair (another MockPair token/WBNB) is rejected on transfer.
        MockPair fake = new MockPair(address(token), address(wbnb));
        address fakeAddr = address(fake);
        address pairAddr = address(_pair());
        vm.prank(alice);
        vm.expectRevert(AgentToken.PoolRejected.selector);
        token.transfer(fakeAddr, 1 ether);
        // The official pair cannot be blocked by the admin.
        vm.prank(admin);
        vm.expectRevert(AgentMint.NotBlockable.selector);
        mint.setPoolBlocked(pairAddr, true);
    }

    function test_TreasuryAndReferralPaidAtOpen() public {
        // Alice mints 10 shares with referrer bob (pre-pool, real).
        uint256 costAlice = mint.costOf(10);
        vm.prank(alice);
        mint.mint{value: costAlice}(10, bob, costAlice);
        assertEq(treasury.balance, 0, "treasury 0 sebelum pool buka");
        assertEq(bob.balance, 100 ether, "referrer 0 sebelum pool buka");

        _openPool(carol); // carol triggers with a 1-share mint, no referrer
        uint256 costTrigger = mint.BASE_PRICE();
        uint256 expectedTreasury = (costAlice + costTrigger) * 1_500 / 10_000;
        assertEq(treasury.balance, expectedTreasury, "treasury 15% dibayar SEKALI saat pool buka");
        assertEq(mint.escrowTreasury(), 0, "escrow treasury kosong sesudah _open");

        // Pre-pool referral stays claimable (PULL) after the pool opens.
        uint256 expectedRef = costAlice * 500 / 10_000;
        assertEq(mint.referralAccrued(bob), expectedRef, "5% alice terakru buat bob");
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        mint.claimReferral();
        assertEq(bob.balance, bobBefore + expectedRef, "bob terima komisi 5%");
        assertEq(mint.referralAccrued(bob), 0, "akrual habis sesudah klaim");
    }

    function test_PostPoolTreasuryAccruesForClaim() public {
        _openPool(carol);
        // Post-pool mint: treasury is NOT paid directly (accumulate
        // + claim pattern, consistent with pre-pool), but accrues.
        uint256 cost = mint.costOf(1);
        uint256 treasuryBefore = treasury.balance;
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(treasury.balance, treasuryBefore, "treasury tidak dibayar instan pasca-pool");
        uint256 accrued = mint.escrowTreasury();
        assertEq(accrued, cost * 1_500 / 10_000, "15% pasca-pool terakru");
        vm.prank(treasury);
        mint.claimTreasury();
        assertEq(treasury.balance, treasuryBefore + accrued, "treasury klaim akrual");
        assertEq(mint.escrowTreasury(), 0, "escrow kosong sesudah klaim");
    }

    function test_ClaimReferralBeforeOpenReverts() public {
        _mintAs(alice, 1, bob);
        assertGt(mint.referralAccrued(bob), 0, "akrual ada sebelum pool buka");
        vm.prank(bob);
        vm.expectRevert(AgentMint.NotOpen.selector);
        mint.claimReferral();
    }
}
