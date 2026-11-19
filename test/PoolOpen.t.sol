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
        assertFalse(mint.opened(), "pool not open at deploy");
    }

    // v2: openEarly REMOVED (RT-02) — no more early pool-open path;
    // the pool ONLY opens when mint reaches OPEN_AT (tested below + ForkOpen).

    function test_PoolOpensAt168000Shares() public {
        _openPool(carol);
        assertTrue(mint.opened(), "pool opens at share 168.000");
        assertTrue(token.tradingEnabled(), "trading opens when pool opens");
        assertEq(mint.totalMinted(), 168_000, "total 168.000 share");
        (uint256 rBnb, uint256 rToken) = mint.reserves();
        assertEq(rBnb, mint.OPEN_BNB(), "reserve BNB = 225,792");
        assertEq(rToken, mint.OPEN_TOKENS(), "reserve token = 22,5792 trillion");
        assertEq(token.balanceOf(address(_pair())), mint.OPEN_TOKENS(), "pair holds pool tokens");
        assertEq(wbnb.balanceOf(address(_pair())), mint.OPEN_BNB(), "pair holds pool WBNB");
    }

    function test_LpBurnedToDead() public {
        _openPool(carol);
        MockPair p = _pair();
        assertEq(p.totalSupply(), 1000, "LP minted (mock: 1000)");
        assertEq(p.balanceOf(mint.DEAD()), 1000, "100% LP to DEAD");
        assertEq(p.balanceOf(address(mint)), 0, "minter holds no LP");
    }

    function test_EpochPriceRises2PercentPer16800Shares() public {
        assertEq(mint.priceUnits(168_000), 100, "flat up to share 168.000");
        assertEq(mint.priceUnits(168_001), 102, "epoch 1: +2%");
        assertEq(mint.priceUnits(184_800), 102, "epoch 1 up to share 184.800");
        assertEq(mint.priceUnits(184_801), 104, "epoch 2: +4%");
        assertEq(mint.priceUnits(201_600), 104, "epoch 2 up to share 201.600");
        // costOf mid epoch 1 (totalMinted = 168.000 -> next share 102).
        vm.store(address(mint), bytes32(uint256(0)), bytes32(uint256(168_000)));
        assertEq(mint.costOf(1), 0.00168 ether * 102 / 100, "1 share epoch 1 = 0,0017136");
    }

    function test_PriceCap2x() public {
        assertEq(mint.priceUnits(1_008_000), 200, "2x cap reached at share 1.008.000");
        assertEq(mint.priceUnits(1_008_001), 200, "stays 200 after cap");
        assertEq(mint.priceUnits(1_680_000), 200, "stays 200 until sold out");
        vm.store(address(mint), bytes32(uint256(0)), bytes32(uint256(1_007_999)));
        assertEq(mint.costOf(1), 0.00336 ether, "max price 0,00336 BNB (2x)");
        vm.store(address(mint), bytes32(uint256(0)), bytes32(uint256(1_500_000)));
        assertEq(mint.costOf(1), 0.00336 ether, "price flat at cap");
    }

    function test_MintCloses7DaysAfterOpenOr168kShares() public {
        _openPool(carol);
        assertFalse(mint.mintClosed(), "mint still open right when pool opens");
        vm.warp(vm.getBlockTimestamp() + 7 days + 1);
        assertTrue(mint.mintClosed(), "mint closes 7 days after pool opens");
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentMint.SoldOut.selector);
        mint.mint{value: cost}(1, address(0), cost);
    }

    function test_MintClosesAtTotalShares() public {
        _openPool(carol);
        vm.store(address(mint), bytes32(uint256(0)), bytes32(mint.TOTAL_SHARES()));
        assertTrue(mint.mintClosed(), "mint closes at 1.680.000 shares");
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
        assertEq(treasury.balance, 0, "treasury 0 before pool opens");
        assertEq(bob.balance, 100 ether, "referrer 0 before pool opens");

        _openPool(carol); // carol triggers with a 1-share mint, no referrer
        uint256 costTrigger = mint.BASE_PRICE();
        uint256 expectedTreasury = (costAlice + costTrigger) * 1_500 / 10_000;
        assertEq(treasury.balance, expectedTreasury, "treasury 15% paid ONCE when pool opens");
        assertEq(mint.escrowTreasury(), 0, "treasury escrow empty after _open");

        // Pre-pool referral stays claimable (PULL) after the pool opens.
        uint256 expectedRef = costAlice * 500 / 10_000;
        assertEq(mint.referralAccrued(bob), expectedRef, "alice 5% accrues for bob");
        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        mint.claimReferral();
        assertEq(bob.balance, bobBefore + expectedRef, "bob receives 5% commission");
        assertEq(mint.referralAccrued(bob), 0, "accrual depleted after claim");
    }

    function test_PostPoolTreasuryAccruesForClaim() public {
        _openPool(carol);
        // Post-pool mint: treasury is NOT paid directly (accumulate
        // + claim pattern, consistent with pre-pool), but accrues.
        uint256 cost = mint.costOf(1);
        uint256 treasuryBefore = treasury.balance;
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(treasury.balance, treasuryBefore, "treasury not paid instantly post-pool");
        uint256 accrued = mint.escrowTreasury();
        assertEq(accrued, cost * 1_500 / 10_000, "15% post-pool accrues");
        vm.prank(treasury);
        mint.claimTreasury();
        assertEq(treasury.balance, treasuryBefore + accrued, "treasury claims accrual");
        assertEq(mint.escrowTreasury(), 0, "escrow empty after claim");
    }

    function test_ClaimReferralBeforeOpenReverts() public {
        _mintAs(alice, 1, bob);
        assertGt(mint.referralAccrued(bob), 0, "accrual exists before pool opens");
        vm.prank(bob);
        vm.expectRevert(AgentMint.NotOpen.selector);
        mint.claimReferral();
    }
}
