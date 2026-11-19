# BAISHOU — BSC Mainnet (chain 56) — STATUS: ✅ MAINNET LIVE — MINT TETAP TUTUP (paused=true)

**Perintah user:** 19 Nov 2026 14:10 WIB — "deploy aja semua kontraknya tapi
jangan open mint dulu". **Mint TETAP TUTUP** (paused=true adalah state awal;
script TIDAK memanggil setPaused(false) / openEarly / mint / seed).
**Deploy selesai 19 Nov 2026 ~14:36 WIB — lihat §7. Lampu hijau parent
diberikan; broadcast sukses.**

## 0. Blocker pendanaan — SELESAI (jalur b, pilihan user 14:23 WIB)

**Pendanaan deployer sempat DIBLOKIR risk engine Binance (~14:17 WIB):**
`baw wallet send` → `{"code": 351703, ... "recipient address is not in your
address book..."}` — kirim 0,006103075125 BNB ke deployer gagal, tidak ada
dana bergerak. **Solusi yang dipakai: jalur (b)** — user: "gas aja lu
pindahin": pindah 0,0025 BNB dari `0xad5d…` (deployer testnet — saldo
mainnetnya 0,0025 BNB, syarat faucet) ke deployer mainnet `0x3730…` —
tx `0xe41a687b883e3cc9cb310f052e2476da97b4c83bf7afbe7ee96b308859cb33fa`
status 1, block 134.462.747. Deployer mainnet kini 0,0024979 BNB, nonce 0,
prediksi alamat tetap berlaku; broadcast gas rendah 0,1 gwei.

## 1. Alamat prediksi (dry-run lawan state mainnet live, nonce deployer 0)

Dua dry-run independen memberi alamat prediksi yang SAMA:

| Kontrak | Alamat prediksi |
|---|---|
| AgentToken | `0x42c40Bf7E152315d947484d37CC6d0E74d29cD88` |
| Pair BAISHOU/WBNB | `0x339b0e7cC4B6dBCe18E63632Ab379F76F9aE5F73` |
| AgentMint | `0x6cA8489C75641bdf7a0A2Af1Eee4375f52a51F00` |
| Deployer (key mainnet baru) | `0x3730f81E6f311ab40222da1393e07Af6F68AffB5` |

⚠️ Ini PREDIKSI — berlaku selama nonce deployer tetap 0. Bukan alamat live.

## 2. Constructor args (lengkap)

**AgentToken** — `new AgentToken("BAISHOU", "BAISHOU", wbnb, factory,
poolManager, infinityVault)`:
- name = `"BAISHOU"`, symbol = `"BAISHOU"`
- wbnb = `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`
- factory = `0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73`
- poolManager = `0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b`
- infinityVault = `0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F`

**AgentMint** — `new AgentMint(Config{...})`:
- token = alamat AgentToken hasil deploy (di atas)
- registrar = `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
- treasury = `0x319581821414b324Dd5Db9795e42E7ee3A287900` (dompet utama user)
- feeTreasury = `0x319581821414b324Dd5Db9795e42E7ee3A287900`
- admin = `0x319581821414b324Dd5Db9795e42E7ee3A287900`
- wbnb = `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`
- swapFeeBps = 30
- unblockable = [] (kosong)
- priceDiv = 1

Konstanta kontrak (dari source, sudah diuji): TOTAL_SHARES 1.680.000,
MAX_SUPPLY 510.854.400.000.000 ether, OPEN_AT 168.000, PROD_BASE_PRICE
0,00168 ether, PROD_OPEN_BNB 225,792 ether, TREASURY_BPS 1500,
REFERRAL_BPS 500, MINT_PRICE_BPS 10000, BASE_PER_ID 168, MAX_PER_TX 168,
FREE_SHARES 16.800, EPOCH_SHARES 16.800.

## 3. Bukti tiap alamat mainnet terverifikasi (chain 56, block 134.461.092)

| Alamat | Bukti |
|---|---|
| Registrar `0x60B9…022F` | `eth_getCode` → bytecode `0x6080…`; fungsional: `balanceOf(0x3195…8900)` = 1, `handleOf(0x3195…8900)` = `"nosa"` — registry Agent ID resmi dengan ID user terdaftar |
| WBNB `0xbb4C…095c` | `eth_getCode` → code; `symbol()` = `"WBNB"` |
| Factory `0xcA14…0c73` | `eth_getCode` → code; `allPairsLength()` = 3.729.190; alamat dari dokumen resmi PancakeSwap (developer.pancakeswap.finance/contracts/v2/addresses) + Bitquery. CATATAN: alamat benar berakhir `…0c73` — penulisan `…0c6` (39 digit) adalah salah ketik dan ditolak cast |
| PoolManager `0xa0Ff…058b` | `eth_getCode` → code; fungsional: `protocolFeeController()` = `0x74Aa9b14049Eccf0eE2183818658B84df427Cb5C`; source terverifikasi Etherscan V2: `src/pool-cl/CLPoolManager.sol`, "Copyright (C) 2024 PancakeSwap"; dua sumber independen (Bitquery Infinity API + riset defiformal) menamai alamat ini CL pool manager BSC |
| InfinityVault `0x0e32…361F` | `eth_getCode` → code; source terverifikasi Etherscan V2: `contract InfinityVault is` (BscScan: "InfinityVault", Exact Match) |

Script `DeployMainnet.s.sol` juga punya pertahanan berlapis: `require`
code-length > 0 untuk kelima alamat di atas SEBELUM broadcast — kalau satu
saja kosong, deploy revert tanpa broadcast setengah jalan. Sentinel
`0x…0001` TIDAK dipakai di mainnet. MockRegistry TIDAK di-deploy.

## 4. Script + test + dry-run

- Script baru: `script/DeployMainnet.s.sol` (bukan `Deploy.s.sol` testnet —
  script lama hardcode role = deployer + deploy MockRegistry bila registrar
  kosong; menjalankannya di mainnet akan mengunci treasury ke dompet
  throwaway. DILARANG dipakai di mainnet).
- `forge build` OK. **`forge test`: 139 passed, 0 failed, 0 skipped**
  (7 suite, 19 Nov 2026).
- Dry-run 1 (multiplier 1,2x): total gas 10.730.681, alamat prediksi =
  §1. Dry-run 2 (tanpa multiplier): total gas 11.624.905, alamat prediksi
  SAMA. Estimasi gas forge bervariasi ±10% antar-run; angka tertinggi
  dipakai untuk pendanaan. Referensi: testnet aktual 7.988.496 gas
  (termasuk MockRegistry 317.527).
- Gas price saat dry-run: `eth_gasPrice` = 0,05 gwei.

## 5. Pendanaan deployer (matematika + status)

- Deployer: `0x3730f81E6f311ab40222da1393e07Af6F68AffB5` — key mainnet BARU
  (`cast wallet new --json`), file `mainnet-deployer-key.json` mode 600,
  gitignored, TIDAK pernah dicetak isinya. Deployer TIDAK pegang peran
  apa pun (treasury/feeTreasury/admin = dompet utama user).
- Hitungan pendanaan: gas tertinggi 11.624.905 × 0,5 gwei (10× harga jalan
  0,05 gwei — headroom supaya broadcast tidak underpriced) =
  0,0058124525 BNB × 1,05 buffer = **0,006103075125 BNB**.
- Saldo dompet utama saat hitung: 0,010306309470965425 BNB (dicek live via
  cast). Sisa dompet utama setelah kirim: ≈ 0,004203234345965425 BNB
  (di luar gas kirim baw sendiri, ~21.000 gas).
- **Status: TERKIRIM via jalur (b) — lihat §0.** Deployer mainnet didanai
  0,0024979 BNB (dari 0xad5d…, tx `0xe41a68…33fa`). Biaya broadcast
  sebenarnya 0,0004469663 BNB (gas 8.910.142 @ ~0,05 gwei efektif —
  jauh di bawah estimasi 0,00116 BNB @ 0,1 gwei); **sisa deployer
  0,0020509337 BNB DIBIARKAN (user 14:25 WIB: "jangan disapu balik
  langsung, biarin aja dulu") — JANGAN sapu balik sampai user bilang.**
- Rencana broadcast (SETELAH lampu hijau parent): `forge script
  script/DeployMainnet.s.sol:DeployBaishouMainnet --rpc-url
  https://bsc-dataseed.binance.org/ --broadcast --with-gas-price
  500000000` (0,5 gwei max fee), lalu `token.initialize(mint)` sudah
  termasuk di script. Verifikasi source BscScan mainnet + Sourcify, lalu
  baca state: paused HARUS true, totalMinted 0, name BAISHOU, costOf(1)
  0,00168 BNB, treasury/admin = dompet utama.

## 6. Yang masih kurang sebelum mint dibuka (setelah deploy)

1. Verifikasi source BscScan mainnet + Sourcify.
2. Baca state live (paused/totalMinted/treasury/admin).
3. Echidna/invariant formal — belum dijalankan.
4. Audit forensik komunitas Square + review independen — gate
   `reviewPassed` sudah ada; `renounce()` terkunci sampai review lolos.
5. Buka mint — butuh kata user tersendiri (deploy ini TIDAK membuka mint).

## 7. ✅ MAINNET LIVE — deploy selesai 19 Nov 2026 ~14:36 WIB

**Broadcast:** `forge script script/DeployMainnet.s.sol:DeployBaishouMainnet
--rpc-url https://bsc-dataseed.binance.org/ --broadcast --with-gas-price
100000000 --priority-gas-price 50000000 --start-fresh`, di dalam `script`
(terekam — lihat §8). Dua percobaan pertama GAGAL sebelum ada tx yang
terkirim (nonce tetap 0, prediksi alamat tidak berubah):
1. tip 0,01 gwei ditolak jaringan ("gas tip cap 10000000, minimum needed
   50000000") — diperbaiki ke tip 0,05 gwei;
2. forge menolak karena run sebelumnya belum selesai ("unfinished
   operations") — diperbaiki dengan `--start-fresh` (run gagal diarsip).
Percobaan ketiga: **ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.**

Catatan key file: `mainnet-deployer-key.json` ternyata format envelope baw
(`{success, data: [{address, public_key, private_key}]}`), BUKAN
`{private_key}` seperti file testnet — dry-run pertama gagal
`KeyError: 'private_key'`. Jalur benar:
`json.load(...)['data'][0]['private_key']`. Alamat dari key diverifikasi
cocok dengan deployer `0x3730…AffB5` sebelum broadcast. Key TIDAK pernah
dicetak (hanya alamat yang ditampilkan).

| Kontrak | Alamat (AKTUAL = prediksi §1 persis) | Tx | Gas |
|---|---|---|---|
| AgentToken | `0x42c40Bf7E152315d947484d37CC6d0E74d29cD88` | `0x6b788a4b63e3c53b8c817c440ee66c5cb9a487abfbb4a9817af11c81744d864b` | 4.821.292 |
| AgentMint | `0x6cA8489C75641bdf7a0A2Af1Eee4375f52a51F00` | `0x4d5b4c0fb1e494999579c948cb0d3906fb3002a7dc2c08984bf00eafbdba7171` | 4.043.241 |
| Pair BAISHOU/WBNB | `0x339b0e7cC4B6dBCe18E63632Ab379F76F9aE5F73` | dibuat saat deploy AgentToken (likuiditas 0 — pool buka di share 168.000) | — |
| `token.initialize(mint)` | — | `0x7c2a64caeaadc04231d1e573d9ceeb22109c8fe8d477d0ab2dfe93ed5543882d` | 45.609 |

Semua 3 tx status 1, block 134.462.865. Total gas deploy: **8.910.142**
(0,0004469663 BNB @ ~0,05 gwei efektif). BscScan mainnet:
https://bscscan.com/address/0x42c40Bf7E152315d947484d37CC6d0E74d29cD88 dan
https://bscscan.com/address/0x6cA8489C75641bdf7a0A2Af1Eee4375f52a51F00

**Verifikasi source — KEDUANYA exact_match / terverifikasi di kedua tempat:**
- **Sourcify: ✅ exact_match KEDUANYA** (creation + runtime) —
  AgentToken job `8d58ffe4-a174-4625-b022-8e246a5eb772` (verifiedAt
  2026-11-19T07:34:00Z), AgentMint job `7b52e748-c07f-496d-a3e4-d06296b55f41`
  (verifiedAt 2026-11-19T07:35:00Z). Percobaan pertama forge ke Sourcify
  sempat timeout di status query — retry berhasil.
- **BscScan mainnet: ✅ terverifikasi KEDUANYA** (dibaca live via
  `getsourcecode`): AgentToken ContractName "AgentToken", compiler
  v0.8.28+commit.7893614a, optimizer runs 200, EVM paris, source 35.446
  karakter; AgentMint ContractName "AgentMint", compiler sama, source
  93.942 karakter, checkverifystatus "Pass - Verified" (GUID
  `y94afrsdr4pvu4ube2pb6gwyjjvw3dzbdqwzyfvpnc1imdtyyu`). AgentToken
  tercatat "already verified" saat submit — Sourcify exact_match
  diimpor otomatis BscScan; AgentMint disubmit manual via skrip
  `/tmp/bscscan_verify.py` (POST standard-JSON pakai surrogate konektor
  etherscan-v2 — forge tidak bisa pakai surrogate). Berbeda dengan
  testnet (chain 97 diblokir paket gratis), chain 56 LOLOS.

**State live (dibaca via cast, chain 56, block 134.463.810 — SEMUA SESUAI):**
- code ada: AgentToken 13.667 B, AgentMint 36.389 B
- `name()` = `"BAISHOU"`, `symbol()` = `"BAISHOU"`
- `pair()` = `0x339b…5F73` (sesuai prediksi), `minter()` = AgentMint
- `paused()` = **true** ✅ (mint TETAP TUTUP)
- `totalMinted()` = **0** ✅
- `costOf(1)` = 1.680.000.000.000.000 wei = **0,00168 BNB** ✅
- `treasury()` = `feeTreasury()` = `admin()` = `0x3195…8900` ✅
  (dompet utama user)
- `opened()` = **false** ✅
- Deployer akhir: saldo **0,0020509337 BNB**, nonce 3 — **DIBIARKAN,
  TIDAK disapu balik** (perintah user 14:25 WIB).

## 8. Rekaman broadcast (video X)

- Typescript: `broadcast-mainnet.typescript` (5.900 B — 3 percobaan:
  gagal tip, gagal resume, sukses). Export key dilakukan di shell LUAR,
  tidak terekam.
- **Audit rahasia SEBELUM publish (aturan AGENTS.md, user 14:28 WIB):
  BERSIH** — grep: 0 string 0x+64hex, 0 kata sensitif
  (private_key/mnemonic/apikey/dll); cek nilai key deployer vs isi file:
  False/False (nilai key TIDAK pernah dicetak, hanya True/False).
  Yang tampil hanya alamat publik + tx + log forge. Aman dipublish.
- MP4: `broadcast-mainnet.mp4` (9,8 MB, 60 dtk, 1280×720, h264 30fps) —
  render ffmpeg drawtext dari typescript bersih (font DejaVu Sans Mono,
  hijau terminal, scroll). Frame dicek visual (t=30: log deploy +
  alamat; t=57: "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL."). Dua cacat
  kosmetik: baris "Archived ..." terpotong di tepi kanan; satu glyph
  spinner Braille jadi kotak — tidak mengganggu isi.
- Draf postingan X #3 (mainnet live, 209 karakter) sudah dibuat parent —
  JANGAN dipost sampai deploy terverifikasi live (sudah terverifikasi
  sekarang — §7).
