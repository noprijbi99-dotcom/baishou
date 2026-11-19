// SPDX-License-Identifier: MIT
// BAISHOU - WAVE-2 ADVERSARIAL tests (19 Nov 2026, verifikasi putaran ke-2).
//
// Cakupan file ini = celah yang BELUM diuji di suite step-2 maupun wave-1:
//   1. REENTRANCY: kontrak penyerang yang receive()-nya memanggil balik
//      claimRefund / exit / claimDividend / claimTreasury (termasuk
//      cross-function refund -> exit). Mandat spek: penyerang TIDAK boleh
//      menarik lebih dari haknya; setiap panggilan reentrant harus gagal
//      dan payout luar harus PERSIS sebesar utang, sekali saja.
//   2. claimTreasury sebelum pool buka (revert NotOpen) dan oleh bukan
//      treasury (revert NotTreasury) — wave-1/step-2 hanya menguji
//      claimReferral sebelum buka.
//
// Item brief lain (klaim refund ganda, refund sebelum gagal, exit sesudah
// pool buka, mint saat pause, mint lewat deadline, freeMint 2x, cap 168,
// MAX_PER_TX, sweep sebelum/sesudah jendela, pause tidak memblokir refund,
// self/zero referrer, dividen di bawah minimum) SUDAH ter-cover di suite
// step-2 — pemetaan lengkapnya ada di VERIFY-2.md, tidak diduplikasi di sini.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockWBNB, MockFactory, MockRegistry} from "./mocks/Mocks.sol";

/// @notice Penyerang: Agent ID holder berbentuk kontrak. Saat menerima BNB
///         (payout), receive() mencoba SATU panggilan reentrant (low-level,
///         hasil dicatat, kegagalan ditelan supaya payout luar selesai) —
///         persis pola serangan drain klasik.
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
        armed = false; // satu tembakan saja, hindari rekursi tak berujung
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
        assertTrue(mint.saleFailed(), "launch gagal");
        atk.arm(1); // reenter claimRefund saat payout
        uint256 before = address(atk).balance;
        atk.doClaimRefund();
        assertEq(atk.reentryAttempts(), 1, "satu percobaan reentrancy terjadi");
        assertEq(atk.reentrySuccesses(), 0, "reentrancy claimRefund GAGAL");
        assertEq(address(atk).balance, before + 0.0168 ether, "refund dibayar PERSIS sekali");
        assertEq(mint.deposits(address(atk)), 0, "deposit lunas");
    }

    function test_Reentrancy_ClaimRefundCannotCrossIntoExit() public {
        // Serangan silang paling tajam: refund 100% sudah dibayar, lalu di
        // tengah payout mencoba exit(1) untuk menarik 80% LAGI dari share
        // yang sama (mintedCount belum dikurangi claimRefund).
        (ReentrantClaimer atk, uint256 atkId) = _makeAttacker();
        atk.doMint(10, mint.costOf(10));
        vm.warp(mint.failureTime() + 1);
        atk.arm(2); // reenter exit(1) saat payout refund
        uint256 before = address(atk).balance;
        atk.doClaimRefund();
        assertEq(atk.reentryAttempts(), 1, "percobaan cross-reentrancy terjadi");
        assertEq(atk.reentrySuccesses(), 0, "cross-reentrancy ke exit GAGAL");
        assertEq(address(atk).balance, before + 0.0168 ether, "total diterima TETAP 100%, tidak lebih");
        assertEq(mint.mintedCount(atkId), 10, "exit reentrant tidak mengurangi share");
    }

    function test_Reentrancy_ExitPaysExactlyOnce() public {
        (ReentrantClaimer atk, uint256 atkId) = _makeAttacker();
        atk.doMint(10, mint.costOf(10));
        atk.arm(2); // reenter exit(1) saat payout exit parsial
        uint256 before = address(atk).balance;
        atk.doExit(5); // exit 5 dari 10 -> haknya 80% x 5 x 0,00168
        assertEq(atk.reentryAttempts(), 1, "percobaan reentrancy terjadi");
        assertEq(atk.reentrySuccesses(), 0, "reentrancy exit GAGAL");
        assertEq(address(atk).balance, before + 0.00672 ether, "exit dibayar PERSIS 80% x 5 share");
        assertEq(mint.mintedCount(atkId), 5, "hanya 5 share luar yang ter-exit");
        assertEq(mint.forfeitOf(address(atk)), 0.00168 ether, "forfeit hanya dari exit luar");
    }

    function test_Reentrancy_ClaimDividendPaysExactlyOnce() public {
        // claimDividend TIDAK punya nonReentrant — perlindungannya murni
        // CEI (withdrawnDividends dicatat SEBELUM transfer). Test ini
        // membuktikan urutan itu: reenter saat payout -> withdrawable 0.
        (ReentrantClaimer atk,) = _makeAttacker();
        atk.doMint(2, mint.costOf(2));
        _openPool(carol);
        vm.deal(address(mint), 100 ether);
        vm.prank(address(mint));
        token.depositDividends{value: 100 ether}();
        uint256 due = token.withdrawableDividendOf(address(atk));
        assertGe(due, token.MIN_DIVIDEND_CLAIM(), "dividen penyerang di atas ambang klaim");
        atk.arm(3); // reenter claimDividend saat payout
        uint256 before = address(atk).balance;
        atk.doClaimDividend();
        assertEq(atk.reentryAttempts(), 1, "percobaan reentrancy terjadi");
        assertEq(atk.reentrySuccesses(), 0, "reentrancy dividen GAGAL (CEI)");
        assertEq(address(atk).balance, before + due, "dividen dibayar PERSIS sekali");
        assertEq(token.withdrawableDividendOf(address(atk)), 0, "tidak ada sisa yang bisa diklaim ulang");
    }

    function test_Reentrancy_ClaimTreasuryPaysExactlyOnce() public {
        // Stack terpisah: treasury = kontrak penyerang. Akrual claimTreasury
        // hanya ada PASCA-pool (bagian pre-pool dibayar sekali di _open),
        // jadi: mint pre-pool -> openEarly (penyerang terima 15% pre-pool,
        // receive belum armed) -> mint pasca-pool -> claimTreasury armed.
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
        mint2.setPaused(false);

        uint256 cost10 = mint2.costOf(10);
        vm.prank(alice);
        mint2.mint{value: cost10}(10, address(0), cost10);
        vm.prank(admin);
        mint2.openEarly();
        assertEq(address(atk).balance, 0.00252 ether, "treasury terima 15% pre-pool saat _open");

        uint256 cost1 = mint2.costOf(1);
        vm.prank(alice);
        mint2.mint{value: cost1}(1, address(0), cost1);
        assertEq(mint2.escrowTreasury(), 0.000252 ether, "akrual pasca-pool 15% x 0,00168");

        atk.arm(4); // reenter claimTreasury saat payout
        atk.doClaimTreasury();
        assertEq(atk.reentryAttempts(), 1, "percobaan reentrancy terjadi");
        assertEq(atk.reentrySuccesses(), 0, "reentrancy claimTreasury GAGAL");
        assertEq(address(atk).balance, 0.00252 ether + 0.000252 ether, "klaim dibayar PERSIS sekali");
        assertEq(mint2.escrowTreasury(), 0, "escrow treasury kosong");
        vm.expectRevert(AgentMint.NothingOwed.selector);
        atk.doClaimTreasury();
    }

    // ============ 2. claimTreasury gates ============

    function test_ClaimTreasuryBeforeOpenReverts() public {
        _mintAs(alice, 10, address(0));
        assertGt(mint.escrowTreasury(), 0, "escrow terisi pre-pool");
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
