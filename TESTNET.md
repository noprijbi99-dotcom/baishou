# BAISHOU — BSC Testnet (chain 97) — STATUS: ✅ DEPLOYED + SMOKE TEST LULUS

**Tanggal deploy:** 19 Nov 2026, ~14:05 WIB
**Deployer testnet (segar):** `0xad5d51D7eE879C47F288F48559BC1914F771fB62`
**Saldo tBNB deployer:** 0,3 masuk dari faucet (user) → **0,2888 tersisa** setelah deploy + seed + smoke test (termasuk 0,01 tBNB dikirim ke bob untuk gas).
**Nonce deployer saat deploy:** 0 — alamat hasil deploy SAMA PERSIS dengan prediksi dry-run §4.

> **KONTRAK LIVE.** Tx hash deploy, alamat, dan hasil smoke test di §6–§7.
> Blocker faucet §1 sudah lewat (user klaim 0,3 tBNB via faucet resmi +
> hCaptcha, 13:56 WIB).

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

**Deploy: 19 Nov 2026 ~14:05 WIB.** Catatan: broadcast pertama GAGAL
(`transaction gas price below minimum: gas tip cap 1, minimum needed
100000000`) — forge menebak priority fee 1 wei, padahal minimum testnet
0,1 gwei. Retry dengan `--with-gas-price 1000000000 --priority-gas-price
100000000` (1 gwei max, 0,1 gwei tip) sukses. Nonce deployer tetap 0 saat
retry, jadi alamat hasil = prediksi dry-run §4 persis.

| Kontrak | Alamat | Tx deploy | BscScan testnet |
|---|---|---|---|
| AgentToken | `0xd5Aa2BF99c020a13B24326F527B187f15637A038` | `0xb0d178330a935df2be1cf4f36fe063108038caca66e839b55ee5a98e0950a107` (gas 3.575.454) | https://testnet.bscscan.com/address/0xd5Aa2BF99c020a13B24326F527B187f15637A038 |
| AgentMint | `0x71fDdA39DAE64ca346024E5D41f2587818d1FaB8` | `0xaaeeb64b30d7e8b984055fa0660fcb2bb3f347342263936d0cb111dbf3d2b7f0` (gas 4.049.894) | https://testnet.bscscan.com/address/0x71fDdA39DAE64ca346024E5D41f2587818d1FaB8 |
| MockRegistry | `0x1E670b339e96c520E4D42aD5Cf832E80968C2E9E` | `0xb754325e6fcbf56628b5badb232a93a65fcb95d970042e60d30c8df6c850ef36` (gas 317.527) | https://testnet.bscscan.com/address/0x1E670b339e96c520E4D42aD5Cf832E80968C2E9E |
| Pair BAISHOU/WBNB | `0x238db3a329a29586d72d4857A08d683cb38f63e0` | dibuat saat deploy AgentToken (likuiditas 0 — pool buka di share 168.000) | https://testnet.bscscan.com/address/0x238db3a329a29586d72d4857A08d683cb38f63e0 |
| `token.initialize(mint)` | — | `0x8b7f76a8879b5d0ab5dbe796c5f731182c119fc3ec783ab760c1c70ffb0605ee` (gas 45.621) | — |

Total gas deploy: **7.988.496** (≈ 0,0008 tBNB pada tip efektif 0,1 gwei).
Seed registry (6 call, gas total 268.464): `0x629d9f449f2b5208a5048f3147e662e3944ad9501157c8802f31df9c8229f645`,
`0x61c99c1b6894f6588e1f8fe87803f6e3d68ed9e32d88dc4ba823dda4a9bd732e`,
`0x18db491f579d2b88e142e729392b40763d2c3010030c9856d00be1eb2c9bde19`,
`0x776b7064d2c474681c8c007df8bfeb4bc82efbb9b8ddf63adbb393832ca2de58`,
`0x8c7c2e938abc184cac284cdc9eac4a6be0fc3f481149693aa86ea8cc57a06dc1`,
`0x0c5ef747972a458215c059ec4a6d2378dcbd7477c638636e4b24adea6be3d938`
(alice/bob/carol ter-seed; `handleOf(alice)` = `"alice"` dicek live).

**Verifikasi source:**
- **Sourcify: ✅ KEDUANYA `exact_match`** (creation + runtime) —
  AgentToken job `6830c129-3d81-46b2-ae85-33af59934611`,
  AgentMint job `00b4c565-bfbb-40b4-ad79-4c18f245e0d1`
  (dicek via `GET /v2/contract/97/<address>`).
- **BscScan testnet: ❌ BELUM terverifikasi** — 3 rute dicoba dan semua
  gagal: (1) `forge verify-contract` + API key Etherscan V2 via surrogate
  → `Invalid API Key` (surrogate tidak di-swap untuk request dari binary
  forge, hanya lewat helper urllib); (2) submit manual V2 API
  `verifysourcecode` dengan flattened source → `Error!` generik;
  (3) submit manual dengan standard JSON (16 source) → `Error!` generik.
  Dugaan kuat: paket gratis Etherscan tidak mengizinkan *submission*
  verifikasi untuk chain 97 (modul `proxy` chain 97 saja sudah ditolak
  paket gratis; modul `contract` read jalan, write tidak). BUKAN masalah
  kode — Sourcify exact_match membuktikan bytecode cocok dengan source.
  BscScan tetap menampilkan kontrak + tx + saldo; source bisa dibaca
  lewat Sourcify. Coba lagi nanti dengan API key berbayar atau dari
  browser (BscScan verify form).

## 7. Smoke test

**Dijalankan 19 Nov 2026 ~14:07 WIB, SEMUA LULUS** (script `/tmp/smoke_test.sh`,
bukan di repo — key test hanya di variabel shell):

| # | Langkah | Tx | Hasil |
|---|---|---|---|
| 0 | Fund bob 0,01 tBNB (gas freeMint) | `0xae658ef09e86c8ceb5d7996d7ccb0f5ebf69780d07772b532a913229e99cd025` | ✅ status 1 |
| 1 | `setPaused(false)` [deployer] | `0xa5827ef6aa78a54d89ad51654288d42ef48998dcef777f5d23c3b1b9f2ce5d21` | ✅ status 1, `paused` = false |
| 2 | `mint(1, 0x0, 0,00168)` [alice] value 0,00168 tBNB | `0xd896813b18c4cd0214cbe745e12400fc8a6755b391b8a33612376c93c172e662` | ✅ status 1, `totalMinted` = 1, saldo token alice = 168.000.000, `deposits` = 0,00168, `pendingBnb` = 0,001428 (= 85%: 80% pool + 5% referral jatuh ke pool tanpa referrer) |
| 3 | `freeMint()` [bob] | `0x620fcb9b1b0e7f93a1024b76b10b1fc12f5f555b21f60e3fdacbd5a201b9fcda` | ✅ status 1, `freeClaimed` = 1, saldo token bob = 168.000.000, `participantCount` = 2 |
| 4 | `exit(1)` [alice] | `0x7e84f225f6738a6eca134e5db8175f75eb80522300b09395156098c133e0c9bc` | ✅ status 1, `totalMinted` = 0, saldo token alice = 0 (dibakar), `forfeitOf` = 0,000336 (20%), refund 0,001344 (80%, event `Exited` terkonfirmasi; saldo tBNB alice 0,2874494452 → 0,2887796175 setelah dikurangi gas exit) |
| 5 | Registry | — | ✅ `handleOf(deployer)` = `"alice"`; alice + bob terdaftar sebagai peserta |

State awal sebelum smoke test (dicek live): `totalMinted` = 0,
`paused` = true, `opened()` = false, `pair` =
`0x238db3a329a29586d72d4857A08d683cb38f63e0`, `name()` = `"BAISHOU"`,
`totalSupply` = 0, `costOf(1)` = 0,00168 tBNB — semua sesuai desain.

**Yang BELUM diuji di testnet (di luar smoke test ini):** `openEarly()` /
pembukaan pool (butuh 168.000 share — tidak realistis di testnet),
`claimRefund()` (butuh launch gagal — butuh time travel 7 hari),
`claimDividend()` (butuh pajak trading), `claimTreasury()` /
`claimReferral()` (butuh pool buka), `renounce()` (gate review — JANGAN
di testnet), dan Echidna/invariant (belum dijalankan).

## 8. Rotasi key test user (19 Nov 2026 ~14:21 WIB)

Insiden: saat persiapan smoke test, satu perintah `python3 -c` membaca
`testnet-test-users.json` dan mencetak isinya ke output tool — termasuk
private key test bob/carol (testnet-only). Perintah user: "rotasi aja,
jangan sampe diulangin lg". Rotasi selesai, **NOL private key tercetak**
selama tugas ini (key baru digenerate via `cast wallet new --json` yang
ditangkap lewat subprocess Python, ditulis langsung ke file).

| Handle | Alamat BARU | Alamat lama (mati, key dibuang) |
|---|---|---|
| alice | `0x1A3f6Ecf4717A323d5de4919763e6a5aF36eA32E` | deployer (dulu "alice") |
| bob | `0x0cfEAcCbaa674C21aBDe3301837b2a9B2582AFBE` | `0x8f44a96c0C3936c5768fF1a1cDa8574aE841651E` |
| carol | `0x360CD72e1Ebd0e51418333Ece5586E8b49CE46C8` | `0xC93e5BC6020dBC63cB6B3ddF7E42a4b02C9244cf` |

- File `testnet-test-users.json` baru (mode 600, gitignored, skema sama).
  Key deployer testnet TIDAK diganti (tidak pernah bocor).
- Funding 0,01 tBNB tiap user (dari deployer testnet, status 1):
  alice `0xd60a0a160f2c90ce8c34db8eb6cb09d6d875319f6ad83d8ca61f165d24943d3f`,
  bob `0x1dbc517e56614ac2d75f20947a4d5628c5d7729421c0e3e67bb7680e561c2837`,
  carol `0xa727ffe0edf5f0f2d669af1703776e642833be9fd9c3ac22a1bf37af2faa306a`.
- Registrasi MockRegistry (6 tx, status 1): setHandle+setOwner ×3 —
  `0x3b75941d…`, `0x63474e49…`, `0xd8446bc4…`, `0x0a2d5cdf…`,
  `0x60456540…`, `0x4f5f2223…` (hash lengkap di laporan agen).
  `handleOf` ketiga alamat baru = `"alice"` / `"bob"` / `"carol"`.
- Bukti akhir: **freeMint carol baru ✅** tx
  `0xf6ef988e000a8068029879fa1f3f2e7ee019be5b1ea64a712cb07f182b7a25f2`,
  saldo token carol = 168.000.000, `freeClaimed` = 2. **freeMint bob baru
  revert `AlreadyGranted`** — perilaku kontrak yang BENAR (claimedFree
  dikunci per Agent ID `keccak("bob")`; bob lama sudah klaim di smoke
  test; tidak ada tx ter-broadcast, tidak ada gas terbuang). Pengganti
  bukti bob: **mint(1) berbayar ✅** tx
  `0xc61037ca04e1bd98d6d204476c9747137c50ed66dcf91e8f3eb657e7b4b38eb2`,
  saldo token bob baru = 168.000.000, `totalMinted` = 1.
- Verifikasi parent (live, chain 97): handleOf ketiga alamat baru benar;
  saldo tBNB alice 0,01 / bob 0,0082934911 (habis mint berbayar +
  gas) / carol 0,009983872 (habis gas freeMint); token bob & carol baru
  masing-masing 168.000.000; `freeClaimed` = 2, `totalMinted` = 1;
  kedua file key mode 600, `git status` bersih.
- Efek samping: deployer kehilangan kepemilikan handle "alice"
  (`ownerOf(id("alice"))` pindah ke alice baru; `handleOf(deployer)`
  masih mengembalikan `"alice"` tapi deployer tidak bisa lagi mint
  sebagai alice — owner mismatch). Deployer tetap admin/treasury
  (tidak butuh Agent ID). Tes mint selanjutnya pakai alice/bob/carol baru.
- Key lama dibuang TANPA backup (sengaja — key bocor). Sisa saldo testnet
  di alamat lama (token + tBNB debu) tidak bisa lagi dipakai. Tidak ada
  nilai riil di sana.
- Aturan permanen (AGENTS.md): JANGAN PERNAH cetak isi file key ke
  output tool/chat/log/file — script yang memegang key hanya boleh
  mencetak alamat; kalau key sudah tercetak, rotasi segera + seed ulang.
