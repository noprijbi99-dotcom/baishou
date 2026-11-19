// SPDX-License-Identifier: MIT
// BAISHOU - local deploy stack (anvil, no fork) for smoke legs that
// need time warps (live testnet cannot warp; public fork RPCs have
// no archive state — "missing trie node"). The src/ bytecode is IDENTICAL
// to the testnet/mainnet deploys; only WBNB/Factory/Registry are mocks.
// All roles = deployer. Env: DEPLOYER_PRIVATE_KEY.
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {MockWBNB, MockFactory, MockRegistry} from "../test/mocks/Mocks.sol";

contract DeployLocal is Script {
    address public constant SENTINEL = 0x0000000000000000000000000000000000000001;

    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        vm.startBroadcast(deployerKey);

        MockWBNB wbnb = new MockWBNB();
        MockFactory factory = new MockFactory();
        MockRegistry registry = new MockRegistry();
        AgentToken token = new AgentToken("BAISHOU", "BAISHOU", address(wbnb), address(factory), SENTINEL, SENTINEL);
        AgentMint mint = new AgentMint(
            AgentMint.Config({
                token: address(token),
                registrar: address(registry),
                treasury: deployer,
                feeTreasury: deployer,
                admin: deployer,
                wbnb: address(wbnb),
                swapFeeBps: 30,
                unblockable: new address[](0),
                priceDiv: 1
            })
        );
        token.initialize(address(mint));

        vm.stopBroadcast();

        console.log("MockWBNB:", address(wbnb));
        console.log("MockFactory:", address(factory));
        console.log("MockRegistry:", address(registry));
        console.log("AgentToken:", address(token));
        console.log("AgentMint:", address(mint));
        console.log("Pair:", token.pair());
        console.log("deployer:", deployer);
    }
}
