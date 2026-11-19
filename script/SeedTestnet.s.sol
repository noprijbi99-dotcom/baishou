// SPDX-License-Identifier: MIT
// BAISHOU - seed MockRegistry di testnet (chain 97) SETELAH Deploy.s.sol.
// Isi env: REGISTRAR, DEPLOYER_PRIVATE_KEY, TEST_USER_1, TEST_USER_2.
// Seed: deployer -> handle "alice", TEST_USER_1 -> "bob",
// TEST_USER_2 -> "carol". id = uint256(keccak256(bytes(handle))).
// MockRegistry.setHandle/setOwner tanpa access control (mock saja).
//   forge script script/SeedTestnet.s.sol:SeedTestnet \
//     --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545/ --broadcast
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {MockRegistry} from "../test/mocks/Mocks.sol";

contract SeedTestnet is Script {
    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        MockRegistry registry = MockRegistry(vm.envAddress("REGISTRAR"));
        address user1 = vm.envAddress("TEST_USER_1");
        address user2 = vm.envAddress("TEST_USER_2");

        vm.startBroadcast(deployerKey);
        registry.setHandle(deployer, "alice");
        registry.setOwner(uint256(keccak256(bytes("alice"))), deployer);
        registry.setHandle(user1, "bob");
        registry.setOwner(uint256(keccak256(bytes("bob"))), user1);
        registry.setHandle(user2, "carol");
        registry.setOwner(uint256(keccak256(bytes("carol"))), user2);
        vm.stopBroadcast();

        console.log("registry:", address(registry));
        console.log("alice id:", uint256(keccak256(bytes("alice"))), "owner:", deployer);
        console.log("bob   id:", uint256(keccak256(bytes("bob"))), "owner:", user1);
        console.log("carol id:", uint256(keccak256(bytes("carol"))), "owner:", user2);
    }
}
