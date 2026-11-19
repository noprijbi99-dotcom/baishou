// SPDX-License-Identifier: MIT
// BAISHOU - deploy script (MAINNET ONLY, chain 56).
// MINT STAYS CLOSED: the contract is born with paused = true and the sale has NOT
// started (v2: saleStartTime = 0 — the 14-day target clock is not running, there is
// no time bomb from deploy). This script does NOT call startSale,
// setPaused(false), mint, or any seeding.
// Deployment order:
//   1. AgentToken("BAISHOU", "BAISHOU", WBNB, FACTORY, POOL_MANAGER, INFINITY_VAULT)
//   2. AgentMint(Config{ token, registrar, treasury, feeTreasury, admin,
//      wbnb, swapFeeBps=30, unblockable=[], priceDiv=1 })
//   3. token.initialize(address(mint))
//
// ROLES (IMMUTABLE — locked once in the constructor, cannot be changed):
//   treasury = feeTreasury = admin = the user's main wallet
//   0x319581821414b324Dd5Db9795e42E7ee3A287900
// Reason: no multisig yet; treasury funds land in the user's own wallet
// and can be moved to a multisig later; admin/pause is in the user's hands.
// The deployer (new mainnet key) holds NO role at all — it only pays gas.
//
// MAINNET ADDRESSES (all verified to have code on chain 56, block
// 134.461.092, 19 Nov 2026 — see DEPLOY-MAINNET.md):
//   Official Agent ID Registrar : 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
//   WBNB                     : 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c (symbol() = "WBNB")
//   PancakeSwap V2 factory   : 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 (allPairsLength() = 3.729.190)
//   Infinity CL PoolManager  : 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b
//   InfinityVault            : 0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F (BscScan: "InfinityVault")
// Do NOT use the 0x...0001 sentinel on mainnet. Do NOT deploy MockRegistry.
// This script REVERTS if any of the addresses above has no code.
//
// Required env: DEPLOYER_PRIVATE_KEY (NEW mainnet key, mode 600).
// Example:
//   forge script script/DeployMainnet.s.sol:DeployBaishouMainnet \
//     --rpc-url https://bsc-dataseed.binance.org/ --broadcast
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract DeployBaishouMainnet is Script {
    // The user's main wallet — holder of ALL roles (immutable).
    address public constant USER_WALLET = 0x319581821414b324Dd5Db9795e42E7ee3A287900;
    // Official Binance Agent ID registry (mainnet).
    address public constant REGISTRAR = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address public constant POOL_MANAGER = 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b;
    address public constant INFINITY_VAULT = 0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F;

    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        require(deployer != USER_WALLET, "deployer must be a fresh key, not the user wallet");

        // Layered defense: every external address must have code
        // on mainnet AT deploy time. If even one is empty -> revert, no
        // half-finished broadcast.
        require(REGISTRAR.code.length > 0, "registrar has no code");
        require(WBNB.code.length > 0, "wbnb has no code");
        require(FACTORY.code.length > 0, "factory has no code");
        require(POOL_MANAGER.code.length > 0, "poolManager has no code");
        require(INFINITY_VAULT.code.length > 0, "infinityVault has no code");

        vm.startBroadcast(deployerKey);

        AgentToken token = new AgentToken("BAISHOU", "BAISHOU", WBNB, FACTORY, POOL_MANAGER, INFINITY_VAULT);
        console.log("AgentToken deployed:", address(token));
        console.log("Pair:", token.pair());

        address[] memory unblockable = new address[](0);
        AgentMint mint = new AgentMint(
            AgentMint.Config({
                token: address(token),
                registrar: REGISTRAR,
                treasury: USER_WALLET,
                feeTreasury: USER_WALLET,
                admin: USER_WALLET,
                wbnb: WBNB,
                swapFeeBps: 30,
                unblockable: unblockable,
                priceDiv: 1
            })
        );
        console.log("AgentMint deployed:", address(mint));

        token.initialize(address(mint));
        console.log("token.initialize(mint) done; minter:", token.minter());

        vm.stopBroadcast();

        console.log("deployer:", deployer);
        console.log("treasury/feeTreasury/admin:", USER_WALLET);
        console.log("registrar:", REGISTRAR);
        console.log("wbnb:", WBNB);
        console.log("factory:", FACTORY);
        console.log("poolManager:", POOL_MANAGER);
        console.log("infinityVault:", INFINITY_VAULT);
        console.log("MINT STAYS CLOSED: paused=true, saleStartTime=0. No startSale called.");
    }
}
