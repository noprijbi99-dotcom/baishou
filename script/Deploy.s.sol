// SPDX-License-Identifier: MIT
// BAISHOU - deploy script SKELETON. JANGAN DIJALANKAN - kontrak belum final.
// Urutan deploy (testnet dulu, semua jalur diuji, baru mainnet):
//   1. Deploy AgentToken("BAISHOU", "BAISHOU", WBNB, PancakeFactory, poolManager, infinityVault)
//   2. Deploy AgentMint(Config{ token, registrar=AgentID 0x60B9..., treasury, feeTreasury,
//      admin, quotaSigner, wbnb, swapFeeBps, unblockable, priceDiv=1, daySeconds=86400, dayOffset=0 })
//   3. token.initialize(address(mint))
//   4. Verifikasi source BscScan + Sourcify SEBELUM pengumuman.
//   5. admin.setPaused(false) HANYA saat peluncuran diumumkan.
// Alamat-alamat di bawah dibaca dari env saat waktunya tiba - JANGAN hardcode mainnet.
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {AgentMint} from "../src/AgentMint.sol";

contract DeployBaishou is Script {
    function run() public {
        // TODO(final): isi dari env (WBNB, FACTORY, REGISTRAR, TREASURY,
        // FEE_TREASURY, ADMIN, QUOTA_SIGNER, POOL_MANAGER, INFINITY_VAULT).
        // Deploy HANYA di testnet sampai review independen selesai.
        revert("DRAFT - kontrak belum final, jangan deploy");
    }
}
