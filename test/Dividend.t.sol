// SPDX-License-Identifier: MIT
// BAISHOU - the holder DIVIDEND path (trading tax 2%/2% -> 1% burn + 1% dividend).
// FINAL design: pro-rata dividends per token via accumulator claims
// (magnifiedDividendPerShare). The 2% buy tax + 1% kept sell tax go to the
// minter, then swapTax() sells them for BNB -> the token DIVIDEND POOL (0% to the team).
// ⚠️ HONEST: dividends are DUST - volume of 100 BNB/month -> holder cap
// ~$0,06/month. Dividends are NEVER promised as income.
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
        assertEq(token.balanceOf(mint.DEAD()), deadBefore + sellAmount * 100 / 10_000, "sell 1% burn");
        assertEq(
            token.balanceOf(address(mint)),
            minterBefore + sellAmount * 100 / 10_000,
            "sell 1% kept to minter (dividend pool, not feeTreasury)"
        );
        assertEq(token.balanceOf(feeTreasury), 0, "feeTreasury receives no tax");
    }

    function test_BuyTaxGoesToDividendPool() public {
        _mintAs(alice, 10, address(0));
        _openPool(carol);
        // Simulated buy: pair -> alice, 2% cut to the minter.
        uint256 buyAmount = 1_000_000 ether;
        uint256 minterBefore = token.balanceOf(address(mint));
        vm.prank(address(_pair()));
        token.transfer(alice, buyAmount);
        assertEq(token.balanceOf(alice), buyAmount * 9_800 / 10_000 + 10 * 168_000_000 ether, "alice receives 98%");
        assertEq(
            token.balanceOf(address(mint)), minterBefore + buyAmount * 200 / 10_000, "buy 2% to minter"
        );

        // swapTax(): the tax tokens are sold for BNB -> into the token
        // DIVIDEND POOL, NOT to feeTreasury. Reserves are synced first because
        // the simulated buy above is a plain transfer (not a swap).
        _pair().sync();
        uint256 feeBefore = feeTreasury.balance;
        uint256 divBefore = token.totalDividends();
        vm.prank(alice);
        mint.swapTax();
        assertEq(feeTreasury.balance, feeBefore, "feeTreasury 0 from tax swap");
        assertGt(token.totalDividends(), divBefore, "BNB from swap enters dividend pool");
    }

    function test_DividendAccruesProRata() public {
        _mintAs(alice, 2, address(0)); // 336M tokens
        _mintAs(bob, 1, address(0)); // 168M tokens
        _openPool(carol);
        // Direct dividend deposit via the minter (1 BNB) to test the accumulator.
        vm.deal(address(mint), 100 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 100 ether}();
        uint256 aliceWd = token.withdrawableDividendOf(alice);
        uint256 bobWd = token.withdrawableDividendOf(bob);
        assertGt(aliceWd, 0, "alice gets dividend");
        assertGt(bobWd, 0, "bob gets dividend");
        assertApproxEqAbs(aliceWd, 2 * bobWd, 10, "alice 2x bob (pro-rata token)");
        // Buyers after a deposit get no dividends from the earlier period:
        // carol (trigger mint of 1 share) holds tokens, but she minted BEFORE
        // the deposit — check a newcomer after the deposit.
        assertEq(token.withdrawableDividendOf(stranger), 0, "non-holder 0");
    }

    function test_DividendClaimDoesNotRequireSell() public {
        _mintAs(alice, 2, address(0));
        _openPool(carol);
        vm.deal(address(mint), 100 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 100 ether}();
        uint256 due = token.withdrawableDividendOf(alice);
        assertGe(due, token.MIN_DIVIDEND_CLAIM(), "alice accrual above min claim");
        uint256 before = alice.balance;
        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, before + due, "claim transfers dividend BNB");
        assertEq(token.withdrawableDividendOf(alice), 0, "fully claimed");
        // Repeated claims only pay the NEW accumulation since the last claim.
        vm.deal(address(mint), 100 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 100 ether}();
        uint256 due2 = token.withdrawableDividendOf(alice);
        assertGt(due2, 0, "new accrual appears");
        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, before + due + due2, "2nd claim = new accrual only");
    }

    function test_DividendMinClaim() public {
        _mintAs(alice, 1, address(0));
        _openPool(carol);
        // Dust deposit: alice's withdrawable is below 0,001 BNB -> reverts,
        // but is NOT forfeited (keeps accumulating).
        vm.deal(address(mint), 0.0001 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 0.0001 ether}();
        uint256 due = token.withdrawableDividendOf(alice);
        assertGt(due, 0, "dust keeps accumulating");
        assertLt(due, token.MIN_DIVIDEND_CLAIM(), "dust below min claim");
        vm.prank(alice);
        vm.expectRevert(AgentToken.DividendTooSmall.selector);
        token.claimDividend();
        assertEq(token.withdrawableDividendOf(alice), due, "failed claim does not forfeit the accrual");
        // Add deposits until past the threshold -> the claim succeeds.
        vm.deal(address(mint), 1000 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 1000 ether}();
        assertGe(token.withdrawableDividendOf(alice), token.MIN_DIVIDEND_CLAIM(), "now above threshold");
        vm.prank(alice);
        token.claimDividend();
        assertEq(token.withdrawableDividendOf(alice), 0, "fully claimed");
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
