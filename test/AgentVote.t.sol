// SPDX-License-Identifier: MIT
// BAISHOU — AgentVote governance tests.
// Agent ID resolution mirrors AgentMint._agent():
//   id = uint256(keccak256(bytes(handleOf(user)))); ok = ownerOf(id) == user
// so the mock registry is seeded with BOTH the handle AND the owner.
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {AgentVote} from "../src/AgentVote.sol";
import {MockRegistry} from "./mocks/Mocks.sol";

contract AgentVoteTest is Test {
    AgentVote internal vote;
    MockRegistry internal registry;

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
        vote = new AgentVote(address(registry));

        registry.setHandle(alice, "alice");
        registry.setOwner(ALICE_ID, alice);
        registry.setHandle(bob, "bob");
        registry.setOwner(BOB_ID, bob);
        registry.setHandle(carol, "carol");
        registry.setOwner(CAROL_ID, carol);

        // Start well before the deadline.
        vm.warp(vote.DEADLINE() - 30 days);
    }

    // ---------- constants & options ----------

    function test_deadlineConstant() public view {
        // 2026-12-09 08:00:00 UTC.
        assertEq(vote.DEADLINE(), 1_796_803_200);
        assertEq(vote.QUESTIONS(), 4);
    }

    function test_optionCounts() public view {
        assertEq(vote.optionCount(0), 4);
        assertEq(vote.optionCount(1), 3);
        assertEq(vote.optionCount(2), 3);
        assertEq(vote.optionCount(3), 3);
    }

    function test_optionValues() public view {
        // Q0 pool-open threshold (paid shares)
        assertEq(vote.optionValue(0, 0), 168_000);
        assertEq(vote.optionValue(0, 1), 84_000);
        assertEq(vote.optionValue(0, 2), 42_000);
        assertEq(vote.optionValue(0, 3), 16_800);
        // Q1 base price (wei)
        assertEq(vote.optionValue(1, 0), 0.00168 ether);
        assertEq(vote.optionValue(1, 1), 0.00084 ether);
        assertEq(vote.optionValue(1, 2), 0.00336 ether);
        // Q2 free allocation (tokens)
        assertEq(vote.optionValue(2, 0), 168_000_000);
        assertEq(vote.optionValue(2, 1), 84_000_000);
        assertEq(vote.optionValue(2, 2), 336_000_000);
        // Q3 sale window (days)
        assertEq(vote.optionValue(3, 0), 14);
        assertEq(vote.optionValue(3, 1), 21);
        assertEq(vote.optionValue(3, 2), 30);
    }

    function test_badQuestionReverts() public {
        vm.prank(alice);
        vm.expectRevert(AgentVote.BadQuestion.selector);
        vote.vote(4, 0);
        vm.expectRevert(AgentVote.BadQuestion.selector);
        vote.getResults(4);
        vm.expectRevert(AgentVote.BadQuestion.selector);
        vote.optionCount(4);
        vm.expectRevert(AgentVote.BadQuestion.selector);
        vote.hasVoted(ALICE_ID, 4);
        vm.expectRevert(AgentVote.BadQuestion.selector);
        vote.myVote(ALICE_ID, 4);
    }

    function test_badOptionReverts() public {
        vm.prank(alice);
        vm.expectRevert(AgentVote.BadOption.selector);
        vote.vote(0, 4); // Q0 has options 0..3
        vm.prank(alice);
        vm.expectRevert(AgentVote.BadOption.selector);
        vote.vote(1, 3); // Q1 has options 0..2
        vm.expectRevert(AgentVote.BadOption.selector);
        vote.optionValue(3, 3);
    }

    // ---------- eligibility ----------

    function test_nonHolderCannotVote() public {
        vm.prank(stranger);
        vm.expectRevert(AgentVote.NotAgentIdHolder.selector);
        vote.vote(0, 0);
    }

    function test_handleWithoutOwnershipCannotVote() public {
        // Dave has a handle string but is NOT the owner of that tokenId.
        registry.setHandle(dave, "alice"); // ALICE_ID is owned by alice, not dave
        vm.prank(dave);
        vm.expectRevert(AgentVote.NotAgentIdHolder.selector);
        vote.vote(0, 0);
    }

    function test_agentIdOf() public view {
        (uint256 id, bool ok) = vote.agentIdOf(alice);
        assertEq(id, ALICE_ID);
        assertTrue(ok);
        (, ok) = vote.agentIdOf(stranger);
        assertFalse(ok);
    }

    // ---------- voting & tally ----------

    function test_holderCanVoteAndTally() public {
        vm.expectEmit(true, false, false, true);
        emit AgentVote.Voted(ALICE_ID, 0, 2);
        vm.prank(alice);
        vote.vote(0, 2);

        uint256[4] memory r = vote.getResults(0);
        assertEq(r[0], 0);
        assertEq(r[1], 0);
        assertEq(r[2], 1);
        assertEq(r[3], 0);
        assertEq(vote.voterCount(), 1);
        assertTrue(vote.hasVoted(ALICE_ID, 0));
        (bool voted, uint256 opt) = vote.myVote(ALICE_ID, 0);
        assertTrue(voted);
        assertEq(opt, 2);
    }

    function test_sameOptionTwiceCountsOnce() public {
        vm.startPrank(alice);
        vote.vote(1, 0);
        vote.vote(1, 0);
        vm.stopPrank();
        assertEq(vote.getResults(1)[0], 1);
        assertEq(vote.voterCount(), 1);
    }

    function test_voteChangeBeforeDeadlineMovesTally() public {
        vm.startPrank(alice);
        vote.vote(0, 0);
        vote.vote(0, 3);
        vm.stopPrank();
        uint256[4] memory r = vote.getResults(0);
        assertEq(r[0], 0);
        assertEq(r[3], 1);
        assertEq(vote.voterCount(), 1);
        (bool voted, uint256 opt) = vote.myVote(ALICE_ID, 0);
        assertTrue(voted);
        assertEq(opt, 3);
    }

    function test_resultsTallyAcrossVotersAndQuestions() public {
        vm.prank(alice);
        vote.vote(0, 1);
        vm.prank(bob);
        vote.vote(0, 1);
        vm.prank(carol);
        vote.vote(0, 3);
        vm.prank(alice);
        vote.vote(3, 2);
        vm.prank(bob);
        vote.vote(3, 0);

        uint256[4] memory r0 = vote.getResults(0);
        assertEq(r0[0], 0);
        assertEq(r0[1], 2);
        assertEq(r0[2], 0);
        assertEq(r0[3], 1);
        uint256[4] memory r3 = vote.getResults(3);
        assertEq(r3[0], 1);
        assertEq(r3[1], 0);
        assertEq(r3[2], 1);
        assertEq(r3[3], 0);
        // Three unique agents, even though five votes were cast.
        assertEq(vote.voterCount(), 3);
    }

    function test_voterCountUniqueAcrossQuestions() public {
        vm.startPrank(alice);
        vote.vote(0, 0);
        vote.vote(1, 0);
        vote.vote(2, 0);
        vote.vote(3, 0);
        vm.stopPrank();
        assertEq(vote.voterCount(), 1);
    }

    function test_tokenIdKeyedAcrossWallets() public {
        // Alice votes with her Agent ID.
        vm.prank(alice);
        vote.vote(2, 0);
        assertEq(vote.voterCount(), 1);

        // The same Agent ID (same handle/tokenId) is now held by Dave's
        // wallet. Dave voting must move the SAME tokenId's vote, not add
        // a second one: votes are keyed by tokenId, not by wallet.
        registry.setHandle(alice, "");
        registry.setHandle(dave, "alice");
        registry.setOwner(ALICE_ID, dave);

        vm.prank(dave);
        vote.vote(2, 2);
        uint256[4] memory r = vote.getResults(2);
        assertEq(r[0], 0);
        assertEq(r[2], 1);
        assertEq(vote.voterCount(), 1);
        (bool voted, uint256 opt) = vote.myVote(ALICE_ID, 2);
        assertTrue(voted);
        assertEq(opt, 2);

        // And Alice (no longer the holder) can no longer vote at all.
        vm.prank(alice);
        vm.expectRevert(AgentVote.NotAgentIdHolder.selector);
        vote.vote(2, 1);
    }

    // ---------- deadline ----------

    function test_voteAtDeadlineMinusOneWorks() public {
        vm.warp(vote.DEADLINE() - 1);
        vm.prank(alice);
        vote.vote(0, 0);
        assertEq(vote.getResults(0)[0], 1);
    }

    function test_revertAtAndAfterDeadline() public {
        vm.warp(vote.DEADLINE());
        vm.prank(alice);
        vm.expectRevert(AgentVote.VotingClosed.selector);
        vote.vote(0, 0);

        vm.warp(vote.DEADLINE() + 365 days);
        vm.prank(alice);
        vm.expectRevert(AgentVote.VotingClosed.selector);
        vote.vote(0, 0);
    }

    function test_resultsReadableAfterDeadline() public {
        vm.prank(alice);
        vote.vote(0, 1);
        vm.prank(bob);
        vote.vote(0, 1);
        vm.warp(vote.DEADLINE() + 90 days);
        assertEq(vote.getResults(0)[1], 2);
        assertEq(vote.voterCount(), 2);
        assertTrue(vote.hasVoted(ALICE_ID, 0));
        (bool voted, uint256 opt) = vote.myVote(BOB_ID, 0);
        assertTrue(voted);
        assertEq(opt, 1);
    }

    function test_hasVotedFalseBeforeVoting() public view {
        assertFalse(vote.hasVoted(ALICE_ID, 0));
        (bool voted,) = vote.myVote(ALICE_ID, 0);
        assertFalse(voted);
    }

    // ---------- fuzz ----------

    function testFuzz_voteNeverExceedsVoterCount(uint256 q, uint256 o) public {
        q = bound(q, 0, 3);
        o = bound(o, 0, q == 0 ? 3 : 2);
        vm.prank(alice);
        vote.vote(q, o);
        vm.prank(bob);
        vote.vote(q, o);
        uint256[4] memory r = vote.getResults(q);
        uint256 sum = r[0] + r[1] + r[2] + r[3];
        assertEq(sum, 2);
        assertEq(vote.voterCount(), 2);
    }
}
