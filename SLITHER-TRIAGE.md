# Slither Triage — BAISHOU step 2 (19 Nov 2026)

Perintah: `~/.venvs/slither/bin/slither . --exclude-dependencies`
(Slither 0.11.6, solc 0.8.28, Foundry 1.9.0).
Hasil lengkap: `slither-2026-11-19.json` (74 temuan).
Baseline fork awal: `slither-baseline-2026-11-19.json` (78 temuan:
2 High, 17 Medium, 25 Low, 34 Informational).

## Ringkasan

| Severity | Baseline | Sekarang | Status |
|---|---|---|---|
| High | 2 | 4 | 0 nyata — semua dijustifikasi di bawah (pola yang sama seperti baseline, kini di 2 tempat karena ada jalur bayar baru `_payOrOwe`) |
| Medium | 17 | 7 | 0 nyata — 2 diperbaiki di kode (lihat § "Diperbaiki"), 5 false positive / by-design |
| Low | 25 | 30 | 0 nyata — semua by-design / vendor / false positive |
| Informational | 34 | 33 | 0 nyata — mayoritas dari `src/vendor/` (OpenZeppelin) |

**Baseline 2 High TIDAK hilang — keduanya masih ada dalam bentuk yang sama
dan dijustifikasi tertulis di bawah, sesuai instruksi tugas ("hilang atau
terjustifikasi tertulis").** Keduanya adalah pola inheren desain PULL-payment
+ `nonReentrant`, bukan bug: `_pay arbitrary-send-eth` dan
`_mintWithBnb reentrancy-eth`. Dua High "baru" adalah kemunculan pola yang
sama di kode baru (`_payOrOwe`, `_mintShares`).

## Diperbaiki di kode (sebelum triase ini)

- `divide-before-multiply` di `costOf` / `_mintShares` (lama): dihitung ulang
  jadi `priceUnits(n) * (BASE_PRICE / 100)` — eksak karena constructor
  memaksa `BASE_PRICE % 100 == 0` (dan `(PROD_BASE_PRICE / priceDiv) % 100 == 0`).
- `uninitialized-local` (`userT`, `Pool p` di `_mintShares`): inisialisasi
  eksplisit (`= 0`, `Pool(0,0,0,0,0,0,0)`).
- `redundant-statements` (`id;`, `n;`): parameter dihapus/di-nameless-kan.
- `events-access` (`AgentToken.initialize`): tambah event `MinterInitialized`
  + emit.
- Hardening: `_open()` kini menyetel `openedTime` di baris pertama (CEI)
  sebelum panggilan eksternal apa pun.

## HIGH — dijustifikasi (bukan bug)

### 1. `arbitrary-send-eth` — `AgentMint._pay` dan `AgentMint._payOrOwe`
Slither menganggap `to` sebagai alamat arbitrer. Faktanya `to` HANYA bisa
berupa: (a) `msg.sender` — pemanggil sendiri (refund overpay, `exit`,
`claimRefund`, `claimReferral`, `claimOwed`); atau (b) `treasury` —
`immutable` yang ditetapkan saat deploy. Tidak ada satu pun jalur di mana
pemanggil bisa memilih alamat penerima orang lain. Jumlah juga terbatas oleh
akuntansi (`deposits`, `forfeitOf`, `referralAccrued`, `escrowTreasury` —
semuanya dikurangi SEBELUM `call`, checks-effects-interactions), dan semua
fungsi pemanggil memakai `nonReentrant`. Mengganti ke pola lain (mis. bayar
WBNB, bukan BNB) akan mengubah janji produk (refund BNB) tanpa mengurangi
risiko nyata. **Diterima.**

### 2. `reentrancy-eth` — `AgentMint._mintWithBnb` dan `AgentMint._mintShares`
Semua entry point publik yang menyentuh ETH memakai `nonReentrant`
(`ReentrancyGuard` OZ); `_mintShares` adalah `private` dan hanya dipanggil
dari `_mintWithBnb` yang sudah ter-guard. Panggilan eksternal di dalam alur
hanya ke kontrak `immutable` tepercaya (WBNB, token sendiri, pair) atau ke
`call` refund di akhir setelah semua state diperbarui. Tidak ada jalur
re-entry yang bisa mengubah akuntansi: `mintedCount`/`totalMinted`/
`deposits`/`pendingBnb` di-update sebelum `_pay` terakhir, dan guard
memblokir pemanggilan ulang `mint`/`exit`/`claim*` di tengah eksekusi.
**Diterima (mitigasi: guard + CEI + alamat immutable).**

## MEDIUM — dijustifikasi (bukan bug)

### 3. `divide-before-multiply` ×2 (`costOf`, `_mintShares`)
Pola yang tersisa adalah `unit = BASE_PRICE / 100` lalu `priceUnits * unit`.
Pembagian ini EKSAK: constructor `revert BadConfig()` kecuali
`PROD_BASE_PRICE % priceDiv == 0` dan `(PROD_BASE_PRICE / priceDiv) % 100 == 0`
(0,00168 ether / 1 = 1,68e15, habis dibagi 100). Tidak ada kehilangan
presisi; diverifikasi test `test_FlatPricePrePool` (`costOf(1)` persis
0,00168 ether, `costOf(168)` persis 168×). **False positive.**

### 4. `incorrect-equality` ×2 (`swapTax`: `lastTaxSwapBlock == block.number`; `_swapTax`: `amount == 0`)
Keduanya kesetaraan yang disengaja, bukan perbandingan saldo yang bisa
dimanipulasi: (a) guard sekali-per-blok untuk swap pajak; (b) revert kalau
tidak ada token pajak untuk di-swap. **By-design.**

### 5. `unused-return` ×3 (`reserves`, `_swapOn`: nilai ketiga `getReserves`;
`_settle`: return `pair.mint`)
Timestamp reserve memang tidak dipakai (bukan data yang dibutuhkan);
jumlah LP yang tercetak ke DEAD memang tidak dipakai (LP dibakar, tidak
perlu dicatat). **By-design.**

## LOW — diringkas (semua by-design / false positive / vendor)

- `calls-loop` ×14: loop `_mintShares` dibatasi `MAX_PER_TX = 168`
  (dipaksa `_check`); panggilan eksternal di `_open`/`_payOrOwe` berada di
  dalam loop hanya menurut analisis statis Slither (satu panggilan per
  eksekusi, bukan iterasi user-controlled). Target kontrak `immutable`.
- `timestamp` ×8: deadline 7 hari / jendela refund 90 hari / mint tutup
  7 hari memang didefinisikan atas `block.timestamp` (desain §3/§10);
  deviasi validator beberapa detik tidak memengaruhi batas berhari-hari.
- `reentrancy-benign` ×3, `reentrancy-events` ×3: lihat justifikasi High #2;
  event di-emit setelah call di `renounce`/`claimDividend`/`_swapTax` —
  state sudah final sebelum call (`renounced`/`withdrawnDividends`/
  `lastTaxSwapBlock` di-set dulu).
- `missing-zero-check` ×2 (`poolManager_`, `infinityVault_` di constructor
  `AgentToken`): SENGAJA tidak dicek — `address(0)` berarti "tidak ada
  kontrak Infinity" dan tidak berbahaya: `rejects()` hanya membandingkan
  kesetaraan, dan transfer ke `address(0)` adalah burn yang ditangani
  sebelum pemeriksaan `rejects()`.
- `return-bomb` ×1 (`_probe`): staticcall dibatasi `PROBE_GAS = 20_000`
  dan hasil divalidasi panjang 32 byte + range alamat. **Mitigasi sudah ada.**

## INFORMATIONAL — diringkas

- `assembly` ×16, `dead-code` ×2, `solc-version` ×4, `pragma` ×1:
  semuanya dari `src/vendor/` (OpenZeppelin, tidak disentuh) — assembly
  OZ yang diaudit, dan pragma `^0.8.24` dipakai bersama solc 0.8.28
  (pin di `foundry.toml`).
- `low-level-calls` ×7: `call`/`staticcall` yang disengaja (pembayaran BNB
  PULL, probe pair) — lihat justifikasi High #1.
- `naming-convention` ×2: `BASE_PRICE`/`OPEN_BNB` (immutable, gaya
  konstanta AIC yang dipertahankan).
- `cyclomatic-complexity` ×1 (`_mintShares`, 13): satu jalur mint yang
  memang bercabang pre/post-pool + escrow; dipecah lebih jauh akan
  mengaburkan invarian escrow — diterima, dicover 139 test.

## Yang belum dilakukan (untuk review independen)

- Slither tidak menggantikan audit: tetap dibutuhkan review independen
  berbayar dari treasury SETELAH pool buka (sesuai §10 #13) sebelum
  `renounce()` — gate `reviewPassed` sudah ada di kontrak.
- Echidna / invariant test formal belum dijalankan (di luar scope step 2).
