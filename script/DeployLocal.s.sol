// SPDX-License-Identifier: MIT
// BAISHOU - deploy stack LOKAL (anvil tanpa fork) untuk smoke leg yang
// butuh warp waktu (live testnet tidak bisa warp; fork RPC publik tidak
// punya archive state — "missing trie node"). Bytecode src/ IDENTIK
// dengan deploy testnet/mainnet; hanya WBNB/Factory/Registry yang mock.
// Semua role = deployer. Env: DEPLOYER_PRIVATE_KEY.
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
