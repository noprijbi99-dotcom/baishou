# BAISHOU Whitepaper

> **Same price. Same cap. Same rules.**
> Built by an agent. Decided by a human. Proven on-chain.

BAISHOU is a fair-mint launchpad on BNB Smart Chain (BSC), designed and
operated by an AI agent (nosa.ai) under a human's direction. This document
describes the mechanism exactly as it is implemented in the deployed
contracts. If anything here ever disagrees with the contract source, the
contract source wins — it is verified and public.

- Website: https://baishou.pages.dev
- Repository: https://github.com/noprijbi99-dotcom/baishou
- X: [@baishouai](https://x.com/baishouai)

---

## 1. The problem

Most token launches are decided before the public arrives:

- **Insider allocations.** Teams, advisors, and early backers hold large
  positions bought at prices the public never sees.
- **Bending rules.** Whitelists, private rounds, and "strategic" sales mean
  the cap and the price are different depending on who you are.
- **No way back.** If a launch stalls, buyers' funds are simply gone. The
  team keeps what it raised either way.

BAISHOU is an attempt to run one launch where none of that is possible —
not by promise, but by contract design.

## 2. Design principles

1. **One price at a time, for everyone.** At any moment there is exactly one
   share price, and it is the same for the team, for referrers, and for the
   smallest buyer.
2. **One cap, for everyone.** No address may mint more than 168 shares.
   There is no whitelist tier, no referral quota, no exception.
3. **Escrow everything.** All sale proceeds stay inside the contract until
   the outcome is decided. The team cannot touch a single wei before then.
4. **Failure is refundable.** If the target is missed, buyers get 100%
   back. The team gets zero from a failed sale.

## 3. Shares and price mechanics

The sale is denominated in **shares**. One share always corresponds to
**168,000,000 BAISHOU tokens** — before the pool opens, after the pool
opens, at every price. The token amount per share never changes; only the
BNB price of a share moves.

| Parameter | Value |
|---|---|
| Total shares | 1,680,000 |
| Pre-pool phase | First 168,000 shares at a flat **0.00168 BNB** per share |
| Post-pool curve | Price rises **+2% per epoch**, one epoch = 16,800 shares, LINEAR increase |
| Price cap | **0.00336 BNB** per share (2× the starting price), never higher |
| Per-address cap | **168 shares** per wallet, for the entire sale |
| Tokens per share | **168,000,000** — fixed |

### 3.1 Pre-pool phase

The first 168,000 shares are sold at one flat price: 0.00168 BNB per share.
There is no curve, no discount, and no early-bird tier in this phase.

### 3.2 Pool opening

The moment the 168,000th share is sold, the pool opens:

- The contract seeds the BAISHOU/WBNB pair with **at least 225.792 BNB**
  and **22,579,200,000,000 tokens** (the pool is seeded at 134,400,000
  tokens per pre-pool share).
- **The LP tokens are burned** — liquidity cannot be pulled.
- Escrowed treasury and referral amounts are released (Section 5).

If a mint names no referrer, that mint's 5% referral share goes to the pool
instead, so the pool can open with up to 239.904 BNB.

### 3.3 Post-pool curve

After the pool opens, the mint continues at a price that rises linearly:
+2% of the base price for every additional epoch of 16,800 shares sold,
capped at 0.00336 BNB per share. The tokens-per-share amount stays
168,000,000 throughout.

### 3.4 Free claim

**16,800 shares are free to claim — one free share allocation per Agent
ID**, first-come, first-served, while the free allocation lasts. Free
claims carry the same 168,000,000 tokens per share as paid shares.

### 3.5 Sale window and closing

- The sale starts when the admin calls `startSale()` (one time only).
  BAISHOU's sale opens **19 Nov 2026, 15:00 UTC**.
- The target deadline is **14 days** after the start:
  **3 Dec 2026, 15:00 UTC**. If 168,000 shares are not sold by then, the
  sale has failed (Section 4).
- After the pool opens, the mint stays open for **7 more days**, then
  closes. The mint also closes immediately at sellout (1,680,000 shares).

## 4. Escrow and the refund guarantee

Every BNB paid into the mint is held in escrow by the AgentMint contract.
There is **no admin withdraw function**: escrowed funds can leave the
contract only through the paths below.

- **Target reached:** escrow is released to open the pool; treasury and
  referral shares are paid out (Section 5).
- **Target missed (14 days pass below 168,000 shares):** the sale unwinds.
  Every minter calls `claimRefund()` and receives **100% of the BNB they
  paid**. Refunds are pull-based (each user claims their own), and the
  claim window stays open for **90 days** after the deadline. Amounts left
  unclaimed after 90 days are burned, never kept by the team.
- **Changed your mind before the pool opens:** `exit()` returns **80%**
  of your BNB immediately. The 20% forfeit stays in the contract and joins
  the liquidity if the pool opens — and if the sale fails instead,
  `claimRefund()` returns 100% of everything you paid, forfeit included.

Pause never blocks refunds or exits.

## 5. Treasury and referral

Sale proceeds are split by the contract as follows — but every part is
paid **only if and when the pool opens**:

| Recipient | Share | When paid |
|---|---|---|
| Liquidity pool | 80% (≥ 225.792 BNB at target) | At pool opening, LP burned |
| Treasury | 15% | At pool opening, out of escrow |
| Referrer (if named) | 5% flat, in BNB | At pool opening, out of escrow |

- The treasury is the project's only income. If the sale fails, the
  treasury receives **zero**.
- Referral pays a flat 5% to the referrer **address** named in a mint. It
  does not raise the buyer's cap, unlock extra shares, or change any
  price. A referred buyer and an unreferred buyer play by identical rules.
- The treasury funds, among other things, a paid independent security
  review of the contracts after the pool opens.

## 6. Tokenomics

| Parameter | Value |
|---|---|
| Token | BAISHOU (AgentToken) |
| Max supply | **510,854,400,000,000** — hard cap in the contract, checked on every mint; it can never be exceeded |
| Team allocation | **None.** No tokens are pre-minted to the team |
| Tokens per share | 168,000,000 — fixed for the whole sale |
| Transfer tax | **2% on buys, 2% on sells** |

### Transfer tax split (per taxed transfer)

- **1% is burned** — sent to the DEAD address, reducing supply.
- **1% goes to holder dividends** — distributed to holders through the
  contract's dividend mechanism (`claimDividend`).

A note on scale: with a supply this large, per-holder dividend amounts are
small by construction. Dividends are a mechanism, not an income promise —
BAISHOU makes no representation that holding the token will earn anything.

## 7. Who can mint: Agent ID only

For the **entire sale**, minting is restricted to holders of a **Binance
Agent ID**. The contract checks the minter's Agent ID; regular wallets
cannot mint directly at any phase. Once the pool is open, anyone can buy
BAISHOU on the secondary market (the BAISHOU/WBNB pair) as usual.

The per-address cap of 168 shares applies per wallet address, exactly as
implemented in the contract. That is the rule, and it is the same for
everyone.

## 8. Admin powers — disclosed in full

The admin is the operator wallet. Its powers are deliberately small, and
they are listed here completely:

- **Pause** the mint (`setPaused`). Pause never blocks refunds or exits.
- **`startSale()`** — one time only. It starts the 14-day clock and
  unpauses the mint in a single transaction. Before it is called, no
  deadline runs; after it is called, it can never be called again.
- **`claimTreasury()`** — after the pool opens, claims the escrowed 15%
  treasury to the treasury address.
- Mark the independent review as passed (`setReviewPassed`), which is the
  gate for any later admin renunciation.

The admin **cannot**:

- withdraw escrowed buyer funds (no such function exists),
- change prices, caps, splits, or the supply cap (all are constants),
- mint tokens outside the sale mechanics,
- block or redirect refunds.

## 9. Contracts and verification

BSC mainnet (chain 56):

| Contract | Address |
|---|---|
| AgentToken | `0x20e62E10C18b14F36E323835B5FCe6F45FE31c1E` |
| AgentMint | `0xE69708358EC640C0bc86980893a4Afd01Aff6F9B` |
| Pair BAISHOU/WBNB | `0x86b5c0cD0f07d613E7c8b10E10a45BD0D858e4f6` |

- Source code: verified on **Sourcify (exact match)** and **BscScan** for
  both contracts — the deployed bytecode matches this repository.
- Tests: **243/243 passing** (`forge test`), including invariant tests.
- Pre-launch process: Slither static analysis, an internal red-team review
  whose findings were fixed before launch, and a full testnet rehearsal of
  every path (mint, pool open, failed refund, exit, dividends). Records:
  `DEPLOY-MAINNET.md`, `REDTEAM-2026-11-19.md` in this repository.

## 10. Risks

Read these before minting. They are part of the design, not fine print.

- **The target can miss.** If fewer than 168,000 shares sell in 14 days,
  there is no pool and no market — only the 100% refund. You get your BNB
  back, but your time and gas are spent.
- **Refunds are pull-based.** If the sale fails, you must call
  `claimRefund()` yourself within 90 days. Unclaimed refunds are burned
  after that window.
- **Early exit costs 20%.** Exiting before the pool opens forfeits 20% of
  your payment (returned only if the sale goes on to fail).
- **Post-pool price risk.** After the pool opens, BAISHOU trades on an
  open market. The mint price cap (0.00336 BNB/share) is not a floor; the
  market price can fall below what you paid.
- **Tax on transfers.** Buys and sells carry a 2% tax (Section 6). Factor
  it into any trade.
- **Smart-contract risk.** The contracts are verified, tested, and were
  reviewed before launch, and a paid independent review is planned from
  the treasury after the pool opens — but no review can guarantee a
  contract is free of bugs.
- **Agent-operated project.** BAISHOU is operated by an AI agent under a
  human's direction. Operational mistakes are possible; the escrow and
  refund design exists so that even a failed launch returns buyers' funds.

## 11. Summary

One flat starting price. One cap for every wallet. Every BNB in escrow
until the outcome is decided. The pool opens at 168,000 shares — or
everyone is refunded 100%.

**Same price. Same cap. Same rules.**
