// SPDX-License-Identifier: MIT
// BAISHOU - V2 SALE CLOCK tests (fix RT-01, 19 Nov 2026).
// Jam kegagalan sale v2 berjangkar MULAI SALE (startSale), BUKAN deploy:
//   (a) tanpa startSale, warp +365 hari: saleFailed() tetap false,
//       failureTime() tetap 0, mint/freeMint tetap revert Paused —
//       kontrak boleh menunggu review SELAMANYA tanpa bom waktu.
//   (b) startSale -> batas 14 hari persis (belum gagal di == deadline,
//       gagal di +1 detik) -> refund 100% jalan di jam baru. Skenario
//       gabungan multi-user (deposits + forfeit) di jam baru dicakup
//       ForkRefund.t.sol — ia membaca failureTime() secara dinamis dan
//       setUp-nya kini startSale.
//   (c) startSale dua kali -> AlreadyStarted; non-admin -> NotAdmin.
//   (d) pool buka di tengah jendela (hari ke-10) -> saleFailed() tetap
//       false walau timestamp melewati failureTime; mintClosed jatuh
//       di openedTime + POST_POOL_WINDOW (7 hari), BUKAN +14 hari.
//   (e) openEarly: DIHAPUS di v2 (compile-level — fungsi itu tidak ada
//       lagi di AgentMint; test PoolOpen lama untuknya sudah dicabut).
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockWBNB, MockFactory, MockRegistry} from "./mocks/Mocks.sol";

contract SaleClockTest is BaishouTest {
    // setUp BaishouTest sudah memanggil startSale() di timestamp deploy.

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
        vm.warp(start + 10 days); // hari ke-10 dari 14: masih dalam jendela
        _openPool(alice);
        assertTrue(mint.opened(), "pool buka hari ke-10");
        uint256 openedAt = mint.openedTime();
        // Lewati failureTime: saleFailed TIDAK boleh true (pool sudah buka).
        vm.warp(start + 14 days + 1);
        assertFalse(mint.saleFailed(), "pool sudah buka -> tidak gagal");
        assertFalse(mint.mintClosed(), "belum tutup: openedTime+7d belum lewat");
        // mintClosed jatuh di openedTime + 7 hari (POST_POOL_WINDOW).
        vm.warp(openedAt + 7 days + 1);
        assertTrue(mint.mintClosed(), "tutup di openedTime + 7 hari");
    }
}

/// @notice Stack TANPA startSale: replika deployment BaishouTest tapi
///         sale tidak pernah dimulai (paused tetap true dari lahir).
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
        // SENGAJA: tidak ada startSale(), tidak ada setPaused(false).
    }

    function test_ClockNeverRunsBeforeStart() public {
        assertTrue(mint.paused(), "lahir paused");
        assertEq(mint.saleStartTime(), 0, "sale belum dimulai");
        assertEq(mint.failureTime(), 0, "tidak ada deadline sebelum start");
        assertGt(mint.deployTime(), 0, "deployTime tetap tercatat (informational)");
        // Warp SETAHUN penuh: tanpa start, tidak ada bom waktu.
        vm.warp(block.timestamp + 365 days);
        assertFalse(mint.saleFailed(), "365 hari tanpa start: TIDAK gagal");
        assertEq(mint.failureTime(), 0, "deadline tetap 0");
        // Mint tetap terblokir pause (bukan SoldOut — jam tidak berjalan).
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
        // Sale berfungsi normal sesudah menunggu setahun.
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(mint.totalMinted(), 1, "mint jalan sesudah startSale");
    }
}
