# BAISHOU — $BAISHOU

> **Same price. Same cap. Same rules.**
> Built by an agent. Decided by a human. Proven on-chain.

A fair mint for Binance Agent ID holders. No team allocation, no presale, no
insider price: all 168,000 shares sell at one flat price of 0.00168 BNB, and
every share carries a fixed 168,000,000 tokens. The mint ends the moment the
pool opens — after that, the only way to buy is the market itself, at the
market price, the same for everyone. Every BNB paid sits in escrow inside
the contract. If the 168,000-share target is not reached within 14 days,
everyone claims a 100% refund. If you want out before the pool opens, you
get 80% back.

## Status: LIVE on BSC mainnet (v3)

| Contract | Address |
|---|---|
| AgentToken | `0x20e62E10C18b14F36E323835B5FCe6F45FE31c1E` |
| AgentMint | `0xE69708358EC640C0bc86980893a4Afd01Aff6F9B` |
| Pair BAISHOU/WBNB | `0x86b5c0cD0f07d613E7c8b10E10a45BD0D858e4f6` |

- Source verified: Sourcify **exact match** and BscScan verified, both contracts.
- Tests: 243/243 passing (`forge test`).
- Sale opens: **19 Nov 2026, 15:00 UTC** (one-time `startSale()` by the admin).
- Sale deadline: **3 Dec 2026, 15:00 UTC** (start + 14 days). Miss it → 100% refunds.
- Full deploy record: `DEPLOY-MAINNET.md` §11. Design: `docs/WHITEPAPER.md`, `docs/FAQ.md`.
- Website: https://baishou.pages.dev

## Design

| Parameter | Value |
|---|---|
| Total shares | 168,000 — the entire sale |
| Price | 0.00168 BNB per share, flat — no curve, no tiers, first share = last share |
| Tokens per share | 168,000,000 — fixed, always (pool is seeded at 134,400,000/share) |
| Pool opens at | 168,000 shares sold: ≥ 225.792 BNB + 22,579,200,000,000 tokens, LP burned |
| Mint ends | The moment the pool opens (admin pause, announced in advance) — after that, market only |
| Free claim | 16,800 free claims of one share's tokens (168,000,000 each), 1 per Agent ID, first-come |
| Cap | 168 shares per address — the team plays by the same cap |
| Gate | Agent ID only for the entire sale; regular wallets buy on the secondary market after the pool opens |
| Max supply | 510,854,400,000,000 hard cap, checked on every mint — the sale can mint at most 53,625,600,000,000, so the cap is never approached |
| Treasury | 15% of sale proceeds — held in escrow, paid ONLY when the pool opens |
| Referral | 5% flat — held in escrow, paid ONLY when the pool opens |
| Trading tax | 2% buy / 2% sell (sell: 1% burned to DEAD at transfer; collected tax is swapped to BNB for holder dividends) |
| Failed sale | 100% refund via `claimRefund()` — pull-based, 90-day claim window |
| Pre-pool exit | 80% back via `exit()`; if the sale later fails, exiters also claim back to 100% |
| Admin | The admin wallet can: pause, call `startSale()` once, claim the treasury after the pool opens, and block external scam pools (the real pair can never be blocked). The admin can NOT withdraw escrowed buyer funds — no such function exists. |

**Sale-design correction — 19 Nov 2026, before the first paid mint.** The
original design kept the mint open after the pool opened, at a price rising
in steps to at most 0.00336 BNB per share, for up to 1,680,000 shares in
total. That design was removed before any buyer had paid: while the market
could trade far above the capped mint price, minters could have bought
below market and sold into the pool — not fair. (Its numbers also did not
close: pool tokens per share scaled with price on that path, so the supply
cap would have halted it at ≈1,340,000 shares anyway.) The sale is now
exactly 168,000 shares at one flat price, and the mint pauses the moment
the pool opens. Full disclosure: `docs/WHITEPAPER.md` §3.3.

Team income is ONLY the 15% treasury — and only if the pool opens. If the
target misses, the team gets 0 and every buyer is refunded in full.

## Contracts

- `src/AgentMint.sol` + `src/AgentToken.sol`: built from a fork of `$AIC`
  (AgentMint `0x55E1501815127A199314B586e59239608Ce4C15C`, BscScan-verified),
  extended with the BAISHOU mechanics: `freeMint`, `exit`, `claimRefund`,
  dividend accumulator, treasury/referral escrow, and the one-time `startSale`.
- `src/libraries/BurnMath.sol` does **NOT** come along — the floor burn is
  removed entirely (burn ≠ BNB liquidity).
- `src/vendor/openzeppelin/`: OZ files (MIT) from AIC's verified source.

## Build & test

```sh
forge build   # solc 0.8.28, optimizer runs 200, evm paris
forge test    # 243/243 green
```

## Audit trail

1. `forge test` + invariants (this repo).
2. Slither baseline, 19 Nov 2026: `slither-baseline-2026-11-19.json` —
   all High/Medium findings triaged in writing before mainnet.
3. Internal red-team review, 19 Nov 2026: `REDTEAM-2026-11-19.md` — the v1
   flaws it caught were fixed in v2/v3 before a single mint.
4. BSC testnet: all paths exercised (mint, pool open, failed refund, exit, dividends).
5. Paid independent review is funded from the treasury when the pool opens.

## Security rules

- PULL refunds, never mass-push. Pause never blocks refunds.
- The contract has NO admin withdraw function — escrowed funds can only go
  to the pool (on success) or back to buyers (refund/exit).
- Source verified on BscScan + Sourcify before announcement.

## Skill

Operations (mint, checks, `baw` preflight, audit checklist):
`~/workspace/custom-skills/baishou/SKILL.md`.
