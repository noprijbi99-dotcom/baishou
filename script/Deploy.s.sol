// SPDX-License-Identifier: MIT
// BAISHOU - deploy script (TESTNET ONLY, chain 97).
// Urutan deploy:
//   1. (opsional) MockRegistry dari test/mocks/Mocks.sol — kalau env REGISTRAR
//      kosong. Registry Agent ID resmi 0x60B9...022F HANYA ada di mainnet
//      (tidak ada code di testnet -> semua mint revert NoAgent).
//   2. AgentToken("BAISHOU", "BAISHOU", WBNB, FACTORY, POOL_MANAGER, INFINITY_VAULT)
//   3. AgentMint(Config{ token, registrar, treasury, feeTreasury, admin,
//      wbnb, swapFeeBps=30, unblockable=[], priceDiv=1 })
//   4. token.initialize(address(mint))
// Semua role (treasury, feeTreasury, admin) = alamat deployer.
// JANGAN jalankan di mainnet dari script ini tanpa review independen.
//   DEPLOYER_PRIVATE_KEY, WBNB, FACTORY, POOL_MANAGER, INFINITY_VAULT,
//   REGISTRAR (opsional; kosong = deploy MockRegistry)
// Contoh:
//   forge script script/Deploy.s.sol:DeployBaishou \
//     --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545/ --broadcast
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {MockRegistry} from "../test/mocks/Mocks.sol";

contract DeployBaishou is Script {
    address public constant SENTINEL = 0x0000000000000000000000000000000000000001;

    function run() public {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);
        address wbnb = vm.envAddress("WBNB");
        address factory = vm.envAddress("FACTORY");
        // PoolManager / InfinityVault resmi Pancake Infinity TIDAK ditemukan
        // di testnet (3x pencarian + eth_getCode alamat mainnet = 0x).
        // Pakai sentinel 0x...0001 bila env kosong: AgentToken hanya
        // memakainya di rejects() (transfer KE alamat itu ditolak) dan
        // _isOtherPair (no-code -> false). BUKAN address(0): burn exit
        // memakai to == address(0) sebagai jalur burn di _update.
        address poolManager = vm.envOr("POOL_MANAGER", SENTINEL);
        address infinityVault = vm.envOr("INFINITY_VAULT", SENTINEL);
        address registrar = vm.envOr("REGISTRAR", address(0));

        vm.startBroadcast(deployerKey);

        if (registrar == address(0)) {
            registrar = address(new MockRegistry());
            console.log("MockRegistry deployed:", registrar);
        }
        AgentToken token = new AgentToken("BAISHOU", "BAISHOU", wbnb, factory, poolManager, infinityVault);
        console.log("AgentToken deployed:", address(token));
        console.log("Pair:", token.pair());

        address[] memory unblockable = new address[](0);
        AgentMint mint = new AgentMint(
            AgentMint.Config({
                token: address(token),
                registrar: registrar,
                treasury: deployer,
                feeTreasury: deployer,
                admin: deployer,
                wbnb: wbnb,
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
        console.log("registrar:", registrar);
        console.log("wbnb:", wbnb);
        console.log("factory:", factory);
        console.log("poolManager:", poolManager);
        console.log("infinityVault:", infinityVault);
    }
}
