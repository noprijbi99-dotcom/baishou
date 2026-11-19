// SPDX-License-Identifier: MIT
// BAISHOU - deploy script (MAINNET ONLY, chain 56).
// MINT TETAP TUTUP: kontrak lahir dengan paused = true. Script ini TIDAK
// memanggil setPaused(false), openEarly, mint, atau seed apa pun.
// Urutan deploy:
//   1. AgentToken("BAISHOU", "BAISHOU", WBNB, FACTORY, POOL_MANAGER, INFINITY_VAULT)
//   2. AgentMint(Config{ token, registrar, treasury, feeTreasury, admin,
//      wbnb, swapFeeBps=30, unblockable=[], priceDiv=1 })
//   3. token.initialize(address(mint))
//
// PERAN (IMMUTABLE — dikunci sekali di constructor, tidak bisa diganti):
//   treasury = feeTreasury = admin = dompet utama user
//   0x319581821414b324Dd5Db9795e42E7ee3A287900
// Alasan: multisig belum ada; dana treasury mendarat di dompet user sendiri
// dan bisa dipindah ke multisig nanti; admin/pause di tangan user.
// Deployer (key mainnet baru) TIDAK pegang peran apa pun — hanya bayar gas.
//
// ALAMAT MAINNET (semua diverifikasi ada code-nya di chain 56, block
// 134.461.092, 19 Nov 2026 — lihat DEPLOY-MAINNET.md):
//   Registrar Agent ID resmi : 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F
//   WBNB                     : 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c (symbol() = "WBNB")
//   PancakeSwap V2 factory   : 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73 (allPairsLength() = 3.729.190)
//   Infinity CL PoolManager  : 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b
//   InfinityVault            : 0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F (BscScan: "InfinityVault")
// JANGAN pakai sentinel 0x...0001 di mainnet. JANGAN deploy MockRegistry.
// Script ini REVERT bila salah satu alamat di atas tidak ada code-nya.
//
// Env yang dibutuhkan: DEPLOYER_PRIVATE_KEY (key mainnet BARU, mode 600).
// Contoh:
//   forge script script/DeployMainnet.s.sol:DeployBaishouMainnet \
//     --rpc-url https://bsc-dataseed.binance.org/ --broadcast
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract DeployBaishouMainnet is Script {
    // Dompet utama user — pemegang SEMUA peran (immutable).
    address public constant USER_WALLET = 0x319581821414b324Dd5Db9795e42E7ee3A287900;
    // Registry Agent ID resmi Binance (mainnet).
    address public constant REGISTRAR = 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F;
    address public constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address public constant FACTORY = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address public constant POOL_MANAGER = 0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b;
    address public constant INFINITY_VAULT = 0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F;

    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        require(deployer != USER_WALLET, "deployer must be a fresh key, not the user wallet");

        // Pertahanan berlapis: semua alamat eksternal wajib ada code-nya
        // di mainnet SAAT deploy. Kalau satu saja kosong -> revert, tidak
        // ada broadcast setengah jalan.
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
        console.log("MINT STAYS CLOSED: paused=true (initial state). No setPaused(false) called.");
    }
}
