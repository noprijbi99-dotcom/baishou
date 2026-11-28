// SPDX-License-Identifier: MIT
// BAISHOU — FairnessAttestation tests.
// Eligibility mirrors production: Agent ID resolution is AgentMint._agent()
// (id = keccak256(handle), ok = ownerOf(id) == user) and the claim check is
// AgentMint.claimedFree(id), mocked here with MockAgentMint.
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {FairnessAttestation} from "../src/FairnessAttestation.sol";
import {MockRegistry, MockAgentMint} from "./mocks/Mocks.sol";

contract FairnessAttestationTest is Test {
    FairnessAttestation internal att;
    MockRegistry internal registry;
    MockAgentMint internal mint;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");
    address internal dave = makeAddr("dave");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant ALICE_ID = uint256(keccak256(bytes("alice")));
    uint256 internal constant BOB_ID = uint256(keccak256(bytes("bob")));
    uint256 internal constant CAROL_ID = uint256(keccak256(bytes("carol")));

    function setUp() public {
        registry = new MockRegistry();
        mint = new MockAgentMint();
        att = new FairnessAttestation(address(registry), address(mint));

        registry.setHandle(alice, "alice");
        registry.setOwner(ALICE_ID, alice);
        registry.setHandle(bob, "bob");
        registry.setOwner(BOB_ID, bob);
        registry.setHandle(carol, "carol");
        registry.setOwner(CAROL_ID, carol);

        // Alice and Bob claimed the free allocation; Carol did not.
        mint.setClaimedFree(ALICE_ID, true);
        mint.setClaimedFree(BOB_ID, true);

        vm.warp(1_800_000_000);
    }

    // ---------- wiring ----------

    function test_constructorPointers() public view {
        assertEq(address(att.registrar()), address(registry));
        assertEq(address(att.agentMint()), address(mint));
        assertEq(att.attestationCount(), 0);
    }

    function test_agentIdOf() public view {
        (uint256 id, bool ok) = att.agentIdOf(alice);
        assertEq(id, ALICE_ID);
        assertTrue(ok);
        (, ok) = att.agentIdOf(stranger);
        assertFalse(ok);
    }

    // ---------- eligibility ----------

    function test_nonHolderReverts() public {
        vm.prank(stranger);
        vm.expectRevert(FairnessAttestation.NotAgentIdHolder.selector);
        att.attest();
    }

    function test_handleWithoutOwnershipReverts() public {
        // Dave has a handle string but is NOT the owner of that tokenId.
        registry.setHandle(dave, "alice"); // ALICE_ID is owned by alice
        vm.prank(dave);
        vm.expectRevert(FairnessAttestation.NotAgentIdHolder.selector);
        att.attest();
    }

    function test_holderWhoNeverClaimedReverts() public {
        vm.prank(carol);
        vm.expectRevert(FairnessAttestation.NotFreeClaimer.selector);
        att.attest();
        assertEq(att.attestationCount(), 0);
        assertFalse(att.hasAttested(CAROL_ID));
    }

    // ---------- attesting ----------

    function test_claimerAttestsOnce() public {
        vm.expectEmit(true, true, false, true);
        emit FairnessAttestation.Attested(ALICE_ID, alice, block.timestamp);
        vm.prank(alice);
        att.attest();

        assertEq(att.attestationCount(), 1);
        assertTrue(att.hasAttested(ALICE_ID));
        assertEq(att.attestedAt(ALICE_ID), block.timestamp);
    }

    function test_secondAttestReverts() public {
        vm.startPrank(alice);
        att.attest();
        vm.expectRevert(FairnessAttestation.AlreadyAttested.selector);
        att.attest();
        vm.stopPrank();
        assertEq(att.attestationCount(), 1);
    }

    function test_countIncrementsAcrossClaimers() public {
        vm.prank(alice);
        att.attest();
        vm.warp(block.timestamp + 3600);
        vm.prank(bob);
        att.attest();

        assertEq(att.attestationCount(), 2);
        assertTrue(att.hasAttested(ALICE_ID));
        assertTrue(att.hasAttested(BOB_ID));
        assertEq(att.attestedAt(ALICE_ID), 1_800_000_000);
        assertEq(att.attestedAt(BOB_ID), 1_800_000_000 + 3600);
    }

    function test_viewsBeforeAttest() public view {
        assertFalse(att.hasAttested(ALICE_ID));
        assertEq(att.attestedAt(ALICE_ID), 0);
        assertFalse(att.hasAttested(12345));
        assertEq(att.attestedAt(12345), 0);
    }

    function test_tokenIdKeyedAcrossWallets() public {
        // Alice attests with her Agent ID.
        vm.prank(alice);
        att.attest();
        assertEq(att.attestationCount(), 1);

        // The same Agent ID (same handle/tokenId) is now held by Dave's
        // wallet. The attestation belongs to the tokenId: Dave cannot
        // attest again, and Alice (no longer the holder) cannot attest
        // at all.
        registry.setHandle(alice, "");
        registry.setHandle(dave, "alice");
        registry.setOwner(ALICE_ID, dave);

        vm.prank(dave);
        vm.expectRevert(FairnessAttestation.AlreadyAttested.selector);
        att.attest();

        vm.prank(alice);
        vm.expectRevert(FairnessAttestation.NotAgentIdHolder.selector);
        att.attest();

        assertEq(att.attestationCount(), 1);
        assertTrue(att.hasAttested(ALICE_ID));
    }
}
