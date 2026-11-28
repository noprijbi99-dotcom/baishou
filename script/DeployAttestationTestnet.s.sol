// SPDX-License-Identifier: MIT
// BAISHOU — FairnessAttestation testnet smoke (TESTNET ONLY, chain 97).
// The real Agent ID registry and AgentMint exist on mainnet only, so this
// deploys MockRegistry + MockAgentMint, seeds three test Agent IDs
// (alice/bob/carol from testnet-test-users.json), marks alice+bob as free
// claimers (carol is NOT), deploys FairnessAttestation, attests from alice
// and bob, and reads everything back. (The non-claimer and non-holder
// reverts are checked separately with eth_call after deploy — a reverting
// broadcast tx would abort the whole forge broadcast.)
//
// Env: DEPLOYER_PRIVATE_KEY, ALICE_PRIVATE_KEY, BOB_PRIVATE_KEY,
//      CAROL_PRIVATE_KEY (keys are read from the repo key files by the
//      caller and passed via env — never printed).
// Example:
//   forge script script/DeployAttestationTestnet.s.sol:DeployAttestationTestnet \
//     --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545/ --broadcast
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {FairnessAttestation} from "../src/FairnessAttestation.sol";
import {MockRegistry, MockAgentMint} from "../test/mocks/Mocks.sol";

contract DeployAttestationTestnet is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        uint256 aliceKey = vm.envUint("ALICE_PRIVATE_KEY");
        uint256 bobKey = vm.envUint("BOB_PRIVATE_KEY");
        uint256 carolKey = vm.envUint("CAROL_PRIVATE_KEY");
        address alice = vm.addr(aliceKey);
        address bob = vm.addr(bobKey);
        address carol = vm.addr(carolKey);
        uint256 aliceId = uint256(keccak256(bytes("alice")));
        uint256 bobId = uint256(keccak256(bytes("bob")));
        uint256 carolId = uint256(keccak256(bytes("carol")));

        // 1) Mocks + attestation contract + seed test Agent IDs and claims.
        vm.startBroadcast(deployerKey);
        MockRegistry registry = new MockRegistry();
        MockAgentMint mint = new MockAgentMint();
        FairnessAttestation att = new FairnessAttestation(address(registry), address(mint));
        registry.setHandle(alice, "alice");
        registry.setOwner(aliceId, alice);
        registry.setHandle(bob, "bob");
        registry.setOwner(bobId, bob);
        registry.setHandle(carol, "carol");
        registry.setOwner(carolId, carol);
        mint.setClaimedFree(aliceId, true);
        mint.setClaimedFree(bobId, true);
        // carol deliberately NOT marked as a free claimer.
        vm.stopBroadcast();

        console.log("MockRegistry:", address(registry));
        console.log("MockAgentMint:", address(mint));
        console.log("FairnessAttestation:", address(att));
        console.log("attestationCount at deploy:", att.attestationCount());
        require(att.attestationCount() == 0, "count not 0 at deploy");
        require(address(att.registrar()) == address(registry), "registrar pointer wrong");
        require(address(att.agentMint()) == address(mint), "agentMint pointer wrong");

        // 2) Attestations: alice and bob (both claimers).
        vm.startBroadcast(aliceKey);
        att.attest();
        vm.stopBroadcast();
        vm.startBroadcast(bobKey);
        att.attest();
        vm.stopBroadcast();

        // 3) Read back (off-chain reads against the live testnet state).
        console.log("attestationCount:", att.attestationCount());
        console.log("alice attestedAt:", att.attestedAt(aliceId));
        console.log("bob attestedAt:", att.attestedAt(bobId));
        require(att.attestationCount() == 2, "count wrong");
        require(att.hasAttested(aliceId), "alice hasAttested false");
        require(att.hasAttested(bobId), "bob hasAttested false");
        require(!att.hasAttested(carolId), "carol hasAttested true");
        require(att.attestedAt(aliceId) != 0, "alice attestedAt 0");
        require(att.attestedAt(bobId) != 0, "bob attestedAt 0");
        require(att.attestedAt(carolId) == 0, "carol attestedAt nonzero");
        console.log("SMOKE OK");
    }
}
