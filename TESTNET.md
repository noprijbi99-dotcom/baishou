# BAISHOU — BSC Testnet (chain 97) — STATUS: ⛔ BLOCKED AT FAUCET

**Tanggal:** 19 Nov 2026, ~13:45 WIB (06:45 UTC)
**Deployer testnet (segar):** `0xad5d51D7eE879C47F288F48559BC1914F771fB62`
**Saldo tBNB deployer:** 0 (dicek live via RPC) — **belum ada dana untuk deploy.**
**Nonce deployer:** 0 — alamat deploy hasil dry-run di bawah masih berlaku
selama tidak ada tx lain dari deployer sebelum broadcast.

> **BELUM ADA KONTRAK YANG TER-DEPLOY.** Tidak ada tx hash deploy, tidak ada
> alamat kontrak live, tidak ada smoke test. File ini mendokumentasikan
> persiapan yang selesai + blocker + cara melanjutkan. Jangan kutip alamat
> "predicted" di bawah sebagai alamat live.

## 1. Blocker: faucet tBNB tidak bisa diklaim dari VM ini

### Jalur resmi BNB Chain (dicoba live, gagal)
- Faucet: `https://testnet.bnbchain.org/faucet-smart` → 301 ke
  `https://www.bnbchain.org/en/testnet-faucet`.
- Frontend-nya (Next.js, `static.bnbchain.org/faucet-ui`) memanggil faucet
  lewat WebSocket **`wss://testnet.bnbchain.org/faucet-smart/api`** dengan
  payload `{tier:0, url:<address>, symbol:"tBNB", captcha:<hCaptcha token>}`
  (sitekey hCaptcha `d9a9ee67-74da-4601-9f31-efe6a297a5cc`).
- Probe WS langsung dari VM (payload persis UI, captcha kosong): server
  menjawab **`{"error": "insufficient BNB on BSC mainnet (require >=0.002BNB)"}`**
  — dicek sebelum/selain validasi captcha. Saldo mainnet deployer = 0
  (dicek live via `bsc-dataseed.binance.org`), jadi klaim ditolak.
- Artinya faucet resmi butuh **DUA** hal yang hanya bisa dari tangan user:
  1. saldo **≥ 0,002 BNB mainnet di alamat deployer** (hanya hold/cek, tidak
     dibelanjakan — tapi tetap keputusan dana mainnet, di luar wewenang agen);
  2. **hCaptcha di browser** (agen subagent tidak punya browser).

### Jalur alternatif (diselidiki, semua buntu dari VM)
| Faucet | Hasil |
|---|---|
| Chainstack `faucet.chainstack.com/bnb-testnet-faucet` | Butuh akun + API key Chainstack + 0,002 ETH mainnet. |
| QuickNode `faucet.quicknode.com/.../bnb-testnet` | FAQ di JS-nya sendiri: butuh "a small mainnet balance" juga. |
| Chainlink `faucets.chain.link` (BNB Chain Testnet terdaftar) | `POST /api/faucet {turnstileToken, requests, walletAddress}` — butuh **Cloudflare Turnstile token dari browser** + (bila 401 `REQUEST_SIGNATURE`) tanda tangan pesan `"Welcome to Chainlink Faucets! ... Wallet address: <addr>"` (bagian tanda tangan ini BISA dilakukan agen via `cast wallet sign`, tapi token Turnstile tidak bisa). |
| Zalalena `faucet.zalalena.com/bsc` | Klaim "no balance", tapi tetap butuh captcha. |

**Yang TIDAK dilakukan (sesuai perintah):** tidak minta dana mainnet, tidak
memakai wallet mainnet user (`0x3195…8900`, `0x4981…8C21`) sebagai alamat
klaim, tidak mengakali dengan wallet lain.

### Cara membuka blokir (keputusan user / koordinator)
- **Opsi A (paling mudah):** user kirim **0,002 BNB mainnet** ke
  `0xad5d51D7eE879C47F288F48559BC1914F771fB62` (hold saja, faucet hanya cek
  saldo — dana tetap milik user di wallet testnet itu), lalu user buka
  `https://testnet.bnbchain.org/faucet-smart` di browser/HP, paste alamat
  di atas, selesaikan hCaptcha, klaim **0,3 tBNB** (cukup untuk deploy +
  seed + smoke test; estimasi total gas deploy ≈ 0,00104 BNB — lihat §4).
- **Opsi B (tanpa dana mainnet):** user buka `https://faucets.chain.link`
  di browser, connect wallet deployer (atau kirim alamat + tanda tangan
  pesan di atas dari agen), selesaikan Turnstile, klaim tBNB.
- Setelah saldo deployer > 0, jalankan §5 — deploy tinggal satu perintah.

## 2. Yang sudah diverifikasi on-chain (bukti live, RPC testnet)

RPC: `https://data-seed-prebsc-1-s1.binance.org:8545/` — chainId 97,
block 143.592.212 saat pengecekan.

| Alamat | Status |
|---|---|
| WBNB testnet `0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd` | ✅ ada code (`eth_getCode` → bytecode `0x6060…`); sumber terverifikasi di BscScan testnet (dicek via Etherscan V2 `getsourcecode`). |
| PancakeSwap V2 factory testnet `0x6725F303b657a9451d8BA641348b6761A6CC7a17` | ✅ ada code (`0x6080…`); cocok dengan dokumentasi resmi PancakeSwap (`developer.pancakeswap.finance/contracts/v2/addresses` → BSC Testnet). |
| Registry Agent ID mainnet `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` | ❌ **tidak ada code di testnet** (`eth_getCode` → `0x`) — sesuai dugaan; JANGAN dipakai (semua mint akan revert `NoAgent`). |
| InfinityVault mainnet `0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F` | ❌ tidak ada code di testnet (`0x`). |

## 3. Keputusan: PoolManager / InfinityVault → sentinel

Alamat resmi Pancake **Infinity** (PoolManager + InfinityVault) testnet
**tidak ditemukan** setelah 3x pencarian (dokumen developer PancakeSwap,
DeepWiki `infinity-universal-router`/`infinity-periphery`, BscScan) +
`eth_getCode` alamat InfinityVault mainnet di testnet = `0x`.

Dipakai sentinel **`0x0000000000000000000000000000000000000001`** untuk
keduanya (default di `script/Deploy.s.sol` bila env kosong). Alasan:
- `AgentToken` hanya memakai kedua alamat itu di `rejects()`: transfer **KE**
  alamat itu ditolak — tidak ada yang akan transfer ke `0x…0001`.
- `_isOtherPair()`: alamat tanpa code → `false`, jadi tidak memblokir
  transfer normal.
- **BUKAN `address(0)`**: `AgentToken._update` memakai `to == address(0)`
  sebagai jalur burn (dipakai `exit()`); sentinel menghindari tabrakan
  semantik itu.
- Mainnet nanti: ganti dengan alamat Infinity resmi mainnet sebelum deploy
  produksi (bukan sentinel).

## 4. Yang sudah siap (tanpa tBNB)

- **Wallet deployer segar:** `0xad5d51D7eE879C47F288F48559BC1914F771fB62`
  — private key di `~/workspace/baishou/testnet-deployer-key.json`
  (mode 600, masuk `.gitignore`, **JANGAN commit / tampilkan isinya**).
- **Test users (Agent ID bob/carol):**
  - bob `0x8f44a96c0C3936c5768fF1a1cDa8574aE841651E`
  - carol `0xC93e5BC6020dBC63cB6B3ddF7E42a4b02C9244cf`
  - key di `~/workspace/baishou/testnet-test-users.json` (mode 600, gitignored).
  - deployer sendiri = "alice".
- **Script deploy lengkap:** `script/Deploy.s.sol` — baca env
  `DEPLOYER_PRIVATE_KEY, WBNB, FACTORY, POOL_MANAGER, INFINITY_VAULT,
  REGISTRAR` (REGISTRAR kosong = deploy `MockRegistry` dari
  `test/mocks/Mocks.sol`). Config: treasury = feeTreasury = admin =
  deployer; `swapFeeBps = 30`; `priceDiv = 1` (nilai produksi).
- **Script seed registry:** `script/SeedTestnet.s.sol` — seed alice/bob/carol
  (`id = uint256(keccak256(bytes(handle)))`, `setHandle` + `setOwner`).
- **`forge build` OK; `forge test`: 139 passed / 0 failed / 0 skipped**
  (dijalankan ulang 19 Nov 2026 sesudah script ditulis).
- **Dry-run simulasi deploy terhadap state testnet live BERHASIL**
  (`forge script` tanpa `--broadcast`, 19 Nov 2026): MockRegistry +
  AgentToken + AgentMint + `token.initialize(mint)` semua lolos simulasi;
  total gas ≈ 10.385.539; estimasi biaya ≈ **0,00104 BNB** pada 0,1 gwei
  (0,3 tBNB dari faucet resmi lebih dari cukup).
- **Alamat hasil dry-run (PREDIKSI — berlaku selama nonce deployer tetap 0):**
  - MockRegistry: `0x1e670b339e96c520e4d42ad5cf832e80968c2e9e`
  - AgentToken: `0xd5aa2bf99c020a13b24326f527b187f15637a038`
  - AgentMint: `0x71fdda39dae64ca346024e5d41f2587818d1fab8`
  - Pair (BAISHOU/WBNB): tercetak saat broadcast nyata (`token.pair()`).
  - ⚠️ Ini BUKAN alamat live — jangan disebar sebagai alamat kontrak.
- **Verifikasi source (jalur sudah dites):** Etherscan V2 `contract`
  module **bekerja di chain 97** (probe `getsourcecode` WBNB testnet
  mengembalikan source). Rencana pasca-deploy: `forge verify-contract`
  ke testnet BscScan (chain 97) dengan API key Etherscan V2 dari konektor
  (`custom.etherscan-v2`); bila gagal, coba Sourcify; bila keduanya gagal,
  laporkan sebagai kekurangan.
- **`.gitignore` diperbarui:** `testnet-deployer-key.json`,
  `testnet-test-users.json`, `/broadcast/*/97/` (log broadcast testnet
  tidak di-commit; key tidak pernah masuk repo).

## 5. Cara melanjutkan (setelah tBNB masuk)

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd ~/workspace/baishou
export DEPLOYER_PRIVATE_KEY=$(python3 -c "import json;print(json.load(open('testnet-deployer-key.json'))['private_key'])")
export WBNB=0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
export FACTORY=0x6725F303b657a9451d8BA641348b6761A6CC7a17
# POOL_MANAGER / INFINITY_VAULT kosong -> sentinel 0x...0001
# REGISTRAR kosong -> deploy MockRegistry
forge script script/Deploy.s.sol:DeployBaishou \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545/ --broadcast

# Seed registry (isi REGISTRAR + TEST_USER_1/2 dari hasil deploy):
export REGISTRAR=<alamat MockRegistry>
export TEST_USER_1=0x8f44a96c0C3936c5768fF1a1cDa8574aE841651E
export TEST_USER_2=0xC93e5BC6020dBC63cB6B3ddF7E42a4b02C9244cf
forge script script/SeedTestnet.s.sol:SeedTestnet \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545/ --broadcast
```

Lalu verifikasi source + smoke test (belum jalan — menunggu dana):
1. `totalMinted` = 0, `opened()` = false, `paused` = true → `setPaused(false)` (admin = deployer).
2. Mint 1 share dari alice: `value = costOf(1) = 0,00168 tBNB` → `totalMinted` = 1, `balanceOf` token = 168.000.000.
3. `freeMint()` dari bob → `balanceOf` = 168.000.000, `freeClaimed` = 1.
4. `exit(1)` dari alice → refund 80% (0,001344 tBNB), `totalMinted` berkurang.
5. `participantCount()` ≥ 2, `isParticipant(id)` true.
6. JANGAN `setReviewPassed(true)` / renounce di testnet (gate review hanya mainnet).

## 6. Kontrak live / tx hash / link BscScan

_Belum ada — deploy tertahan di blocker §1. Diisi setelah broadcast._

| Kontrak | Alamat | Tx deploy | BscScan testnet |
|---|---|---|---|
| AgentToken | — | — | — |
| AgentMint | — | — | — |
| MockRegistry | — | — | — |
| Pair BAISHOU/WBNB | — | — | — |

## 7. Smoke test

_Belum dijalankan — menunggu dana faucet. Hasil per langkah + tx hash dicatat di sini setelah deploy._
