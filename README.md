# BAISHOU — $BAISHOU

> **Same price. Same cap. Same rules.**

Fair mint for Binance Agent ID holders, with no team allocation: the first 168.000 shares
at 0,00168 BNB get a fixed 168.000.000 tokens. Price rises max 2x (not 8x).
If the 168.000-share target is not reached within 7 days, money back 100%.
If you want out before the pool opens, back 80%.

⚠️ **STATUS: DRAFT — NOT THE FINAL CONTRACT. DO NOT DEPLOY.**
This repo is a build scaffold: AIC fork + test skeleton + skill. Finalization needs
parameterization, new functions (freeMint / exit / claimRefund / dividends),
Slither + full tests + independent review, per the `baishou` skill.

## Design

Design source of truth: `~/workspace/launchpad-research/POLA-BARU-ARUNIKA.md`
(Option B, decided 19 Nov 2026). In short:

| Parameter | Value |
|---|---|
| Total shares | 1.680.000 |
| Pre-pool | 168.000 shares @ 0,00168 BNB flat |
| Tokens/share | 168.000.000 (pool receives 134.400.000/share) |
| Pool open | Share 168.000: 225,792 BNB + 22,5792 trillion tokens, LP to DEAD |
| Post-pool curve | Epoch +2% per 16.800 shares, cap 0,00336 BNB (2x), LINEAR |
| Free | 16.800 shares @ 168.000.000 tokens (1 per Agent ID, first-come) |
| Cap | 168 shares per address (team the same) |
| Gate | Agent ID-only for the entire sale; regular wallets buy secondary after the pool opens |
| Max supply | 510,8544 trillion (contract hard cap) |
| Treasury | 15% — paid WHEN the pool opens (escrow), not instant |
| Referral | 5% flat — paid WHEN the pool opens (escrow) |
| Trading tax | 2% buy / 2% sell (1% burn + 1% holder dividends); team 0% of tax |
| Failed refund | 100% via PULL claim, 90-day window, leftovers burned to DEAD |
| Pre-pool exit | Back 80%; 20% forfeit → LP (failed = 100% back to exiters) |
| Mint closes | 7 days after the pool opens OR 1.680.000 shares |
| Admin | Pause only; renounce AFTER the independent review completes |
| Refundable deposit | Phase 2 |

Team income is ONLY the 15% treasury from sales — and even that is only paid
after the pool opens. If nobody mints, the team gets 0.

## Fork

- `src/AgentMint.sol` + `src/AgentToken.sol`: fork of `$AIC`
  (AgentMint `0x55E1501815127A199314B586e59239608Ce4C15C`, BscScan-verified).
- `src/libraries/BurnMath.sol` does **NOT** come along — the floor burn is removed entirely
  (design §10 #1: burn ≠ BNB liquidity). The call site in `_curveShare` has been
  removed; leftover dead-code burn is marked `TODO(final)`.
- `src/vendor/openzeppelin/`: OZ files (MIT) from AIC's verified source.
- Not yet in the fork (written at finalization): `freeMint`, `exit`,
  `claimRefund`, dividend accumulator, Agent Registry, treasury/referral escrow.

## Build & test

```sh
forge build   # solc 0.8.28, optimizer runs 200, evm paris
forge test    # tests without vm.skip must be green; skipped tests = BAISHOU targets
```

## Audit (free, layered — before mainnet)

1. `forge test` + invariants (this repo).
2. `slither . --exclude-dependencies` (venv `~/.venvs/slither`, solc 0.8.28
   via solc-select) — first baseline 19 Nov 2026:
   78 findings (2 High, 17 Medium, 25 Low, 34 Informational), file
   `slither-baseline-2026-11-19.json`. All High/Medium must be triaged
   (fixed or justified in writing) before testnet.
3. BSC testnet: all paths (mint, pool open, failed refund, exit, dividends).
4. Community forensic audit via Square (free) + paid independent review
   from the treasury WHEN the pool opens — then renounce.

## Security (§8b rules)

- PULL refunds, never mass-push. Pause never blocks refunds.
- The contract has NO withdraw function — funds only go to depositors or the pool.
- Fresh deployer wallet, gas only. Testnet before mainnet.
- Source verified on BscScan + Sourcify BEFORE announcement.

## Skill

Operations (mint, checks, `baw` preflight, audit checklist):
`~/workspace/custom-skills/baishou/SKILL.md`.
