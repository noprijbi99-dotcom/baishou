// SPDX-License-Identifier: MIT
// BAISHOU - test base + deployment sanity + BAISHOU parameter targets (FINAL).
//
// Test decisions (documented, per the step-2 task):
// - setUp uses priceDiv = 1 (not 1000): costOf(1) == 0,00168 ether
//   exactly as in the design doc; test users are dealt 100 ether (more than
//   enough for 168 shares x 0,00168 = 0,28224 BNB).
// - v2: setUp starts the sale via startSale() (not setPaused(false)) —
//   saleStartTime == the setUp timestamp, failureTime() = start + 14 days.
// - Pool open is reached via _fastForwardToOpen() + 1 trigger mint (vm.store):
//   a loop of 1.000 agents x 168 shares is too slow/fragile. Storage slots are taken
//   from `forge inspect AgentMint storage-layout` (totalMinted=0,
//   pendingBnb=3, pendingTokens=4) and AgentToken (_balances=0,
//   _totalSupply=2), MockWBNB (balanceOf=4). The helper keeps consistency:
//   the contract's WBNB balance is INCREASED (the real deposit still funds the escrow payout
//   at _open), the contract's pool token balance is REPLACED to equal the
//   fictional pendingTokens (no leftover tokens get swapped along).
//   After _open, MockPair.sync() has set the reserves from the real balances.
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockWBNB, MockFactory, MockRegistry, MockPair} from "./mocks/Mocks.sol";

contract BaishouTest is Test {
    AgentToken internal token;
    AgentMint internal mint;
    MockWBNB internal wbnb;
    MockFactory internal factory;
    MockRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal treasury = makeAddr("treasury");
    address internal feeTreasury = makeAddr("feeTreasury");
    address internal poolManager = makeAddr("poolManager");
    address internal infinityVault = makeAddr("infinityVault");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant ALICE_ID = uint256(keccak256(bytes("alice")));
    uint256 internal constant BOB_ID = uint256(keccak256(bytes("bob")));
    uint256 internal constant CAROL_ID = uint256(keccak256(bytes("carol")));

    function setUp() public virtual {
        wbnb = new MockWBNB();
        factory = new MockFactory();
        registry = new MockRegistry();

        token = new AgentToken(
            "BAISHOU", "BAISHOU", address(wbnb), address(factory), poolManager, infinityVault
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
        registry.setOwner(ALICE_ID, alice);
        registry.setHandle(bob, "bob");
        registry.setOwner(BOB_ID, bob);
        registry.setHandle(carol, "carol");
        registry.setOwner(CAROL_ID, carol);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
        vm.deal(stranger, 100 ether);

        vm.prank(admin);
        mint.startSale();
    }

    // ---- Helpers -----------------------------------------------------------

    function _mintAs(address user, uint256 shares, address referrer) internal {
        uint256 cost = mint.costOf(shares);
        vm.prank(user);
        mint.mint{value: cost}(shares, referrer, cost);
    }

    function _pair() internal view returns (MockPair) {
        return MockPair(token.pair());
    }

    /// @dev See the file header: a fiction of 167.999 shares without a referrer.
    function _fastForwardToOpen() internal {
        uint256 poolShare = mint.POOL_SHARE();
        uint256 targetTokens = mint.OPEN_TOKENS() - poolShare;
        uint256 targetBnb = mint.OPEN_BNB() - mint.BASE_PRICE() * 85 / 100;
        vm.store(address(mint), bytes32(uint256(0)), bytes32(mint.OPEN_AT() - 1));
        vm.store(address(mint), bytes32(uint256(3)), bytes32(targetBnb));
        vm.store(address(mint), bytes32(uint256(4)), bytes32(targetTokens));
        bytes32 wbnbSlot = keccak256(abi.encode(address(mint), uint256(4)));
        uint256 wbnbBal = wbnb.balanceOf(address(mint)) + targetBnb;
        vm.store(address(wbnb), wbnbSlot, bytes32(wbnbBal));
        bytes32 tokSlot = keccak256(abi.encode(address(mint), uint256(0)));
        uint256 oldBal = token.balanceOf(address(mint));
        vm.store(address(token), tokSlot, bytes32(targetTokens));
        vm.store(address(token), bytes32(uint256(2)), bytes32(token.totalSupply() - oldBal + targetTokens));
    }

    /// @dev Open the pool: fast-forward + 1 trigger mint (no referrer) by
    ///      `triggerUser` (must hold an Agent ID + quota). After this
    ///      mint.opened() == true and reserves() are synced with the mock pair.
    function _openPool(address triggerUser) internal {
        _fastForwardToOpen();
        _mintAs(triggerUser, 1, address(0));
        assertTrue(mint.opened(), "pool should be open after trigger mint");
    }

    /// @dev Fill the sale to OPEN_AT via the REAL mint path (no vm.store,
    ///      no openEarly — that function was REMOVED in v2): generic agents mint
    ///      MAX_PER_TX per address until totalMinted == OPEN_AT; the final
    ///      mint triggers _open() inside the contract. Prerequisite:
    ///      (OPEN_AT - totalMinted) is exactly divisible by MAX_PER_TX. All mints
    ///      use the same `referrer` (address(0) = no referrer -> the
    ///      5% cut falls to the pool; pool seed 239,904 BNB, treasury
    ///      stays 42,336 BNB). Gas metering is disabled during the mass loop
    ///      (same pattern as ForkOpen — execution is still complete).
    function _fillToOpen(address referrer) internal {
        uint256 per = mint.MAX_PER_TX();
        uint256 cost = mint.costOf(per); // flat pre-pool: constant
        uint256 i;
        vm.pauseGasMetering();
        while (mint.totalMinted() + per <= mint.OPEN_AT()) {
            address agent = address(uint160(0x100_000 + i));
            string memory handle = string.concat("filler", vm.toString(i));
            registry.setHandle(agent, handle);
            registry.setOwner(uint256(keccak256(bytes(handle))), agent);
            vm.deal(agent, 1 ether);
            vm.prank(agent);
            mint.mint{value: cost}(per, referrer, cost);
            i++;
        }
        vm.resumeGasMetering();
        assertTrue(mint.opened(), "pool harus buka sesudah fill ke OPEN_AT");
    }

    // ---- Wiring ------------------------------------------------------------

    function test_DeploymentWiring() public view {
        assertTrue(address(token) != address(0), "token not deployed");
        assertTrue(address(mint) != address(0), "mint not deployed");
        assertTrue(token.pair() != address(0), "pair not created");
        assertEq(token.wbnb(), address(wbnb), "token wbnb mismatch");
        assertFalse(mint.paused(), "mint should be unpaused after startSale()");
        assertFalse(token.tradingEnabled(), "trading must be closed before pool opens");
        assertFalse(mint.opened(), "pool must not be open at deploy");
        assertEq(mint.totalMinted(), 0, "nothing minted at deploy");
    }

    function test_MintPrePoolGivesUserTokens() public {
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(mint.totalMinted(), 1, "totalMinted");
        assertEq(token.balanceOf(alice), mint.USER_SHARE(), "user tokens");
    }

    function test_MintRevertsWithoutAgentId() public {
        uint256 cost = mint.costOf(1);
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NoAgent.selector);
        mint.mint{value: cost}(1, address(0), cost);
    }

    function test_MintOverpayRefunded() public {
        uint256 cost = mint.costOf(1);
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.mint{value: cost + 0.5 ether}(1, address(0), cost + 0.5 ether);
        assertEq(alice.balance, before - cost, "only exact cost kept, overpay refunded");
    }

    function test_CostOfMonotonic() public view {
        uint256 c1 = mint.costOf(1);
        uint256 c2 = mint.costOf(2);
        assertGt(c1, 0, "cost must be positive");
        assertGt(c2, c1, "more shares must cost more");
    }

    function test_MintEmitsMinted() public {
        uint256 cost = mint.costOf(1);
        vm.expectEmit(true, true, false, true);
        emit AgentMint.Minted(alice, ALICE_ID, 1, 1, cost);
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
    }

    function test_MintWhilePausedReverts() public {
        vm.prank(admin);
        mint.setPaused(true);
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentMint.Paused.selector);
        mint.mint{value: cost}(1, address(0), cost);
    }

    // ---- BAISHOU parameter targets (FINAL, 19 Nov 06:22 UTC) --------------

    function test_BaishouParameterTargets() public view {
        assertEq(mint.TOTAL_SHARES(), 1_680_000, "total shares 1.680.000");
        assertEq(mint.OPEN_AT(), 168_000, "pre-pool 168.000 share");
        assertEq(mint.PROD_BASE_PRICE(), 0.00168 ether, "harga flat 0,00168 BNB");
        assertEq(mint.BASE_PRICE(), 0.00168 ether, "priceDiv=1: BASE_PRICE = harga prod");
        assertEq(mint.PROD_OPEN_BNB(), 225.792 ether, "pool open 225,792 BNB");
        assertEq(mint.OPEN_BNB(), 225.792 ether, "priceDiv=1: OPEN_BNB = prod");
        assertEq(mint.USER_SHARE(), 168_000_000 ether, "168.000.000 token/share");
        assertEq(mint.POOL_SHARE(), 134_400_000 ether, "134.400.000 token/share ke pool");
        assertEq(mint.OPEN_TOKENS(), 22_579_200_000_000 ether, "pool open 22,5792 triliun token");
        assertEq(mint.MAX_SUPPLY(), 510_854_400_000_000 ether, "max supply 510,8544 triliun");
        assertEq(mint.TREASURY_BPS(), 1_500, "treasury 15%");
        assertEq(mint.REFERRAL_BPS(), 500, "referral 5% flat");
        assertEq(mint.MINT_PRICE_BPS(), 10_000, "tepat 168.000.000/share, tanpa selisih 1%");
        assertEq(mint.MAX_PER_TX(), 168, "max 168 share/tx = cap wallet");
        assertEq(mint.BASE_PER_ID(), 168, "cap 168 share per alamat");
        assertEq(mint.INVITE_QUOTA(), 0, "kuota invite +2 DIHAPUS");
        assertEq(mint.FREE_SHARES(), 16_800, "free 16.800 share");
        assertEq(mint.EPOCH_SHARES(), 16_800, "epoch 16.800 share");
        assertEq(mint.SALE_WINDOW(), 14 days, "jendela target sale 14 hari sejak start (v2)");
        assertEq(mint.POST_POOL_WINDOW(), 7 days, "mint pasca-pool tutup +7 hari (v2)");
        assertEq(mint.REFUND_WINDOW(), 90 days, "jendela refund 90 hari sejak gagal");
    }

    function test_BaishouTokenTaxTargets() public view {
        assertEq(token.BUY_TAX_BPS(), 200, "beli 2%");
        assertEq(token.SELL_BURN_BPS(), 100, "jual 1% burn");
        assertEq(token.SELL_KEEP_BPS(), 100, "jual 1% dividen pool (bukan feeTreasury)");
        assertEq(token.MAX_SUPPLY(), 510_854_400_000_000 ether, "token max supply = mint cap");
        assertEq(token.MIN_DIVIDEND_CLAIM(), 0.001 ether, "min klaim dividen 0,001 BNB");
    }

    function test_RegistryRegistersOnMint() public {
        assertFalse(mint.isParticipant(ALICE_ID), "belum peserta sebelum mint");
        assertEq(mint.participantCount(), 0, "0 peserta awal");
        _mintAs(alice, 1, address(0));
        assertTrue(mint.isParticipant(ALICE_ID), "terdaftar saat pertama mint");
        assertEq(mint.participantCount(), 1, "1 peserta");
        _mintAs(alice, 1, address(0));
        assertEq(mint.participantCount(), 1, "mint ke-2 ID sama tidak dobel");
        _mintAs(bob, 1, address(0));
        assertEq(mint.participantCount(), 2, "ID baru menambah peserta");
    }

    function test_DeployTimeAndSaleFailed() public view {
        assertEq(mint.deployTime(), block.timestamp, "deployTime = waktu deploy");
        assertEq(mint.saleStartTime(), block.timestamp, "setUp startSale() di timestamp yang sama");
        assertEq(mint.failureTime(), block.timestamp + 14 days, "failure = start + 14 hari (v2)");
        assertFalse(mint.saleFailed(), "belum gagal saat deploy");
        assertFalse(mint.mintClosed(), "mint belum tutup saat deploy");
    }

    function test_SaleFailedAfterDeadline() public {
        vm.warp(vm.getBlockTimestamp() + 14 days + 1);
        assertTrue(mint.saleFailed(), "gagal kalau deadline start+14 hari lewat & pool belum buka");
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        vm.expectRevert(AgentMint.SoldOut.selector);
        mint.mint{value: cost}(1, address(0), cost);
    }
}
