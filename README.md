# BAISHOU — $BAISHOU

> **Same price. Same cap. Same rules.**

Fair mint untuk pemegang Binance Agent ID, tanpa alokasi tim: 16.800 share
pertama 0,00168 BNB dapat 168.000 token tetap. Harga naik max 2x (bukan 8x).
Kalau target 16.800 share tidak tercapai dalam 7 hari, uang kembali 100%.
Kalau mau keluar sebelum pool buka, kembali 80%.

⚠️ **STATUS: DRAFT — BUKAN KONTRAK FINAL. JANGAN DEPLOY.**
Repo ini kerangka build: fork AIC + test skeleton + skill. Finalisasi butuh
parameterisasi, fungsi baru (freeMint / exit / claimRefund / dividen),
Slither + test penuh + review independen, sesuai skill `baishou`.

## Desain

Sumber kebenaran desain: `~/workspace/launchpad-research/POLA-BARU-ARUNIKA.md`
(Opsi B, diputuskan 19 Nov 2026). Ringkasnya:

| Parameter | Nilai |
|---|---|
| Total shares | 168.000 |
| Pre-pool | 16.800 share @ 0,00168 BNB flat |
| Token/share | 168.000 (pool terima 134.400/share) |
| Pool open | Share 16.800: 22,5792 BNB + 2,25792 miliar token, LP ke DEAD |
| Kurva pasca-pool | Epoch +2% per 1.680 share, cap 0,00336 BNB (2x), LINEAR |
| Free | 1.680 share @ 16.800 token (1 per Agent ID, first-come) |
| Cap | 168 share per alamat (tim sama) |
| Gate | 24 jam Agent ID-only, max 8.400 share, lalu semua wallet |
| Treasury | 15% — dibayar SAAT pool buka (escrow), bukan instan |
| Referral | 5% flat — dibayar SAAT pool buka (escrow) |
| Pajak trading | 2% beli / 2% jual (1% burn + 1% dividen holder); tim 0% dari pajak |
| Refund gagal | 100% via klaim PULL, jendela 90 hari, sisa dibakar ke DEAD |
| Exit pre-pool | Kembali 80%; 20% forfeit → LP (gagal = 100% balik ke exiters) |
| Mint tutup | 7 hari setelah pool buka ATAU 168.000 share |
| Admin | Cuma pause; renounce SETELAH review independen selesai |
| Deposit refundable | Fase 2 |

Pendapatan tim HANYA treasury 15% dari penjualan — dan itu pun baru dibayar
setelah pool buka. Kalau tidak ada yang mint, tim dapat 0.

## Fork

- `src/AgentMint.sol` + `src/AgentToken.sol`: fork `$AIC`
  (AgentMint `0x55E1501815127A199314B586e59239608Ce4C15C`, terverifikasi BscScan).
- `src/libraries/BurnMath.sol` **TIDAK** ikut — floor burn dihapus total
  (desain §10 #1: burn ≠ likuiditas BNB). Call site di `_curveShare` sudah
  dicabut; sisa dead-code burn ditandai `TODO(final)`.
- `src/vendor/openzeppelin/`: file OZ (MIT) dari source terverifikasi AIC.
- Yang BELUM ada di fork (ditulis saat finalisasi): `freeMint`, `exit`,
  `claimRefund`, dividend accumulator, Agent Registry, escrow treasury/referral.

## Build & test

```sh
forge build   # solc 0.8.28, optimizer runs 200, evm paris
forge test    # test tanpa vm.skip harus hijau; test skip = target BAISHOU
```

## Audit (gratis, berlapis — sebelum mainnet)

1. `forge test` + invariant (repo ini).
2. `slither . --exclude-dependencies` (venv `~/.venvs/slither`, solc 0.8.28
   via solc-select) — baseline pertama 19 Nov 2026:
   78 temuan (2 High, 17 Medium, 25 Low, 34 Informational), file
   `slither-baseline-2026-11-19.json`. Semua High/Medium harus triase
   (perbaiki atau justifikasi tertulis) sebelum testnet.
3. Testnet BSC: semua jalur (mint, pool open, refund gagal, exit, dividen).
4. Audit forensik komunitas via Square (gratis) + review independen berbayar
   dari treasury SAAT pool buka — baru renounce.

## Keamanan (aturan §8b)

- Refund PULL, jangan mass-push. Pause tidak pernah memblokir refund.
- Kontrak TIDAK PUNYA fungsi withdraw — dana hanya ke deposan atau pool.
- Deployer wallet segar, isi gas saja. Testnet dulu sebelum mainnet.
- Source terverifikasi BscScan + Sourcify SEBELUM pengumuman.

## Skill

Operasional (mint, cek, preflight `baw`, audit checklist):
`~/workspace/custom-skills/baishou/SKILL.md`.
