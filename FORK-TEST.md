# BAISHOU — FORK TEST JALUR UANG + INVARIANT (19 Nov 2026)

Laporan jujur hasil gerbang pre-mint yang sebelumnya belum teruji. Semua test
baru ditulis di file TERPISAH (`test/Fork*.t.sol`, `test/Invariant.t.sol`);
tidak ada test lama dan tidak ada kode kontrak yang diubah. Semua berjalan
di EVM lokal Foundry dengan mock yang sama seperti suite lama (MockRegistry,
MockWBNB, MockPair) — **tidak ada transaksi mainnet/testnet yang dikirim,
tidak ada wallet beneran yang dipakai.**

## Hasil akhir

```
forge test (suite PENUH, lama + baru)
11 suite: 192 passed, 0 failed, 0 skipped
Suite lama (7 file): 139 test — SEMUA tetap hijau.
Invariant: 256 runs, 128.000 calls, 0 reverts.
```

## (a) Pool-open — loop NYATA 168.000 share — `test/ForkOpen.t.sol` ✅

Bedanya dari `PoolOpen.t.sol` lama: di sana pool dibuka pakai
`_fastForwardToOpen()` (vm.store memalsukan 167.999 share). Di sini
**1.000 agen beneran** didaftarkan ke MockRegistry dan masing-masing mint
168 share (MAX_PER_TX = cap per ID) pada harga produksi (priceDiv = 1),
semua dengan satu referrer yang sama, sampai OPEN_AT tercapai beneran.

Angka yang terverifikasi dari konstanta kontrak (di-cross-check ke literal):

| Item | Hasil |
|---|---|
| totalMinted | 168.000 = OPEN_AT, `opened()` = true, trading aktif |
| Total deposit pre-pool (totalPaid) | 282,24 BNB |
| Treasury 15% | **42,336 BNB** — diterima treasury persis |
| Referral 5% | **14,112 BNB** — terakru penuh, diklaim via `claimReferral()` |
| Pool (reserve pair) | 225,792 BNB + 22.579.200.000.000 token (= OPEN_BNB / OPEN_TOKENS) |
| participantCount | 1.000 peserta unik |

Nuansa mekanisme yang penting (sesuai kode, bukan asumsi): potongan
treasury pre-pool **dibayar otomatis sekali di `_open()`** (via
`_payOrOwe`), BUKAN lewat `claimTreasury()` — terbukti dari
`claimTreasury()` tepat sesudah pool buka revert `NothingOwed` dan
`escrowTreasury() == 0`. `claimTreasury()` adalah jalur akrual PASCA-pool;
itu juga diverifikasi di test yang sama: 1 mint pasca-pool terakru
15%-nya dan berhasil diklaim treasury sampai nol.

Catatan gas (jujur): loop 168.000 share-iterasi nyata mengonsumsi
±1,62 miliar gas eksekusi EVM — di atas cap metering default forge per
test (2^30). Karena itu loop dibungkus `vm.pauseGasMetering()` /
`vm.resumeGasMetering()`: yang dimatikan HANYA akuntansi gas test runner,
eksekusinya tetap penuh (dibuktikan terpisah: dengan
`FOUNDRY_GAS_LIMIT=20000000000` tanpa pause, test yang sama lulus dengan
gas terukur 1.622.820.003). Semua assertion berjalan dengan metering
normal. Runtime test ini ±17 detik.

## (b) claimRefund 100% saat sale gagal — `test/ForkRefund.t.sol` ✅

Skenario gabungan: alice mint 100, bob mint 50 (referrer alice), carol
mint 20; carol exit PENUH, alice exit PARSIAL (40); lalu deadline lewat.

- Exit carol: kembali 0,02688 BNB (80%), forfeit 0,00672 BNB tercatat.
- Exit alice 40: kembali 0,05376 BNB (80%), forfeit 0,01344 BNB.
- **Bukti solvabilitas di tengah jalan:** saldo WBNB kontrak ==
  total kewajiban refund (Σ deposits + forfeitOf) == **0,20496 BNB**, persis.
- Sesudah `saleFailed()`: refund alice = **0,11424** (deposits 0,1008 +
  forfeit 0,01344), bob = **0,084** (deposit penuh), carol = **0,00672**
  (forfeit saja) — semua persis sampai wei.
- Akhir: kewajiban 0, saldo WBNB kontrak 0, treasury tetap 0.
- `claimReferral()` sesudah gagal tetap revert `NotOpen` (pool tidak
  pernah buka — komisi referral tidak bocor keluar pada launch gagal).

## (c) exit() 80% sebelum pool buka — `test/ForkRefund.t.sol` ✅

Selain angka exit di skenario (b), ada test khusus: minter 168 share
DENGAN referrer exit PENUH → kembali 0,225792 dari 0,28224 BNB (80%
persis), dan potongan yang sudah terakru ikut mundur bersih:
`escrowTreasury`, `referralAccrued`, `pendingBnb` semua kembali 0;
sisa escrow kontrak == forfeit 0,056448 BNB (kewajiban refund terakhir).

## (d) claimDividend dari swap tax — `test/ForkDividend.t.sol` ✅

Rantai PENUH seperti produksi (bukan setoran `depositDividends` langsung
seperti sebagian test lama): pool dibuka kecil via `openEarly()` (alice
168 share; treasury menerima 0,042336 BNB saat buka; pool 0,239904 BNB +
22.579.200.000 token) → bob **beli lewat `pair.swap()`** (bayar 0,2125
WBNB, terima 98% = 19,6 miliar token; pajak beli 2% = 400 juta token
masuk minter) → `swapTax()` 12× (satu per blok, semua berhasil) menjual
token pajak jadi BNB → BNB masuk dividend pool (`totalDividends > 0`,
`feeTreasury` tetap 0) → alice `claimDividend()`: akrualnya
≥ ambang minimum 0,001 BNB dan klaim membayar **persis**
`withdrawableDividendOf` sesaat sebelum klaim; klaim kedua = 0.

Kenapa pool kecil: pada skala produksi (168.000 share) dividen per holder
memang debu di bawah ambang 0,001 BNB untuk volume swap realistis —
desain yang sudah dicatat sejak step 2, bukan temuan baru. Jalur kode
yang sama diverifikasi di sini pada fraksi supply yang membuat ambang
terjangkau oleh pajak swap beneran.

## Invariant — `test/Invariant.t.sol` ✅

Handler 8 agen melakukan aksi acak: mint (dengan referrer bergilir),
exit, freeMint, claimRefund, dan warp waktu (melintasi deadline gagal).
**256 runs × 500 calls = 128.000 calls, 0 reverts, tiga invarian tahan:**

1. **Solvabilitas escrow pra-pool:** saldo WBNB kontrak ≥ Σ (deposits +
   forfeitOf) semua agen — termasuk sesudah deadline dan sesudah klaim
   refund acak menguras escrow secara sah.
2. `totalMinted` ≤ TOTAL_SHARES (1.680.000) — selalu.
3. `totalSupply` token ≤ MAX_SUPPLY (510.854.400.000.000) — selalu.

Non-trivialitas handler diverifikasi terpisah (test sekali jalan,
dihapus sesudahnya): drive manual handler menghasilkan 1.246 share
ke-mint dan kewajiban refund 2,09328 BNB sebelum klaim — jadi invarian
di atas bukan lulus di state kosong.

## Yang MASIH belum teruji (jujur)

- **Bukan fork mainnet beneran:** pair/registry/WBNB masih mock.
  `MockPair.swap()` tidak menegakkan constant-product (amount-out
  diarahkan test) — sama seperti keterbatasan suite lama. Interaksi
  dengan kontrak PancakeSwap asli dan registry Agent ID asli
  (0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F) belum diuji di fork.
- **Dividen pada skala produksi:** lihat catatan (d) — akrual per holder
  di bawah ambang klaim untuk volume wajar, dan ±44% dividen terakru ke
  saldo pair (tidak bisa diklaim), sesuai catatan desain step 2.
- **`_open()` produksi di 168.000 share melawan pair Pancake asli**
  (LP mint math asli) belum diuji; yang diuji di sini `_open` yang sama
  melawan MockPair + `openEarly` melawan MockPair.
- Echidna tidak dijalankan (sesuai arahan: invariant memakai forge
  invariant dalam satu stack Foundry).

## File yang ditambahkan

- `test/ForkOpen.t.sol` — (a) loop nyata + split escrow persis.
- `test/ForkRefund.t.sol` — (b) + (c) skenario gabungan multi-user.
- `test/ForkDividend.t.sol` — (d) swap → swapTax → claimDividend.
- `test/Invariant.t.sol` — handler + 3 invariant.
- `FORK-TEST.md` — laporan ini.

Runtime suite penuh 71,65 detik wall (88,85 detik CPU; invariant
±72 detik CPU, ForkOpen ±17 detik CPU).
