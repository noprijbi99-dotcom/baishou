# BAISHOU — BSC Mainnet (chain 56) — STATUS: ⏸️ CHECKPOINT — MENUNGGU PERSETUJUAN PARENT

**Perintah user:** 19 Nov 2026 14:10 WIB — "deploy aja semua kontraknya tapi
jangan open mint dulu". **Mint TETAP TUTUP** (paused=true adalah state awal;
script TIDAK memanggil setPaused(false) / openEarly / mint / seed).
**Perintah checkpoint:** persiapan selesai → lapor parent → TUNGGU lampu
hijau. **BELUM ADA BROADCAST.**

## 0. Blocker saat ini (satu-satunya yang belum selesai)

**Pendanaan deployer DIBLOKIR risk engine Binance (19 Nov ~14:25 WIB):**
`baw wallet send` → `{"success": false, "error": {"code": 351703, "name":
"SERVICE_ERROR", "message": "This transfer was blocked because the recipient
address is not in your address book. Add this address in your binance wallet
app, then retry the transfer."}}`

- Jumlah yang dicoba: **0,006103075125 BNB** → deployer
  `0x3730f81E6f311ab40222da1393e07Af6F68AffB5` (tidak ada dana yang bergerak;
  saldo deployer dicek live = **0**).
- Jalur agen sudah habis: baw TIDAK punya perintah address-book
  (`baw wallet --help`: status/address/balance/send/cancel/speed-up/
  tx-history/settings/left-quota/tx-lock/chains/gas-price/resolve-domain/
  agent-id — tidak ada tambah-alamat); kirim via cast dari dompet utama
  DILARANG (tidak boleh ekstrak private key dompet utama).
- **Solusi yang disiapkan (butuh tangan user, 1 tap di aplikasi Binance):**
  user tambahkan alamat deployer `0x3730f81E6f311ab40222da1393e07Af6F68AffB5`
  ke address book di aplikasi Binance Wallet, lalu agen retry kirim
  **0,006103075125 BNB** yang sama. Setelah saldo deployer terverifikasi,
  parent beri lampu hijau → broadcast.

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
- **Status: BELUM TERKIRIM — diblokir 351703 (§0).** Biaya broadcast
  sebenarnya kemungkinan jauh lebih kecil (di 0,05–0,1 gwei: ~0,0006–
  0,0012 BNB); sisa dana di deployer bisa disapu balik ke dompet utama
  setelah deploy, atau disimpan untuk operasi berikut.
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
