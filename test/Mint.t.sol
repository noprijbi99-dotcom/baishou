// SPDX-License-Identifier: MIT
// BAISHOU - the MINT path (pre-pool flat + epoch curve + free + gate).
// FINAL design: POLA-BARU-ARUNIKA.md §2/§3 - the first 168.000 shares
// @ 0,00168 BNB flat, 168.000.000 tokens/share; after that epoch +2% per
// 16.800 shares, cap 0,00336 (2x). ID-only gate for the ENTIRE sale.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";

contract MintTest is BaishouTest {
    function test_FlatPricePrePool() public view {
        assertEq(mint.costOf(1), 0.00168 ether, "1 share pre-pool = 0,00168 BNB");
        assertEq(mint.costOf(168), 168 * 0.00168 ether, "harga flat s.d. 168.000 share");
        assertEq(mint.priceUnits(1), 100, "units flat pre-pool");
        assertEq(mint.priceUnits(168_000), 100, "units flat di share terakhir pre-pool");
    }

    function test_Cap168PerAddress() public {
        uint256 cost = mint.costOf(168);
        vm.prank(alice);
        mint.mint{value: cost}(168, address(0), cost);
        assertEq(mint.mintedCount(ALICE_ID), 168, "cap tercapai");
        uint256 cost1 = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentMint.Quota.selector);
        mint.mint{value: cost1}(1, address(0), cost1);
    }

    function test_MaxPerTxEqualsCap() public {
        uint256 cost = mint.costOf(169);
        vm.prank(alice);
        vm.expectRevert(AgentMint.BadShares.selector);
        mint.mint{value: cost}(169, address(0), cost);
    }

    function test_ReferralNotPaidInstantly() public {
        uint256 cost = mint.costOf(1);
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        mint.mint{value: cost}(1, bob, cost);
        assertEq(bob.balance, bobBefore, "referral ditahan escrow sampai pool buka");
        assertEq(mint.referralAccrued(bob), cost * 500 / 10_000, "5% terakru buat referrer");
        assertEq(mint.escrowTreasury(), cost * 1_500 / 10_000, "15% terakru buat treasury");
        assertEq(mint.pendingBnb(), cost * 8_000 / 10_000, "80% ke pool");
    }

    function test_TreasuryNotPaidInstantly() public {
        uint256 cost = mint.costOf(1);
        uint256 treasuryBefore = treasury.balance;
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(treasury.balance, treasuryBefore, "treasury ditahan escrow sampai pool buka");
        assertEq(mint.escrowTreasury(), cost * 1_500 / 10_000, "15% terakru");
        // Without a valid referrer, the 5% referral falls to the pool: pending = 85%.
        assertEq(mint.pendingBnb(), cost * 8_500 / 10_000, "85% ke pool tanpa referrer");
    }

    function test_ReferralToSelfOrStrangerFallsToPool() public {
        // Referrer = self -> invalid -> 5% to the pool.
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        mint.mint{value: cost}(1, alice, cost);
        assertEq(mint.referralAccrued(alice), 0, "self-referral tidak dapat komisi");
        assertEq(mint.pendingBnb(), cost * 8_500 / 10_000, "5% jatuh ke pool");
        // Referrer without an Agent ID -> invalid -> 5% to the pool.
        uint256 cost2 = mint.costOf(1);
        vm.prank(bob);
        mint.mint{value: cost2}(1, stranger, cost2);
        assertEq(mint.referralAccrued(stranger), 0, "stranger bukan referrer valid");
    }

    // The 24-hour gate + opening to all wallets was CANCELLED 19 Nov 06:20 UTC.
    // The gate is FULLY Agent ID-only for the whole sale: a stranger reverts
    // NoAgent ALWAYS — after 24 hours, after 30 days, after the pool opens.
    function test_GateIdOnlyForever() public {
        uint256 cost = mint.costOf(1);
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NoAgent.selector);
        mint.mint{value: cost}(1, address(0), cost);

        vm.warp(vm.getBlockTimestamp() + 24 hours + 1);
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NoAgent.selector);
        mint.mint{value: cost}(1, address(0), cost);

        vm.warp(vm.getBlockTimestamp() + 5 days);
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NoAgent.selector);
        mint.mint{value: cost}(1, address(0), cost);

        // Agent ID holders can still mint at any time while the sale runs.
        _mintAs(alice, 1, address(0));
        assertEq(mint.mintedCount(ALICE_ID), 1, "Agent ID tetap bisa mint");

        // Even after the pool opens, a stranger still cannot mint.
        _openPool(bob);
        uint256 costPost = mint.costOf(1);
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NoAgent.selector);
        mint.mint{value: costPost}(1, address(0), costPost);
    }

    function test_FreeMintOnePerAgentId() public {
        uint256 aliceBefore = alice.balance;
        vm.prank(alice);
        mint.freeMint();
        assertEq(token.balanceOf(alice), 168_000_000 ether, "free = 168.000.000 token");
        assertEq(alice.balance, aliceBefore, "free tanpa BNB");
        assertEq(mint.freeClaimed(), 1, "1 klaim tercatat");
        assertTrue(mint.claimedFree(ALICE_ID), "alice sudah klaim");

        vm.prank(alice);
        vm.expectRevert(AgentMint.AlreadyGranted.selector);
        mint.freeMint();

        vm.prank(stranger);
        vm.expectRevert(AgentMint.NoAgent.selector);
        mint.freeMint();
    }

    function test_FreeMintDoesNotReduceBuyCap() public {
        vm.prank(alice);
        mint.freeMint();
        assertEq(mint.mintedCount(ALICE_ID), 0, "free tidak menambah mintedCount");
        uint256 cost = mint.costOf(168);
        vm.prank(alice);
        mint.mint{value: cost}(168, address(0), cost);
        assertEq(mint.mintedCount(ALICE_ID), 168, "tetap bisa mint 168 penuh");
        assertEq(token.balanceOf(alice), 169 * 168_000_000 ether, "free + 168 paid");
    }

    function test_FreeMintBlockedWhenPaused() public {
        vm.prank(admin);
        mint.setPaused(true);
        vm.prank(alice);
        vm.expectRevert(AgentMint.Paused.selector);
        mint.freeMint();
    }

    function test_Cap168IncludesTeamDeployer() public {
        // The admin (deployer) is subject to the same cap: give him an Agent ID, then
        // 168 is allowed, +1 reverts Quota. No shortcut for the team.
        registry.setHandle(admin, "admin");
        registry.setOwner(uint256(keccak256(bytes("admin"))), admin);
        vm.deal(admin, 100 ether);
        uint256 cost = mint.costOf(168);
        vm.prank(admin);
        mint.mint{value: cost}(168, address(0), cost);
        assertEq(mint.mintedCount(uint256(keccak256(bytes("admin")))), 168, "admin mentok 168");
        uint256 cost1 = mint.costOf(1);
        vm.prank(admin);
        vm.expectRevert(AgentMint.Quota.selector);
        mint.mint{value: cost1}(1, address(0), cost1);
    }

    function test_Fixed168MAfterPoolOpen() public {
        _openPool(carol);
        // Bob never minted: 1 post-pool share, the price has risen
        // (epoch 1 -> 102 units), but tokens stay 168.000.000/share.
        uint256 cost = mint.costOf(1);
        assertGt(cost, 0.00168 ether, "harga pasca-pool naik dari flat");
        vm.prank(bob);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(token.balanceOf(bob), 168_000_000 ether, "tetap 168 jt/share walau harga naik");
    }

    function test_MaxSupplyRevert() public {
        // MAX_SUPPLY backstop: totalSupply already at the cap threshold -> the next
        // mint (which mints POOL_SHARE to the contract) reverts SupplyCap.
        bytes32 supplySlot = bytes32(uint256(2));
        vm.store(address(token), supplySlot, bytes32(mint.MAX_SUPPLY() - 1));
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentToken.SupplyCap.selector);
        mint.mint{value: cost}(1, address(0), cost);
    }
}
