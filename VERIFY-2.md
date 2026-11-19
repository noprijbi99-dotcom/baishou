# BAISHOU — VERIFY-2 (verifikasi wave-2, 19 Nov 2026)

Putaran kedua atas perintah user: "jangan puas dengan sekali test, kita
harus meminimalisir miss." Tiga pekerjaan: (1) audit kualitas asersi
wave-1, (2) multi-seed runs, (3) test adversarial baru untuk celah yang
belum ter-cover. **src/ dan test lama TIDAK diubah sama sekali.**
File baru satu-satunya: `test/Adversarial.t.sol`.

## Ringkasan hasil

- Multi-seed: 4 seed × suite penuh (211 test) — **semua hijau**.
- Invariant dinaikkan: **512 runs / 256.000 calls / 0 reverts — hijau**.
- Adversarial: 7 test baru — **semua lulus**. Tidak ada perilaku kontrak
  yang menyimpang dari spek → **tidak ada FINDING kontrak** (lihat §4).
- Audit asersi wave-1: tidak ada asersi yang batal total, tapi ada
  7 catatan kualitas (W1–W7, §1) — sebagian besar sudah termitigasi
  test lain; satu yang paling substantif: W2.

---

## 1. Audit kualitas asersi wave-1

Metode: setiap ekspektasi di `ForkOpen/ForkRefund/ForkDividend/
Invariant.t.sol` ditelusuri asal angkanya — literal independen / hitungan
spek vs dibaca balik dari kontrak yang diuji (sirkular: test tetap hijau
walau kontrak salah secara konsisten).

### ForkRefund.t.sol — BERSIH (yang terkuat)
Semua ekspektasi payout adalah literal keras independen: referral 0,0042
(:25), exit carol 0,02688 + forfeit 0,00672 (:31-32), exit alice 0,05376 +
forfeit 0,01344 (:37-38), deposit sisa 0,1008/0,084 (:41-42), refund
0,11424 / 0,084 / 0,00672 (:65-83), exit penuh 0,225792 + forfeit
0,056448 (:92-96). Dua equality kontrak-vs-kontrak terjangkar literal di
test yang sama: solvabilitas escrow (:44-49, total kewajiban di-pin
0,20496 dulu) dan sisa escrow == forfeitOf (:99, forfeitPool di-pin
0,056448 di :96). Tidak ada catatan.

### ForkOpen.t.sol
- **W1 (sedang-rendah) — :29-31, :91.** Input dan asersi pertama
  kontrak-derivatif: `sharesPerAgent = mint.MAX_PER_TX()`,
  `cost168 = mint.costOf(...)`, lalu `cost168 == sharesPerAgent *
  mint.BASE_PRICE()`. Ini hanya membuktikan konsistensi internal costOf
  vs konstanta — bukan harga spek. `deposits(agen0) == cost168` (:91)
  mewarisi kelemahan yang sama. **Mitigasi:** BASE_PRICE di-pin ke
  literal 0,00168 ether di `Baishou.t.sol::test_BaishouParameterTargets`,
  dan total file ini di-pin literal (282,24 / 42,336 / 14,112 di :59-61),
  jadi rantainya tertutup — tapi asersi lokalnya sendiri sirkular.
- **W2 (paling substantif) — :98-106.** Seksi claimTreasury PASCA-pool:
  ekspektasi (`costPost`, `accruedPost`) dihitung 100% dari getter
  kontrak (`costOf(1)`, `TREASURY_BPS()`) TANPA cross-check literal satu
  pun. Kalau harga pasca-pool atau potongan 15%-nya salah secara
  konsisten, seksi ini tetap hijau. **Mitigasi parsial:** split pre-pool
  terjangkar literal persis (42,336 = 15% × 282,24; 14,112 = 5%), dan
  harga epoch pasca-pool diuji terpisah di `PoolOpen.t.sol:44,125`.
  Rekomendasi wave-3: pin `costOf(1)` pasca-openEarly ke literal di
  test treasury pasca-pool.
- **W3 (rendah) — :52, :83.** `totalMinted == mint.OPEN_AT()` dan
  reserve token `== mint.OPEN_TOKENS()`: perbandingan ke konstanta
  kontrak tanpa literal di file ini. **Mitigasi:** kedua konstanta
  di-pin literal di `Baishou.t.sol::test_BaishouParameterTargets`
  (168.000; 22.579.200.000.000 ether). Reserve BNB justru ganda
  (:81-82: konstanta + literal 225,792) — pola yang benar.

### ForkDividend.t.sol
- **W4 (sedang-rendah) — :61-68.** Jumlah klaim sirkular: `due` dibaca
  dari `withdrawableDividendOf(alice)`, lalu delta saldo diassert
  `== due`. Yang terbukti: mekanisme klaim (bayar persis sebesar view,
  nol sesudahnya, tak bisa ganda) — BUKAN kebenaran jumlah dividennya.
  **Mitigasi:** `Dividend.t.sol::test_DividendAccruesProRata` menguji
  rasio akumulator (alice 2× bob, toleransi 10 wei, atas setoran
  diketahui 100 BNB) — rasio terjangkar, jumlah absolut per holder
  terhadap hitungan independen penuh memang belum ada (praktis sulit:
  ±44% supply di pair ikut pro-rata).
- **W5 (rendah) — :57.** BNB hasil swapTax hanya diassert
  `totalDividends > 0` — tanpa ekspektasi kuantitatif/batas apa pun.
- **W6 (rendah) — :31.** Reserve token pool `== 168 * mint.POOL_SHARE()`
  — konstanta kontrak; di-pin literal 134.400.000 ether di Baishou.t.sol.

### Invariant.t.sol
- **W7 (rendah, inheren) — :94-104 + handler :42-80.** Invarian 1
  menjumlah kewajiban dari mapping kontrak sendiri (`deposits` +
  `forfeitOf`): membuktikan solvabilitas TERHADAP kewajiban yang
  tercatat — tidak bisa mendeteksi pencatatan deposit yang sistematis
  salah (mis. selalu separuh). Handler juga tanpa ghost counter dan
  semua aksi try/catch: run degeneratif (semua aksi revert) akan lulus
  hampa. **Mitigasi terdokumentasi:** non-trivialitas dibuktikan
  terpisah di wave-1 (FORK-TEST.md :110-112 — drive manual menghasilkan
  1.246 share + kewajiban 2,09328 BNB sebelum klaim). Invarian 2-3
  membandingkan ke konstanta kontrak (TOTAL_SHARES / MAX_SUPPLY) yang
  ter-pin literal di Baishou.t.sol.

**Kesimpulan audit:** tidak ada asersi wave-1 yang "palsu hijau" secara
menyeluruh — setiap angka uang utama (282,24 / 42,336 / 14,112 /
225,792 / semua payout refund & exit) pada akhirnya terjangkar literal
independen di file yang sama atau di Baishou.t.sol. Kelemahan terkumpul
di (a) harga/akrual pasca-pool (W2) dan (b) jumlah absolut dividen (W4).

---

## 2. Multi-seed runs

Suite penuh = 211 test (192 wave-1 + 7 adversarial baru + pewarisan base
di suite baru), 12 suite. Perintah: `forge test --fuzz-seed <seed>`.

| Seed | Hasil | Durasi |
|---|---|---|
| 1 | 211 passed, 0 failed, 0 skipped | 74,84 dtk |
| 42 | 211 passed, 0 failed, 0 skipped | 77,40 dtk |
| 1337 | 211 passed, 0 failed, 0 skipped | 78,73 dtk |
| 20261119 | 211 passed, 0 failed, 0 skipped | 86,55 dtk |

Invariant dinaikkan (forge 1.9 tidak punya flag `--invariant-runs`;
dipakai env `FOUNDRY_INVARIANT_RUNS=512`, tanpa mengubah foundry.toml):

| Konfigurasi | Hasil |
|---|---|
| `FOUNDRY_INVARIANT_RUNS=512`, seed 777 | 3 invarian PASS — **runs: 512, calls: 256.000, reverts: 0** |

Tidak ada kegagalan yang bergantung seed.

---

## 3. Test adversarial baru — `test/Adversarial.t.sol` (7 test)

Fokus file ini = celah yang BENAR-BENAR belum ter-cover: reentrancy dan
gerbang claimTreasury. Penyerang = kontrak `ReentrantClaimer` (pemegang
Agent ID) yang receive()-nya menembakkan satu panggilan balik low-level
dan mencatat hasilnya; mandat yang diassert: panggilan reentrant selalu
GAGAL (`reentrySuccesses == 0`) dan payout luar PERSIS haknya, sekali.

| Test | Skenario | Hasil |
|---|---|---|
| `test_Reentrancy_ClaimRefundPaysExactlyOnce` | reenter claimRefund di tengah payout refund gagal-launch | PASS — diterima persis 0,0168 BNB sekali |
| `test_Reentrancy_ClaimRefundCannotCrossIntoExit` | reenter exit(1) di tengah payout refund (serangan silang: mintedCount belum berkurang) | PASS — total tetap 100%, share utuh |
| `test_Reentrancy_ExitPaysExactlyOnce` | reenter exit(1) di tengah payout exit parsial 5/10 | PASS — diterima persis 0,00672 (80%×5), forfeit hanya 0,00168 |
| `test_Reentrancy_ClaimDividendPaysExactlyOnce` | reenter claimDividend (fungsi TANPA nonReentrant — perlindungan murni CEI) | PASS — dibayar persis `due` sekali, withdrawable 0 |
| `test_Reentrancy_ClaimTreasuryPaysExactlyOnce` | treasury = kontrak penyerang (stack terpisah, openEarly + akrual pasca-pool) | PASS — 0,00252 (di _open) + 0,000252 (klaim) persis; klaim ulang NothingOwed |
| `test_ClaimTreasuryBeforeOpenReverts` | treasury klaim saat escrow terisi tapi pool belum buka | PASS — revert NotOpen |
| `test_ClaimTreasuryOnlyTreasury` | bukan treasury memanggil claimTreasury | PASS — revert NotTreasury |

Catatan pertahanan: di semua jalur, urutan CEI kontrak (state di-nol-kan
SEBELUM transfer) membuat sebagian besar reentrancy gagal bahkan sebelum
ReentrancyGuard bekerja; guard memblokir sisanya (termasuk cross-function
karena satu guard bersama). Defense-in-depth terverifikasi, tidak ada
jalur ekstraksi melebihi hak.

### Pemetaan item brief → cakupan yang SUDAH ada (tidak diduplikasi)
| Item | Lokasi |
|---|---|
| Klaim refund ganda (ke-2 revert) | `RefundFail.t.sol:29-31` (NothingOwed) |
| claimRefund sebelum failureTime | `RefundFail.t.sol:85-90` (NotFailed); sesudah pool buka `:77-83` |
| Exit sesudah pool buka | `RefundExit.t.sol:75-81` (ExitClosed) |
| Mint saat paused | `Baishou.t.sol::test_MintWhilePausedReverts`; freeMint paused `Mint.t.sol:134-140` |
| Mint lewat deadline / tutup | `Baishou.t.sol::test_SaleFailedAfterDeadline`; tutup pasca-pool `PoolOpen.t.sol:65-74` |
| freeMint 2× | `Mint.t.sol:105-121` (AlreadyGranted) |
| Cap 168/wallet / MAX_PER_TX | `Mint.t.sol:20-29` (Quota) / `:31-36` (BadShares) |
| claimReferral sebelum pool buka | `PoolOpen.t.sol:142-149`, `ForkRefund.t.sol:66-69` (NotOpen) |
| sweepUnclaimed sebelum jendela / sesudah | `RefundFail.t.sol:65-75` (NotSweepable, incl. tepat di batas) / `:49-63` (ke DEAD persis) |
| Pause tidak memblokir claimRefund / exit | `RefundFail.t.sol:104-113` / `RefundExit.t.sol:83-91` |
| Self-referral & referrer tanpa Agent ID | `Mint.t.sol:60-75` (5% jatuh ke pool) |
| Referrer zero-address | `Mint.t.sol:49-58` (pendingBnb 85%) |
| Dividen < 0,001 BNB revert, akrual tidak hangus | `Dividend.t.sol:102-124` (DividendTooSmall + withdrawable tetap) |

---

## 4. FINDINGS

**Tidak ada finding kontrak.** Tidak satu pun perilaku aktual menyimpang
dari spek/desain di semua test wave-2 (adversarial + multi-seed +
invariant 512 runs). Tidak ada test yang dipaksa hijau; tidak ada src/
yang disentuh.

Yang ada hanyalah catatan kualitas test (W1–W7 di §1) — kelemahan
asersi, bukan bug kontrak. Dua rekomendasi wave-3 bila mau ditutup:
(1) pin literal harga pasca-pool di test akrual treasury (W2);
(2) hitungan dividen absolut independen untuk satu holder pada skenario
terkontrol (W4). Keduanya perbaikan test, bukan perbaikan kontrak.

Sisa keterbatasan yang sama seperti wave-1 (di luar cakupan wave ini):
pair/registry/WBNB masih mock lokal; interaksi melawan PancakeSwap dan
registry Agent ID asli belum diuji di fork mainnet beneran.
