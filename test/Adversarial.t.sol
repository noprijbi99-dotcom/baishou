// SPDX-License-Identifier: MIT
// BAISHOU - WAVE-2 ADVERSARIAL tests (19 Nov 2026, round-2 verification).
//
// Scope of this file = gaps NOT yet tested in the step-2 suite or wave-1:
//   1. REENTRANCY: an attacker contract whose receive() calls back into
//      claimRefund / exit / claimDividend / claimTreasury (including
//      cross-function refund -> exit). Spec mandate: the attacker must NOT be able
//      to withdraw more than its entitlement; every reentrant call must fail
//      and the outer payout must be EXACTLY the amount owed, exactly once.
//   2. claimTreasury before the pool opens (reverts NotOpen) and by a
//      non-treasury caller (reverts NotTreasury) — wave-1/step-2 only tested
//      claimReferral before opening.
//
// Other brief items (double refund claims, refund before failure, exit after
// the pool opens, mint while paused, mint past the deadline, freeMint 2x, the 168 cap,
// MAX_PER_TX, sweep before/after the window, pause not blocking refunds,
// self/zero referrer, dividends below the minimum) are ALREADY covered by the step-2
// suite — the full mapping is in VERIFY-2.md, not duplicated here.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockWBNB, MockFactory, MockRegistry} from "./mocks/Mocks.sol";

/// @notice Attacker: an Agent ID holder in contract form. When it receives BNB
///         (payout), receive() attempts ONE reentrant call (low-level,
///         the result is recorded, failures are swallowed so the outer payout completes) —
///         exactly the classic drain-attack pattern.
contract ReentrantClaimer {
    AgentMint public mint;
    AgentToken public token;
    uint8 public mode; // 1=claimRefund 2=exit(1) 3=claimDividend 4=claimTreasury
    bool public armed;
    uint256 public reentryAttempts;
    uint256 public reentrySuccesses;

    function setTargets(AgentMint mint_, AgentToken token_) external {
        mint = mint_;
        token = token_;
    }

    function arm(uint8 mode_) external {
        mode = mode_;
        armed = true;
    }

    function doMint(uint256 shares, uint256 cost) external {
        mint.mint{value: cost}(shares, address(0), cost);
    }

    function doExit(uint256 shares) external {
        mint.exit(shares);
    }

    function doClaimRefund() external {
        mint.claimRefund();
    }

    function doClaimDividend() external {
        token.claimDividend();
    }

    function doClaimTreasury() external {
        mint.claimTreasury();
    }

    receive() external payable {
        if (!armed) return;
        armed = false; // one shot only, avoid unbounded recursion
        reentryAttempts++;
        bool ok;
        if (mode == 1) {
            (ok,) = address(mint).call(abi.encodeWithSelector(AgentMint.claimRefund.selector));
        } else if (mode == 2) {
            (ok,) = address(mint).call(abi.encodeWithSelector(AgentMint.exit.selector, uint256(1)));
        } else if (mode == 3) {
            (ok,) = address(token).call(abi.encodeWithSelector(AgentToken.claimDividend.selector));
        } else if (mode == 4) {
            (ok,) = address(mint).call(abi.encodeWithSelector(AgentMint.claimTreasury.selector));
        }
        if (ok) reentrySuccesses++;
    }
}

contract AdversarialTest is BaishouTest {
    function _makeAttacker() internal returns (ReentrantClaimer atk, uint256 atkId) {
        atk = new ReentrantClaimer();
        atk.setTargets(mint, token);
        atkId = uint256(keccak256(bytes("attacker")));
        registry.setHandle(address(atk), "attacker");
        registry.setOwner(atkId, address(atk));
        vm.deal(address(atk), 100 ether);
    }

    // ============ 1. REENTRANCY ============

    function test_Reentrancy_ClaimRefundPaysExactlyOnce() public {
        (ReentrantClaimer atk,) = _makeAttacker();
        atk.doMint(10, mint.costOf(10)); // deposit 0,0168 BNB
        vm.warp(mint.failureTime() + 1);
        assertTrue(mint.saleFailed(), "launch failed");
        atk.arm(1); // reenter claimRefund during payout
        uint256 before = address(atk).balance;
        atk.doClaimRefund();
        assertEq(atk.reentryAttempts(), 1, "one reentrancy attempt occurred");
        assertEq(atk.reentrySuccesses(), 0, "reentrancy claimRefund FAILED");
        assertEq(address(atk).balance, before + 0.0168 ether, "refund paid EXACTLY once");
        assertEq(mint.deposits(address(atk)), 0, "deposit settled");
    }

    function test_Reentrancy_ClaimRefundCannotCrossIntoExit() public {
        // The sharpest cross attack: the 100% refund has been paid, then in
        // the middle of the payout it tries exit(1) to withdraw another 80% from the same
        // shares (mintedCount not yet reduced by claimRefund).
        (ReentrantClaimer atk, uint256 atkId) = _makeAttacker();
        atk.doMint(10, mint.costOf(10));
        vm.warp(mint.failureTime() + 1);
        atk.arm(2); // reenter exit(1) during the refund payout
        uint256 before = address(atk).balance;
        atk.doClaimRefund();
        assertEq(atk.reentryAttempts(), 1, "cross-reentrancy attempt occurred");
        assertEq(atk.reentrySuccesses(), 0, "cross-reentrancy into exit FAILED");
        assertEq(address(atk).balance, before + 0.0168 ether, "total received STILL 100%, no more");
        assertEq(mint.mintedCount(atkId), 10, "reentrant exit does not reduce shares");
    }

    function test_Reentrancy_ExitPaysExactlyOnce() public {
        (ReentrantClaimer atk, uint256 atkId) = _makeAttacker();
        atk.doMint(10, mint.costOf(10));
        atk.arm(2); // reenter exit(1) during the partial-exit payout
        uint256 before = address(atk).balance;
        atk.doExit(5); // exit 5 of 10 -> its entitlement is 80% x 5 x 0,00168
        assertEq(atk.reentryAttempts(), 1, "reentrancy attempt occurred");
        assertEq(atk.reentrySuccesses(), 0, "reentrancy exit FAILED");
        assertEq(address(atk).balance, before + 0.00672 ether, "exit paid EXACTLY 80% x 5 shares");
        assertEq(mint.mintedCount(atkId), 5, "only 5 external shares exited");
        assertEq(mint.forfeitOf(address(atk)), 0.00168 ether, "forfeit only from external exit");
    }

    function test_Reentrancy_ClaimDividendPaysExactlyOnce() public {
        // claimDividend has NO nonReentrant — its protection is purely
        // CEI (withdrawnDividends is recorded BEFORE the transfer). This test
        // proves that ordering: reenter during payout -> withdrawable 0.
        (ReentrantClaimer atk,) = _makeAttacker();
        atk.doMint(2, mint.costOf(2));
        _openPool(carol);
        vm.deal(address(mint), 100 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 100 ether}();
        uint256 due = token.withdrawableDividendOf(address(atk));
        assertGe(due, token.MIN_DIVIDEND_CLAIM(), "attacker dividend above claim threshold");
        atk.arm(3); // reenter claimDividend during payout
        uint256 before = address(atk).balance;
        atk.doClaimDividend();
        assertEq(atk.reentryAttempts(), 1, "reentrancy attempt occurred");
        assertEq(atk.reentrySuccesses(), 0, "reentrancy dividend FAILED (CEI)");
        assertEq(address(atk).balance, before + due, "dividend paid EXACTLY once");
        assertEq(token.withdrawableDividendOf(address(atk)), 0, "no remainder that can be re-claimed");
    }

    function test_Reentrancy_ClaimTreasuryPaysExactlyOnce() public {
        // Separate stack: treasury = attacker contract. claimTreasury accrual
        // only exists POST-pool (the pre-pool portion is paid once in _open),
        // so: mint pre-pool -> pool opens at OPEN_AT via a real fill (v2:
        // openEarly removed; the attacker receives the 15% pre-pool, receive not yet
        // armed) -> mint post-pool -> claimTreasury armed.
        MockWBNB wbnb2 = new MockWBNB();
        MockFactory factory2 = new MockFactory();
        MockRegistry registry2 = new MockRegistry();
        ReentrantClaimer atk = new ReentrantClaimer();
        AgentToken token2 = new AgentToken(
            "BAISHOU", "BAISHOU", address(wbnb2), address(factory2), poolManager, infinityVault
        );
        AgentMint.Config memory c = AgentMint.Config({
            token: address(token2),
            registrar: address(registry2),
            treasury: address(atk),
            feeTreasury: feeTreasury,
            admin: admin,
            wbnb: address(wbnb2),
            swapFeeBps: 30,
            unblockable: new address[](0),
            priceDiv: 1
        });
        AgentMint mint2 = new AgentMint(c);
        atk.setTargets(mint2, token2);
        token2.initialize(address(mint2));
        registry2.setHandle(alice, "alice");
        registry2.setOwner(ALICE_ID, alice);
        vm.prank(admin);
        mint2.startSale();

        // v2: the pool ONLY opens at OPEN_AT — alice mints 167 (per-ID quota
        // 168: 1 share left for the post-pool mint below), 999 generic agents
        // x 168, then 1 final agent mints the 1 closing share.
        uint256 cost168 = mint2.costOf(168);
        uint256 cost167 = mint2.costOf(167);
        vm.prank(alice);
        mint2.mint{value: cost167}(167, address(0), cost167);
        vm.pauseGasMetering();
        for (uint256 i; i < 999; i++) {
            address agent = address(uint160(0x200_000 + i));
            string memory handle = string.concat("f2agent", vm.toString(i));
            registry2.setHandle(agent, handle);
            registry2.setOwner(uint256(keccak256(bytes(handle))), agent);
            vm.deal(agent, 1 ether);
            vm.prank(agent);
            mint2.mint{value: cost168}(168, address(0), cost168);
        }
        address last = address(uint160(0x200_000 + 999));
        registry2.setHandle(last, "f2agent999");
        registry2.setOwner(uint256(keccak256(bytes("f2agent999"))), last);
        vm.deal(last, 1 ether);
        uint256 costLast = mint2.costOf(1);
        vm.prank(last);
        mint2.mint{value: costLast}(1, address(0), costLast);
        vm.resumeGasMetering();
        assertTrue(mint2.opened(), "mint2 pool opens at OPEN_AT");
        assertEq(address(atk).balance, 42.336 ether, "treasury receives 15% x 282,24 at _open");

        uint256 cost1 = mint2.costOf(1); // share 168.001: epoch 1 = 0,0017136
        vm.prank(alice);
        mint2.mint{value: cost1}(1, address(0), cost1);
        assertEq(mint2.escrowTreasury(), 0.00025704 ether, "post-pool accrual 15% x 0,0017136");

        atk.arm(4); // reenter claimTreasury during payout
        atk.doClaimTreasury();
        assertEq(atk.reentryAttempts(), 1, "reentrancy attempt occurred");
        assertEq(atk.reentrySuccesses(), 0, "reentrancy claimTreasury FAILED");
        assertEq(address(atk).balance, 42.336 ether + 0.00025704 ether, "claim paid EXACTLY once");
        assertEq(mint2.escrowTreasury(), 0, "treasury escrow empty");
        vm.expectRevert(AgentMint.NothingOwed.selector);
        atk.doClaimTreasury();
    }

    // ============ 2. claimTreasury gates ============

    function test_ClaimTreasuryBeforeOpenReverts() public {
        _mintAs(alice, 10, address(0));
        assertGt(mint.escrowTreasury(), 0, "escrow filled pre-pool");
        vm.prank(treasury);
        vm.expectRevert(AgentMint.NotOpen.selector);
        mint.claimTreasury();
    }

    function test_ClaimTreasuryOnlyTreasury() public {
        _mintAs(alice, 10, address(0));
        vm.prank(alice);
        vm.expectRevert(AgentMint.NotTreasury.selector);
        mint.claimTreasury();
    }
}
