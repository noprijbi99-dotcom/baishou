// SPDX-License-Identifier: MIT
// BAISHOU — AgentVote testnet smoke (TESTNET ONLY, chain 97).
// The real Agent ID registry exists on mainnet only, so this deploys the
// MockRegistry, seeds three test Agent IDs (alice/bob/carol from
// testnet-test-users.json), deploys AgentVote, casts votes, changes one,
// and reads everything back. (The non-holder revert is checked separately
// with an eth_call after deploy — a reverting broadcast tx would abort
// the whole forge broadcast.)
//
// Env: DEPLOYER_PRIVATE_KEY, ALICE_PRIVATE_KEY, BOB_PRIVATE_KEY,
//      CAROL_PRIVATE_KEY (keys are read from the repo key files by the
//      caller and passed via env — never printed).
// Example:
//   forge script script/DeployVoteTestnet.s.sol:DeployVoteTestnet \
//     --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545/ --broadcast
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentVote} from "../src/AgentVote.sol";
import {MockRegistry} from "../test/mocks/Mocks.sol";

contract DeployVoteTestnet is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 aliceKey = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 bobKey = vm.envUint("BOB_PRIVATE_KEY");
        uint256 carolKey = vm.envUint("CAROL_PRIVATE_KEY");
        address alice = vm.addr(aliceKey);
        address bob = vm.addr(bobKey);
        address carol = vm.addr(carolKey);

        // 1) Registry + vote contract + seed test Agent IDs.
        vm.startBroadcast(deployerKey);
        MockRegistry registry = new MockRegistry();
        AgentVote vote = new AgentVote(address(registry));
        registry.setHandle(alice, "alice");
        registry.setOwner(uint256(keccak256(bytes("alice"))), alice);
        registry.setHandle(bob, "bob");
        registry.setOwner(uint256(keccak256(bytes("bob"))), bob);
        registry.setHandle(carol, "carol");
        registry.setOwner(uint256(keccak256(bytes("carol"))), carol);
        vm.stopBroadcast();

        console.log("MockRegistry:", address(registry));
        console.log("AgentVote:", address(vote));
        console.log("DEADLINE:", vote.DEADLINE());

        // 2) Votes: alice Q0->2, bob Q0->2, carol Q0->3, alice changes Q0->1,
        //    alice Q3->2.
        vm.startBroadcast(aliceKey);
        vote.vote(0, 2);
        vm.stopBroadcast();
        vm.startBroadcast(bobKey);
        vote.vote(0, 2);
        vm.stopBroadcast();
        vm.startBroadcast(carolKey);
        vote.vote(0, 3);
        vm.stopBroadcast();
        vm.startBroadcast(aliceKey);
        vote.vote(0, 1);
        vote.vote(3, 2);
        vm.stopBroadcast();

        // 3) Read back (off-chain reads against the live testnet state).
        uint256[4] memory r0 = vote.getResults(0);
        uint256[4] memory r3 = vote.getResults(3);
        console.log("Q0 opt0/opt1:", r0[0], r0[1]);
        console.log("Q0 opt2/opt3:", r0[2], r0[3]);
        console.log("Q3 opt0/opt1:", r3[0], r3[1]);
        console.log("Q3 opt2/opt3:", r3[2], r3[3]);
        console.log("voterCount:", vote.voterCount());
        require(r0[0] == 0 && r0[1] == 1 && r0[2] == 1 && r0[3] == 1, "Q0 tally wrong");
        require(r3[2] == 1, "Q3 tally wrong");
        require(vote.voterCount() == 3, "voterCount wrong");

        uint256 aliceId = uint256(keccak256(bytes("alice")));
        require(vote.hasVoted(aliceId, 0), "alice hasVoted Q0 false");
        (bool voted, uint256 opt) = vote.myVote(aliceId, 0);
        require(voted && opt == 1, "alice myVote wrong");
        console.log("SMOKE OK");
    }
}
