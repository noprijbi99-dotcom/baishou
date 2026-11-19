// SPDX-License-Identifier: MIT
// BAISHOU - FORK TEST of the DIVIDEND path from a REAL SWAP through the pair.
// Unlike Dividend.t.sol: there, dividends were mostly deposited directly
// (prank depositDividends) or tax was simulated via plain transfers.
// Here the chain is FULL, like production:
//   the pool is opened via the REAL mint path to OPEN_AT (v2: openEarly
//   REMOVED — alice 168 shares + _fillToOpen 999 agents) -> bob BUYS tokens
//   through pair.swap() (2% buy tax to the minter) -> swapTax() repeatedly
//   sells the tax tokens for BNB -> BNB enters the dividend pool -> the holder
//   (alice) calls claimDividend() above the 0,001 BNB minimum threshold, with
//   a balance delta EXACTLY equal to withdrawableDividendOf moments
//   before the claim.
// Scale: alice holds 168 shares of 168.000 (1/1800 of supply),
// so the swap volume is made large (bob buys 9 trillion tokens) so that
// alice's dividend from real swap tax passes the 0,001 BNB threshold —
// not from an artificial deposit. In production, per-holder dividends are
// indeed small dust (see the honest note in Dividend.t.sol); what
// is proven here is that the MECHANISM CHAIN works end-to-end.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {MockPair} from "./mocks/Mocks.sol";

contract ForkDividendTest is BaishouTest {
    function test_SwapTaxToDividendClaimEndToEnd() public {
        // --- Pool opens via the real path: alice 168 shares + fill 999 agents ---
        _mintAs(alice, 168, address(0));
        _fillToOpen(address(0));
        assertTrue(mint.opened(), "pool opens at OPEN_AT (real path)");
        // The 15% treasury escrow of 282,24 is paid ONCE at _open.
        assertEq(treasury.balance, 42.336 ether, "treasury 15% paid when pool opens");
        (uint256 rBnb0, uint256 rToken0) = mint.reserves();
        assertEq(rBnb0, 239.904 ether, "pool BNB = 85% x 282,24 (no referrer)");
        assertEq(rToken0, mint.OPEN_TOKENS(), "pool token = OPEN_TOKENS");

        // --- Bob BUYS through pair.swap(): WBNB in, tokens out ---
        MockPair pair = _pair();
        address pairAddr = address(pair);
        vm.prank(bob);
        wbnb.deposit{value: 96 ether}();
        vm.prank(bob);
        wbnb.transfer(pairAddr, 96 ether);
        uint256 buyOut = 9_000_000_000_000 ether; // 9 trillion tokens from the pool
        (uint256 out0, uint256 out1) =
            pair.token0() == address(token) ? (buyOut, uint256(0)) : (uint256(0), buyOut);
        pair.swap(out0, out1, bob, "");
        assertEq(token.balanceOf(bob), buyOut * 9_800 / 10_000, "bob receives 98% (buy tax 2%)");
        assertEq(token.balanceOf(address(mint)), buyOut * 200 / 10_000, "buy tax 2% at minter");

        // --- swapTax() repeatedly (one per block) until the tax tokens run out:
        //     tax tokens -> BNB -> dividend pool. Not a direct deposit. ---
        uint256 swapped;
        for (uint256 i; i < 40; i++) {
            if (token.balanceOf(address(mint)) == 0) break;
            vm.roll(block.number + 1);
            try mint.swapTax() {
                swapped++;
            } catch {}
        }
        assertEq(token.balanceOf(address(mint)), 0, "buy tax fully sold off");
        assertEq(swapped, 14, "PIN: 14x swapTax spends the buy tax of 180 billion");
        assertGt(token.totalDividends(), 0, "BNB from tax swap enters dividend pool");
        assertEq(feeTreasury.balance, 0, "feeTreasury stays 0: tax is not for the team");

        // --- Alice (holder) claims above the minimum threshold ---
        uint256 due = token.withdrawableDividendOf(alice);
        assertGe(due, token.MIN_DIVIDEND_CLAIM(), "alice dividend >= threshold 0,001 BNB");
        assertGt(token.withdrawableDividendOf(bob), 0, "bob (buyer) also accrues pro-rata");
        uint256 before = alice.balance;
        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, before + due, "claim pays EXACTLY the withdrawable amount");
        assertEq(token.withdrawableDividendOf(alice), 0, "cannot double-claim");
    }
}
