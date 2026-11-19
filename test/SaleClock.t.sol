// SPDX-License-Identifier: MIT
// BAISHOU - V2 SALE CLOCK tests (RT-01 fix, 19 Nov 2026).
// The v2 sale failure clock is anchored to SALE START (startSale), NOT deploy:
//   (a) without startSale, warp +365 days: saleFailed() stays false,
//       failureTime() stays 0, mint/freeMint still revert Paused —
//       the contract may wait for review FOREVER with no time bomb.
//   (b) startSale -> the exact 14-day boundary (not failed at == deadline,
//       failed at +1 second) -> 100% refunds work on the new clock. The combined
//       multi-user scenario (deposits + forfeit) on the new clock is covered by
//       ForkRefund.t.sol — it reads failureTime() dynamically and
//       its setUp now calls startSale.
//   (c) startSale twice -> AlreadyStarted; non-admin -> NotAdmin.
//   (d) the pool opens mid-window (day 10) -> saleFailed() stays
//       false even though the timestamp passes failureTime; mintClosed falls
//       at openedTime + POST_POOL_WINDOW (7 days), NOT +14 days.
//   (e) openEarly: REMOVED in v2 (compile-level — that function no longer
//       exists in AgentMint; the old PoolOpen test for it has been withdrawn).
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockWBNB, MockFactory, MockRegistry} from "./mocks/Mocks.sol";

contract SaleClockTest is BaishouTest {
    // BaishouTest setUp already calls startSale() at the deploy timestamp.

    function test_StartSaleTwiceReverts() public {
        assertGt(mint.saleStartTime(), 0, "sale sudah dimulai di setUp");
        vm.prank(admin);
        vm.expectRevert(AgentMint.AlreadyStarted.selector);
        mint.startSale();
    }

    function test_StartSaleNonAdminReverts() public {
        vm.prank(alice);
        vm.expectRevert(AgentMint.NotAdmin.selector);
        mint.startSale();
    }

    function test_FailureBoundaryExactly14Days() public {
        uint256 start = mint.saleStartTime();
        assertEq(mint.failureTime(), start + 14 days, "deadline = start + 14 hari");
        vm.warp(start + 14 days);
        assertFalse(mint.saleFailed(), "di tepat deadline: BELUM gagal (strict >)");
        vm.warp(start + 14 days + 1);
        assertTrue(mint.saleFailed(), "deadline + 1 detik: gagal");
    }

    function test_Refund100PercentUnderNewClock() public {
        _mintAs(alice, 10, address(0)); // 0,0168 BNB
        vm.warp(mint.saleStartTime() + 14 days + 1);
        assertTrue(mint.saleFailed(), "gagal di jam baru");
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.claimRefund();
        assertEq(alice.balance, before + 0.0168 ether, "refund 100% di jam v2");
        assertEq(mint.deposits(alice), 0, "deposit lunas");
    }

    function test_OpenMidWindow_KillsFailure_ClosesAtPostPoolWindow() public {
        uint256 start = mint.saleStartTime();
        vm.warp(start + 10 days); // day 10 of 14: still within the window
        _openPool(alice);
        assertTrue(mint.opened(), "pool buka hari ke-10");
        uint256 openedAt = mint.openedTime();
        // Pass failureTime: saleFailed must NOT be true (the pool has opened).
        vm.warp(start + 14 days + 1);
        assertFalse(mint.saleFailed(), "pool sudah buka -> tidak gagal");
        assertFalse(mint.mintClosed(), "belum tutup: openedTime+7d belum lewat");
        // mintClosed falls at openedTime + 7 days (POST_POOL_WINDOW).
        vm.warp(openedAt + 7 days + 1);
        assertTrue(mint.mintClosed(), "tutup di openedTime + 7 hari");
    }
}

/// @notice Stack WITHOUT startSale: a replica of the BaishouTest deployment but
///         the sale never starts (paused stays true from birth).
contract SaleClockUnstartedTest is Test {
    AgentToken internal token;
    AgentMint internal mint;
    MockWBNB internal wbnb;
    MockFactory internal factory;
    MockRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal treasury = makeAddr("treasury");
    address internal feeTreasury = makeAddr("feeTreasury");
    address internal alice = makeAddr("alice");

    function setUp() public {
        wbnb = new MockWBNB();
        factory = new MockFactory();
        registry = new MockRegistry();
        token = new AgentToken(
            "BAISHOU", "BAISHOU", address(wbnb), address(factory), makeAddr("poolManager"), makeAddr("infinityVault")
        );
        AgentMint.Config memory c = AgentMint.Config({
            token: address(token),
            registrar: address(registry),
            treasury: treasury,
            feeTreasury: feeTreasury,
            admin: admin,
            wbnb: address(wbnb),
            swapFeeBps: 30,
            unblockable: new address[](0),
            priceDiv: 1
        });
        mint = new AgentMint(c);
        token.initialize(address(mint));
        registry.setHandle(alice, "alice");
        registry.setOwner(uint256(keccak256(bytes("alice"))), alice);
        vm.deal(alice, 100 ether);
        // INTENTIONAL: no startSale(), no setPaused(false).
    }

    function test_ClockNeverRunsBeforeStart() public {
        assertTrue(mint.paused(), "lahir paused");
        assertEq(mint.saleStartTime(), 0, "sale belum dimulai");
        assertEq(mint.failureTime(), 0, "tidak ada deadline sebelum start");
        assertGt(mint.deployTime(), 0, "deployTime tetap tercatat (informational)");
        // Warp a FULL YEAR: without a start, there is no time bomb.
        vm.warp(block.timestamp + 365 days);
        assertFalse(mint.saleFailed(), "365 hari tanpa start: TIDAK gagal");
        assertEq(mint.failureTime(), 0, "deadline tetap 0");
        // Mint stays blocked by pause (not SoldOut — the clock is not running).
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentMint.Paused.selector);
        mint.mint{value: cost}(1, address(0), cost);
        vm.prank(alice);
        vm.expectRevert(AgentMint.Paused.selector);
        mint.freeMint();
    }

    function test_StartSaleAfterLongWait_StartsFreshWindow() public {
        vm.warp(block.timestamp + 365 days);
        vm.prank(admin);
        mint.startSale();
        uint256 start = mint.saleStartTime();
        assertEq(start, block.timestamp, "start = saat startSale dipanggil");
        assertEq(mint.failureTime(), start + 14 days, "jendela 14 hari BARU mulai");
        assertFalse(mint.saleFailed(), "tidak gagal di hari mulai");
        // The sale works normally after waiting a year.
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(mint.totalMinted(), 1, "mint jalan sesudah startSale");
    }
}
