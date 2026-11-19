// SPDX-License-Identifier: MIT
// BAISHOU - WAVE-3 PIN: closes two substantive VERIFY-2.md audit notes.
//
// W2 (ForkOpen.t.sol:98-106 old version): the POST-pool claimTreasury accrual
// used to be computed 100% from contract getters (costOf, TREASURY_BPS) without
// a literal anchor. Here the curve price + 15% cut are recomputed from
// spec literals (BASE 0,00168 BNB; LINEAR +0,0000336/epoch of 16.800 shares;
// cap 0,00336) by the _spec* functions in this file — NOT from costOf — then the
// claimTreasury payout is pinned to the hard literal 0,025704 BNB.
//
// W4 (ForkDividend.t.sol:61-68 old version): the dividend claim amount used to be
// circular (due read from withdrawableDividendOf). Here the expectation
// is computed INDEPENDENTLY: a shadow model maintains the pair reserves,
// the minter's tax balance, totalSupply, and magnifiedDividendPerShare from
// literal setup numbers + the spec AMM/accumulator formulas. The pair balance joins
// pro-rata because the accumulator divides over totalSupply (including tokens in
// pair) — that is reflected exactly in the model: mdps rises by
// (deposit x 2^128) / totalSupply at deposit time. The sell-tax "burn" tokens
// also STAY in totalSupply (transfer to DEAD, not _burn) and join
// pro-rata — the model therefore keeps supply constant. Alice's claim is asserted
// == floor(alice balance x shadow mdps / 2^128); alice's correction = 0 (tokens
// received while mdps = 0, never moved), withdrawn = 0.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {MockPair} from "./mocks/Mocks.sol";

contract Wave3PinTest is BaishouTest {
    // ================= W2: pin the post-pool treasury accrual =================

    uint256 internal constant SPEC_BASE_PRICE = 0.00168 ether; // spec literal
    uint256 internal constant SPEC_OPEN_AT = 168_000;
    uint256 internal constant SPEC_EPOCH_SHARES = 16_800;

    /// @dev The spec curve rewritten from literals: n <= 168.000 -> 100;
    ///      epoch = (n-168.001)/16.800 + 1; units = min(100 + 2*epoch, 200).
    function _specUnits(uint256 n) internal pure returns (uint256) {
        if (n <= SPEC_OPEN_AT) return 100;
        uint256 epoch = (n - SPEC_OPEN_AT - 1) / SPEC_EPOCH_SHARES + 1;
        uint256 units = 100 + 2 * epoch;
        return units > 200 ? 200 : units;
    }

    function _specCost(uint256 firstShare, uint256 shares) internal pure returns (uint256 cost) {
        uint256 unit = SPEC_BASE_PRICE / 100;
        for (uint256 i; i < shares; i++) {
            cost += _specUnits(firstShare + i) * unit;
        }
    }

    /// @dev The treasury cut per share exactly as spec: pay x 15%,
    ///      floored per share, then summed.
    function _specTreasury(uint256 firstShare, uint256 shares) internal pure returns (uint256 acc) {
        uint256 unit = SPEC_BASE_PRICE / 100;
        for (uint256 i; i < shares; i++) {
            uint256 pay = _specUnits(firstShare + i) * unit;
            acc += pay * 1_500 / 10_000;
        }
    }

    function test_W2_PostPoolTreasuryAccrualPinnedLiteral() public {
        _openPool(alice); // totalMinted = 168.000, pool opens

        // Initial anchor (literal): trigger mint of 1 flat share -> 15% cut =
        // 0,000252 BNB paid to treasury at _open; escrow back to 0.
        assertEq(treasury.balance, 0.000252 ether, "cut trigger dibayar saat open");
        assertEq(mint.escrowTreasury(), 0, "prasyarat: escrow 0 sesudah open");

        // Post-pool mint: 100 shares by bob = shares #168.001..#168.100,
        // all epoch 1 -> units 102 -> 0,0017136 BNB/share.
        uint256 firstShare = 168_001;
        uint256 shares = 100;
        uint256 expectedCost = _specCost(firstShare, shares);
        assertEq(expectedCost, 0.17136 ether, "PIN W2: biaya spek 100 share epoch-1");
        uint256 expectedTreasury = _specTreasury(firstShare, shares);
        assertEq(expectedTreasury, 0.025704 ether, "PIN W2: akrual spek = 15% x 0,17136");

        uint256 bobBefore = bob.balance;
        vm.prank(bob);
        mint.mint{value: expectedCost}(shares, address(0), expectedCost);
        assertEq(bob.balance, bobBefore - expectedCost, "bob bayar persis biaya spek (refund 0)");
        assertEq(token.balanceOf(bob), 16_800_000_000 ether, "bob terima 100 x 168 jt token");
        assertEq(mint.escrowTreasury(), expectedTreasury, "escrow terakru = angka spek");

        uint256 treasuryBefore = treasury.balance;
        vm.prank(treasury);
        mint.claimTreasury();
        assertEq(
            treasury.balance,
            treasuryBefore + 0.025704 ether,
            "PIN W2: claimTreasury membayar 0,025704 BNB persis"
        );
        assertEq(mint.escrowTreasury(), 0, "escrow habis sesudah klaim");

        vm.prank(treasury);
        vm.expectRevert(AgentMint.NothingOwed.selector);
        mint.claimTreasury();
    }

    // ================= W4: pin the dividend claim amount =======================

    uint256 internal constant SPEC_MAGNITUDE = 2 ** 128; // accumulator spec literal

    /// @dev The spec AMM formula (PancakeMath.amountOut, test swap fee = 30 bps
    ///      from the setUp Config) rewritten from setup parameters.
    function _specAmountOut(uint256 amtIn, uint256 rIn, uint256 rOut) internal pure returns (uint256) {
        uint256 inWithFee = amtIn * (10_000 - 30);
        return (inWithFee * rOut) / (rIn * 10_000 + inWithFee);
    }

    /// @dev Sell all of the minter's tax tokens via a real swapTax(), while
    ///      advancing the shadow model: cap per call = pair token reserve
    ///      pair x 10/10.000 (spec TAX_SWAP_BPS), BNB out via the AMM formula,
    ///      mdps rises (D x 2^128)/supply — supply CONSTANT during the flush
    ///      (tax sales = transfers, not burns).
    function _flushTaxShadow(uint256 rT, uint256 rW, uint256 minterBal, uint256 supply, uint256 mdps, uint256 totalDep)
        internal
        returns (uint256, uint256, uint256, uint256)
    {
        while (minterBal > 0) {
            uint256 cap = rT * 10 / 10_000;
            uint256 amt = minterBal < cap ? minterBal : cap;
            vm.roll(block.number + 1);
            mint.swapTax();
            uint256 d = _specAmountOut(amt, rT, rW);
            mdps += (d * SPEC_MAGNITUDE) / supply;
            totalDep += d;
            rT += amt;
            rW -= d;
            minterBal -= amt;
        }
        return (rT, rW, mdps, totalDep);
    }

    function test_W4_DividendClaimMatchesIndependentComputation() public {
        // ---- Deterministic setup: pool opens via the REAL path (v2:
        //      openEarly removed) — alice 168 shares + fill 999 agents.
        //      Total supply = user 28,224 T + pool 22,5792 T; seed pool
        //      239,904 BNB (all mints without a referrer). ----
        _mintAs(alice, 168, address(0));
        _fillToOpen(address(0));
        MockPair pair = _pair();
        address pairAddr = address(pair);

        uint256 aliceTokens = 28_224_000_000 ether; // 168 x 168.000.000 (literal)
        uint256 supply0 = 50_803_200_000_000 ether; // 28,224 T user + 22,5792 T pool
        assertEq(token.balanceOf(alice), aliceTokens, "setup: saldo alice literal");
        assertEq(token.totalSupply(), supply0, "setup: supply awal literal");
        (uint256 rBnb0, uint256 rToken0) = mint.reserves();
        assertEq(rBnb0, 239.904 ether, "setup: reserve BNB literal (jangkar model)");
        assertEq(rToken0, 22_579_200_000_000 ether, "setup: reserve token literal (jangkar model)");

        // ---- Bob BUYS 9 trillion tokens (gross) from the pair; pays 96 BNB ----
        vm.prank(bob);
        wbnb.deposit{value: 96 ether}();
        vm.prank(bob);
        wbnb.transfer(pairAddr, 96 ether);
        uint256 buyGross = 9_000_000_000_000 ether;
        (uint256 out0, uint256 out1) =
            pair.token0() == address(token) ? (buyGross, uint256(0)) : (uint256(0), buyGross);
        pair.swap(out0, out1, bob, "");
        // Spec buy split 2%: 180 billion to the minter, 8,82 trillion to bob.
        assertEq(token.balanceOf(address(mint)), 180_000_000_000 ether, "setup: pajak beli 2%");
        assertEq(token.balanceOf(bob), 8_820_000_000_000 ether, "setup: bob terima 98%");

        // ---- Flush buy tax -> dividend pool (shadow model) ----
        uint256 rT = 13_579_200_000_000 ether; // 22_579_200_000_000 - 9_000_000_000_000
        uint256 rW = 335.904 ether; // 239,904 (pool open) + 96 (bayaran bob)
        uint256 mdps;
        uint256 totalDep;
        (rT, rW, mdps, totalDep) = _flushTaxShadow(rT, rW, 180_000_000_000 ether, supply0, 0, 0);
        assertEq(token.balanceOf(address(mint)), 0, "model: pajak beli habis terjual");

        // ---- Bob SELLS 2 trillion tokens: spec split 1% burn + 1% kept ----
        // MODEL NOTE: the "burn" in AgentToken is a transfer to DEAD,
        // NOT _burn — the tokens STAY in totalSupply and join
        // pro-rata dividends (never claimed by DEAD). So supply does
        // NOT fall; the accumulator denominator stays supply0 in the second flush.
        vm.prank(bob);
        token.transfer(pairAddr, 2_000_000_000_000 ether);
        (uint256 w0, uint256 w1) =
            pair.token0() == address(wbnb) ? (uint256(20 ether), uint256(0)) : (uint256(0), uint256(20 ether));
        pair.swap(w0, w1, bob, ""); // bob takes 20 BNB (setup parameter)
        assertEq(token.balanceOf(token.DEAD()), 20_000_000_000 ether, "setup: burn 1% parkir di DEAD");
        assertEq(token.totalSupply(), supply0, "setup: supply tetap (burn = transfer ke DEAD)");
        assertEq(token.balanceOf(address(mint)), 20_000_000_000 ether, "setup: kept 1% di minter");
        rT += 1_960_000_000_000 ether; // net tokens into the pair (2 T - 1% - 1%)
        rW -= 20 ether;

        // ---- Flush sell tax -> dividend pool (denominator stays supply0) ----
        (rT, rW, mdps, totalDep) = _flushTaxShadow(rT, rW, 20_000_000_000 ether, supply0, mdps, totalDep);
        assertEq(token.balanceOf(address(mint)), 0, "model: pajak jual habis terjual");
        // Model validation: total deposits per the contract == per the shadow model.
        assertEq(token.totalDividends(), totalDep, "model: total setoran dividen cocok");

        // ---- Alice's expectation: pure pro-rata over the shadow mdps ----
        // The pair holds ~35% of supply at this point and joins pro-rata —
        // already reflected because mdps divides over the FULL totalSupply.
        uint256 expected = aliceTokens * mdps / SPEC_MAGNITUDE;
        assertEq(expected, 2_653_293_237_882_583, "PIN W4 (v2, pool nyata): ekspektasi literal 0,002653293237882583 BNB");
        assertGe(expected, 0.001 ether, "ekspektasi di atas ambang klaim minimum");
        uint256 before = alice.balance;
        vm.prank(alice);
        token.claimDividend();
        assertEq(alice.balance, before + expected, "PIN W4: klaim alice == hitungan independen");
        assertEq(token.withdrawableDividendOf(alice), 0, "habis diklaim, tidak bisa ganda");
    }
}
