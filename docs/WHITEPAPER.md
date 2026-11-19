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

1. **One price, for everyone.** There is exactly one share price for the
   whole sale — flat — and it is the same for the team, for referrers, and
   for the smallest buyer. When the pool opens, the mint ends; from then on
   there is only the market price, which is also the same for everyone.
2. **One cap, for everyone.** No address may mint more than 168 shares.
   There is no whitelist tier, no referral quota, no exception.
3. **Escrow everything.** All sale proceeds stay inside the contract until
   the outcome is decided. The team cannot touch a single wei before then.
4. **Failure is refundable.** If the target is missed, buyers get 100%
   back. The team gets zero from a failed sale.

## 3. Shares and price mechanics

The sale is denominated in **shares**. One share always corresponds to
**168,000,000 BAISHOU tokens** — for every buyer, at every moment of the
sale. The token amount per share never changes, and neither does the
price: the entire sale runs at one flat price.

| Parameter | Value |
|---|---|
| Total shares | **168,000** — the entire sale |
| Price | **0.00168 BNB** per share — flat for all 168,000 shares; no curve, no tiers |
| Per-address cap | **168 shares** per wallet, for the entire sale |
| Tokens per share | **168,000,000** — fixed |
| Mint closes | The moment the pool opens (Section 3.3) |

### 3.1 The sale

All 168,000 shares are sold at one flat price: 0.00168 BNB per share.
There is no curve, no discount, and no early-bird tier — the first share
and the last share cost exactly the same.

### 3.2 Pool opening

The moment the 168,000th share is sold, the pool opens:

- The contract seeds the BAISHOU/WBNB pair with **at least 225.792 BNB**
  and **22,579,200,000,000 tokens** (the pool is seeded at 134,400,000
  tokens per pre-pool share).
- **The LP tokens are burned** — liquidity cannot be pulled.
- Escrowed treasury and referral amounts are released (Section 5).
- **The mint ends.** In the same moment, the admin pauses the mint — a
  step announced publicly in advance (Section 3.3). From then on, BAISHOU
  can only be bought on the market.

If a mint names no referrer, that mint's 5% referral share goes to the pool
instead, so the pool can open with up to 239.904 BNB.

### 3.3 Why the mint ends at the pool opening — a correction, disclosed

The original design kept the mint open for 7 more days after the pool
opened, at a price rising +2% per 16,800 shares up to a cap of 0.00336 BNB
per share, for up to 1,680,000 shares in total. On 19 November 2026 —
**before the first paid mint** — we removed that design, for two reasons:

1. **It was not fair.** If the market price ran above the capped mint
   price — as it freely can — anyone still able to mint could have bought
   below market and sold into the pool at the market price. A primary sale
   running underneath a live market is a discount window for whoever uses
   it, paid for by everyone trading on the market. That contradicts the
   one rule this project exists for.
2. **Its numbers did not close.** On that post-pool path, the pool tokens
   minted per share scaled with the price, so the token supply cap
   (Section 6) would have halted the sale at ≈1,340,000 shares — the
   advertised 1,680,000 could never have been reached.

So the sale is exactly 168,000 shares at one flat price, and the mint
pauses the moment the pool opens. The pause is an admin action
(`setPaused`, Section 8), committed to publicly in advance, before any
buyer had paid. After the pool opens, the only way to buy BAISHOU is the
pool itself — one market price, the same for everyone. And with the sale
ending at 168,000 shares, the maximum supply the sale can ever mint is
53,625,600,000,000 tokens (Section 6): every published number closes
exactly.

### 3.4 Free claim

**16,800 shares are free to claim — one free share allocation per Agent
ID**, first-come, first-served, while the free allocation lasts. Free
claims carry the same 168,000,000 tokens per share as paid shares.

### 3.5 Sale window and closing

- The sale starts when the admin calls `startSale()` (one time only).
  BAISHOU's sale opened **19 Nov 2026, 15:04 UTC**.
- The target deadline is **14 days** after the start:
  **3 Dec 2026, 15:04 UTC**. If 168,000 shares are not sold by then, the
  sale has failed (Section 4).
- The mint ends the moment the 168,000th share is sold and the pool opens
  (Section 3.3). If the target is missed, the mint ends at the deadline
  and the refund path opens (Section 4).

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
| Maximum the sale can mint | **53,625,600,000,000** — 168,000 shares × (168,000,000 + 134,400,000) + 16,800 free claims × 168,000,000. The hard cap above is never approached |
| Team allocation | **None.** No tokens are pre-minted to the team |
| Tokens per share | 168,000,000 — fixed for the whole sale |
| Transfer tax | **2% on buys, 2% on sells** |

### Transfer tax — how it actually flows

- **Sells:** 1% is burned immediately (sent to the DEAD address,
  reducing supply); the other 1% is collected by the AgentMint contract.
- **Buys:** the full 2% tax is collected by the AgentMint contract
  (nothing is burned at buy time).
- Collected tax tokens are periodically swapped for BNB through the pair
  (`swapTax()`, capped per swap, available once the pool is open) and the
  BNB is deposited into the token's dividend pool. Holders claim BNB
  dividends via `claimDividend()`.

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

- **Pause** the mint (`setPaused`) — including the pre-announced pause the
  moment the pool opens (Section 3.3). Pause never blocks refunds or exits.
- **`startSale()`** — one time only. It starts the 14-day clock and
  unpauses the mint in a single transaction. Before it is called, no
  deadline runs; after it is called, it can never be called again.
- **`claimTreasury()`** — after the pool opens, claims the escrowed 15%
  treasury to the treasury address.
- Mark the independent review as passed (`setReviewPassed`), which is the
  gate for any later admin renunciation.
- **Block a scam pool** (`setPoolBlocked`) — mark an external pool
  address as blocked for token transfers. The real BAISHOU pair, the
  contracts themselves, and the treasury address can never be blocked.

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
- **Market price risk.** After the pool opens, BAISHOU trades on an open
  market at whatever price the market sets. That price can fall below the
  0.00168 BNB per share you paid — possibly far below.
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
