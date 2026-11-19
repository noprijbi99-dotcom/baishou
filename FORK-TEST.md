# BAISHOU — FORK TEST: MONEY PATHS + INVARIANTS (19 Nov 2026)

An honest report of the pre-mint gate results that were previously untested. All new tests
were written in SEPARATE files (`test/Fork*.t.sol`, `test/Invariant.t.sol`);
no old tests and no contract code were changed. Everything runs
on a local Foundry EVM with the same mocks as the old suite (MockRegistry,
MockWBNB, MockPair) — **no mainnet/testnet transactions were sent,
no real wallets were used.**

## Final results

```
forge test (FULL suite, old + new)
11 suites: 192 passed, 0 failed, 0 skipped
Old suite (7 files): 139 tests — ALL still green.
Invariants: 256 runs, 128.000 calls, 0 reverts.
```

## (a) Pool-open — REAL loop of 168.000 shares — `test/ForkOpen.t.sol` ✅

The difference from the old `PoolOpen.t.sol`: there the pool was opened with
`_fastForwardToOpen()` (vm.store fakes 167.999 shares). Here
**1.000 real agents** are registered in MockRegistry and each mints
168 shares (MAX_PER_TX = the per-ID cap) at the production price (priceDiv = 1),
all with one and the same referrer, until OPEN_AT is genuinely reached.

Numbers verified from contract constants (cross-checked against literals):

| Item | Result |
|---|---|
| totalMinted | 168.000 = OPEN_AT, `opened()` = true, trading active |
| Total pre-pool deposits (totalPaid) | 282,24 BNB |
| Treasury 15% | **42,336 BNB** — received by the treasury exactly |
| Referral 5% | **14,112 BNB** — fully accrued, claimed via `claimReferral()` |
| Pool (pair reserves) | 225,792 BNB + 22.579.200.000.000 tokens (= OPEN_BNB / OPEN_TOKENS) |
| participantCount | 1.000 unique participants |

An important mechanism nuance (per the code, not assumption): the pre-pool treasury
cut is **paid automatically once in `_open()`** (via
`_payOrOwe`), NOT through `claimTreasury()` — proven by
`claimTreasury()` right after the pool opens reverting `NothingOwed` and
`escrowTreasury() == 0`. `claimTreasury()` is the POST-pool accrual path;
that was also verified in the same test: 1 post-pool mint accrued
its 15% and the treasury successfully claimed it to zero.

Gas note (honest): a real loop of 168.000 share-iterations consumes
±1,62 billion gas of EVM execution — above forge's default per-test metering
cap (2^30). The loop is therefore wrapped in `vm.pauseGasMetering()` /
`vm.resumeGasMetering()`: what is disabled is ONLY the test runner's gas accounting,
execution is still complete (proven separately: with
`FOUNDRY_GAS_LIMIT=20000000000` and no pause, the same test passes with
measured gas of 1.622.820.003). All assertions run with normal metering.
This test's runtime is ±17 seconds.

## (b) claimRefund 100% when the sale fails — `test/ForkRefund.t.sol` ✅

Combined scenario: alice mints 100, bob mints 50 (referrer alice), carol
mints 20; carol exits FULLY, alice exits PARTIALLY (40); then the deadline passes.

- Carol's exit: back 0,02688 BNB (80%), forfeit 0,00672 BNB recorded.
- Alice's exit of 40: back 0,05376 BNB (80%), forfeit 0,01344 BNB.
- **Mid-way solvency proof:** contract WBNB balance ==
  total refund obligations (Σ deposits + forfeitOf) == **0,20496 BNB**, exactly.
- After `saleFailed()`: alice's refund = **0,11424** (deposits 0,1008 +
  forfeit 0,01344), bob = **0,084** (full deposit), carol = **0,00672**
  (forfeit only) — all exact to the wei.
- End: obligations 0, contract WBNB balance 0, treasury still 0.
- `claimReferral()` after failure still reverts `NotOpen` (the pool
  never opened — referral commissions do not leak out on a failed launch).

## (c) exit() 80% before the pool opens — `test/ForkRefund.t.sol` ✅

Besides the exit numbers in scenario (b), there is a dedicated test: a minter of 168 shares
WITH a referrer exits FULLY → back 0,225792 of 0,28224 BNB (exactly 80%
), and the already-accrued cuts roll back cleanly:
`escrowTreasury`, `referralAccrued`, `pendingBnb` all return to 0;
the remaining contract escrow == forfeit 0,056448 BNB (the last refund obligation).

## (d) claimDividend from swap tax — `test/ForkDividend.t.sol` ✅

The FULL chain like production (not a direct `depositDividends` deposit
like some old tests): the pool is opened small via `openEarly()` (alice
168 shares; treasury receives 0,042336 BNB at open; pool 0,239904 BNB +
22.579.200.000 tokens) → bob **buys through `pair.swap()`** (pays 0,2125
WBNB, receives 98% = 19,6 billion tokens; 2% buy tax = 400 million tokens
goes to the minter) → `swapTax()` 12× (one per block, all succeed) sells
the tax tokens for BNB → BNB enters the dividend pool (`totalDividends > 0`,
`feeTreasury` stays 0) → alice `claimDividend()`: her accrual
is ≥ the 0,001 BNB minimum threshold and the claim pays **exactly**
`withdrawableDividendOf` moments before the claim; the second claim = 0.

Why a small pool: at production scale (168.000 shares) per-holder dividends
are indeed dust below the 0,001 BNB threshold for realistic swap volumes —
a design recorded since step 2, not a new finding. The same code path
is verified here at a supply fraction that makes the threshold
reachable by real swap tax.

## Invariants — `test/Invariant.t.sol` ✅

A handler of 8 agents performs random actions: mint (with rotating referrers),
exit, freeMint, claimRefund, and time warps (crossing the failure deadline).
**256 runs × 500 calls = 128.000 calls, 0 reverts, three invariants hold:**

1. **Pre-pool escrow solvency:** contract WBNB balance ≥ Σ (deposits +
   forfeitOf) of all agents — including after the deadline and after random refund
   claims legitimately drain the escrow.
2. `totalMinted` ≤ TOTAL_SHARES (1.680.000) — always.
3. Token `totalSupply` ≤ MAX_SUPPLY (510.854.400.000.000) — always.

Handler non-triviality was verified separately (one-off test,
deleted afterwards): a manual handler drive produced 1.246 minted shares
and refund obligations of 2,09328 BNB before claims — so the invariants
above did not pass on an empty state.

## What is STILL untested (honest)

- **Not a real mainnet fork:** pair/registry/WBNB are still mocks.
  `MockPair.swap()` does not enforce constant-product (amount-out
  is test-directed) — the same limitation as the old suite. Interactions
  with the real PancakeSwap contracts and the real Agent ID registry
  (0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F) have not been tested on a fork.
- **Dividends at production scale:** see note (d) — per-holder accrual
  below the claim threshold for reasonable volumes, and ±44% of dividends accrue to
  the pair's balance (unclaimable), per the step-2 design notes.
- **Production `_open()` at 168.000 shares against a real Pancake pair**
  (real LP mint math) not yet tested; what was tested here is the same `_open`
  against MockPair + `openEarly` against MockPair.
- Echidna was not run (per direction: invariants use forge
  invariant within one Foundry stack).

## Files added

- `test/ForkOpen.t.sol` — (a) real loop + exact escrow split.
- `test/ForkRefund.t.sol` — (b) + (c) combined multi-user scenario.
- `test/ForkDividend.t.sol` — (d) swap → swapTax → claimDividend.
- `test/Invariant.t.sol` — handler + 3 invariants.
- `FORK-TEST.md` — this report.

Full suite runtime 71,65 seconds wall (88,85 seconds CPU; invariants
±72 seconds CPU, ForkOpen ±17 seconds CPU).
