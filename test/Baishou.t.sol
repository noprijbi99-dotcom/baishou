// SPDX-License-Identifier: MIT
// BAISHOU - test base + deployment sanity + BAISHOU parameter targets.
//
// Status: KERANGKA. Tests marked vm.skip encode the BAISHOU design targets
// (POLA-BARU-ARUNIKA.md §3/§10, Opsi B) and run only after the fork is
// parameterised. Tests WITHOUT vm.skip must pass against the fork base now;
// they lock the wiring and the behaviour the final contract must KEEP.
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockWBNB, MockFactory, MockRegistry} from "./mocks/Mocks.sol";

contract BaishouTest is Test {
    AgentToken internal token;
    AgentMint internal mint;
    MockWBNB internal wbnb;
    MockFactory internal factory;
    MockRegistry internal registry;

    address internal admin = makeAddr("admin");
    address internal treasury = makeAddr("treasury");
    address internal feeTreasury = makeAddr("feeTreasury");
    address internal quotaSigner = makeAddr("quotaSigner");
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
            quotaSigner: quotaSigner,
            wbnb: address(wbnb),
            swapFeeBps: 30,
            unblockable: new address[](0),
            priceDiv: 1000,
            daySeconds: 86400,
            dayOffset: 0
        });
        mint = new AgentMint(c);
        token.initialize(address(mint));

        // Agent IDs for the test users (handle + owner, see Mocks.sol).
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
        mint.setPaused(false);
    }

    // ---- Wiring: must pass against the fork base now -----------------------

    function test_DeploymentWiring() public view {
        assertTrue(address(token) != address(0), "token not deployed");
        assertTrue(address(mint) != address(0), "mint not deployed");
        assertTrue(token.pair() != address(0), "pair not created");
        assertEq(token.wbnb(), address(wbnb), "token wbnb mismatch");
        assertFalse(mint.paused(), "mint should be unpaused after setPaused(false)");
        assertFalse(token.tradingEnabled(), "trading must be closed before pool opens");
        assertFalse(mint.opened(), "pool must not be open at deploy");
        assertEq(mint.totalMinted(), 0, "nothing minted at deploy");
    }

    function test_MintPrePoolGivesUserTokens() public {
        uint256 cost = mint.costOf(1);
        vm.prank(alice);
        mint.mint{value: cost}(1, address(0), cost);
        assertEq(mint.totalMinted(), 1, "totalMinted");
        // Fork value (AIC USER_SHARE). After BAISHOU parameterisation this
        // must become 168_000 ether - see test_BaishouParameterTargets.
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

    // ---- BAISHOU parameter targets (Opsi B) - skipped until final --------
    // Un-skip one by one as the fork is parameterised; each must turn green.

    function test_BaishouParameterTargets() public {
        vm.skip(true, "TODO: parameterisasi BAISHOU - konstanta masih AIC");
        assertEq(mint.TOTAL_SHARES(), 168_000, "total shares 168.000");
        assertEq(mint.OPEN_AT(), 16_800, "pre-pool 16.800 share");
        assertEq(mint.BASE_PRICE(), 0.00168 ether, "harga flat 0,00168 BNB");
        assertEq(mint.USER_SHARE(), 168_000 ether, "168.000 token/share");
        assertEq(mint.POOL_SHARE(), 134_400 ether, "134.400 token/share ke pool");
        assertEq(mint.OPEN_TOKENS(), 16_800 * 134_400 ether, "pool open 2,25792 miliar token");
        assertEq(mint.TREASURY_BPS(), 1_500, "treasury 15%");
        assertEq(mint.MINT_PRICE_BPS(), 10_000, "tepat 168.000/share, tanpa selisih 1%");
        assertEq(mint.MAX_PER_TX(), 168, "max 168 share/tx = cap wallet");
        assertEq(mint.BASE_PER_ID(), 168, "cap 168 share per alamat");
        assertEq(mint.INVITE_QUOTA(), 0, "kuota invite +2 DIHAPUS");
    }

    function test_BaishouTokenTaxTargets() public {
        vm.skip(true, "TODO: parameterisasi BAISHOU - pajak token masih AIC");
        assertEq(token.BUY_TAX_BPS(), 200, "beli 2%");
        assertEq(token.SELL_BURN_BPS(), 100, "jual 1% burn");
        assertEq(token.SELL_KEEP_BPS(), 100, "jual 1% dividen pool (bukan feeTreasury)");
    }
}
