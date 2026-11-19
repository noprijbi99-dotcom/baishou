# BAISHOU — VERIFY-2 (wave-2 verification, 19 Nov 2026)

Second round on the user's order: "don't be satisfied with a single test, we
must minimize misses." Three jobs: (1) audit the assertion quality of
wave-1, (2) multi-seed runs, (3) new adversarial tests for the gaps
not yet covered. **src/ and old tests were NOT changed at all.**
The only new file: `test/Adversarial.t.sol`.

## Results summary

- Multi-seed: 4 seeds × full suite (211 tests) — **all green**.
- Invariants raised: **512 runs / 256.000 calls / 0 reverts — green**.
- Adversarial: 7 new tests — **all pass**. No contract behavior
  deviates from spec → **no contract FINDINGS** (see §4).
- Wave-1 assertion audit: no assertion is totally void, but there are
  7 quality notes (W1–W7, §1) — most already mitigated by
  other tests; the most substantive one: W2.

---

## 1. Wave-1 assertion quality audit

Method: every expectation in `ForkOpen/ForkRefund/ForkDividend/
Invariant.t.sol` was traced to the origin of its numbers — independent literals / spec
calculations vs read back from the contract under test (circular: the test stays green
even if the contract is consistently wrong).

### ForkRefund.t.sol — CLEAN (the strongest)
All payout expectations are independent hard literals: referral 0,0042
(:25), carol's exit 0,02688 + forfeit 0,00672 (:31-32), alice's exit 0,05376 +
forfeit 0,01344 (:37-38), remaining deposits 0,1008/0,084 (:41-42), refunds
0,11424 / 0,084 / 0,00672 (:65-83), full exit 0,225792 + forfeit
0,056448 (:92-96). Two contract-vs-contract equalities are literal-anchored in
the same test: escrow solvency (:44-49, total obligations pinned at
0,20496 first) and remaining escrow == forfeitOf (:99, forfeitPool pinned at
0,056448 at :96). No notes.

### ForkOpen.t.sol
- **W1 (medium-low) — :29-31, :91.** First inputs and assertions are
  contract-derivative: `sharesPerAgent = mint.MAX_PER_TX()`,
  `cost168 = mint.costOf(...)`, then `cost168 == sharesPerAgent *
  mint.BASE_PRICE()`. This only proves costOf's internal consistency
  vs the constants — not the spec price. `deposits(agent0) == cost168` (:91)
  inherits the same weakness. **Mitigation:** BASE_PRICE is pinned to the
  literal 0,00168 ether in `Baishou.t.sol::test_BaishouParameterTargets`,
  and this file's totals are literal-pinned (282,24 / 42,336 / 14,112 at :59-61),
  so the chain is closed — but its local assertions themselves are circular.
- **W2 (most substantive) — :98-106.** The POST-pool claimTreasury section:
  expectations (`costPost`, `accruedPost`) are computed 100% from contract
  getters (`costOf(1)`, `TREASURY_BPS()`) WITHOUT a single literal cross-check.
  If the post-pool price or the 15% cut were consistently wrong,
  this section would stay green. **Partial mitigation:** the pre-pool split is
  exactly literal-anchored (42,336 = 15% × 282,24; 14,112 = 5%), and the
  post-pool epoch price is tested separately in `PoolOpen.t.sol:44,125`.
  Wave-3 recommendation: pin the post-openEarly `costOf(1)` to a literal in
  the post-pool treasury test.
- **W3 (low) — :52, :83.** `totalMinted == mint.OPEN_AT()` and the
  token reserve `== mint.OPEN_TOKENS()`: comparisons to contract
  constants without literals in this file. **Mitigation:** both constants
  are literal-pinned in `Baishou.t.sol::test_BaishouParameterTargets`
  (168.000; 22.579.200.000.000 ether). The BNB reserve is instead doubled
  (:81-82: constant + literal 225,792) — the correct pattern.

### ForkDividend.t.sol
- **W4 (medium-low) — :61-68.** The claim amount is circular: `due` is read
  from `withdrawableDividendOf(alice)`, then the balance delta is asserted
  `== due`. What is proven: the claim mechanism (pays exactly the view's amount,
  zero afterwards, cannot double) — NOT the correctness of the dividend amount.
  **Mitigation:** `Dividend.t.sol::test_DividendAccruesProRata` tests
  the accumulator ratio (alice 2× bob, tolerance 10 wei, over a known deposit
  of 100 BNB) — the ratio is anchored; an absolute per-holder amount
  against a full independent calculation indeed does not exist yet (practically hard:
  ±44% of supply in the pair joins pro-rata).
- **W5 (low) — :57.** The BNB from swapTax is only asserted
  `totalDividends > 0` — with no quantitative expectation/bound whatsoever.
- **W6 (low) — :31.** Pool token reserve `== 168 * mint.POOL_SHARE()`
  — a contract constant; literal-pinned at 134.400.000 ether in Baishou.t.sol.

### Invariant.t.sol
- **W7 (low, inherent) — :94-104 + handler :42-80.** Invariant 1
  sums obligations from the contract's own mappings (`deposits` +
  `forfeitOf`): it proves solvency AGAINST the recorded obligations
  — it cannot detect systematically wrong deposit recording (e.g. always
  half). The handler also has no ghost counter and all actions are try/catch: a degenerate run (all actions revert) would pass
  vacuously. **Documented mitigation:** non-triviality was proven
  separately in wave-1 (FORK-TEST.md :110-112 — a manual drive produced
  1.246 shares + obligations of 2,09328 BNB before claims). Invariants 2-3
  compare against contract constants (TOTAL_SHARES / MAX_SUPPLY) that are
  literal-pinned in Baishou.t.sol.

**Audit conclusion:** no wave-1 assertion is wholly "fake green"
 — every main money number (282,24 / 42,336 / 14,112 /
225,792 / all refund & exit payouts) is ultimately anchored to independent literals
in the same file or in Baishou.t.sol. Weaknesses concentrate in
(a) post-pool price/accrual (W2) and (b) absolute dividend amounts (W4).

---

## 2. Multi-seed runs

Full suite = 211 tests (192 wave-1 + 7 new adversarial + base inheritance
in the new suite), 12 suites. Command: `forge test --fuzz-seed <seed>`.

| Seed | Result | Duration |
|---|---|---|
| 1 | 211 passed, 0 failed, 0 skipped | 74,84 sec |
| 42 | 211 passed, 0 failed, 0 skipped | 77,40 sec |
| 1337 | 211 passed, 0 failed, 0 skipped | 78,73 sec |
| 20261119 | 211 passed, 0 failed, 0 skipped | 86,55 sec |

Invariants raised (forge 1.9 has no `--invariant-runs` flag;
the env `FOUNDRY_INVARIANT_RUNS=512` was used, without changing foundry.toml):

| Configuration | Result |
|---|---|
| `FOUNDRY_INVARIANT_RUNS=512`, seed 777 | 3 invariants PASS — **runs: 512, calls: 256.000, reverts: 0** |

No seed-dependent failures.

---

## 3. New adversarial tests — `test/Adversarial.t.sol` (7 tests)

This file's focus = gaps that are REALLY not covered yet: reentrancy and
the claimTreasury gates. The attacker = a `ReentrantClaimer` contract (an Agent ID
holder) whose receive() fires one low-level callback
and records the result; the asserted mandate: reentrant calls always
FAIL (`reentrySuccesses == 0`) and the outer payout is EXACTLY its entitlement, once.

| Test | Scenario | Result |
|---|---|---|
| `test_Reentrancy_ClaimRefundPaysExactlyOnce` | reenter claimRefund mid failed-launch refund payout | PASS — received exactly 0,0168 BNB once |
| `test_Reentrancy_ClaimRefundCannotCrossIntoExit` | reenter exit(1) mid refund payout (cross attack: mintedCount not yet reduced) | PASS — total stays 100%, shares intact |
| `test_Reentrancy_ExitPaysExactlyOnce` | reenter exit(1) mid partial exit payout 5/10 | PASS — received exactly 0,00672 (80%×5), forfeit only 0,00168 |
| `test_Reentrancy_ClaimDividendPaysExactlyOnce` | reenter claimDividend (a function WITHOUT nonReentrant — protection is pure CEI) | PASS — paid exactly `due` once, withdrawable 0 |
| `test_Reentrancy_ClaimTreasuryPaysExactlyOnce` | treasury = attacker contract (separate stack, openEarly + post-pool accrual) | PASS — 0,00252 (in _open) + 0,000252 (claim) exactly; re-claim NothingOwed |
| `test_ClaimTreasuryBeforeOpenReverts` | treasury claims while the escrow is filled but the pool hasn't opened | PASS — reverts NotOpen |
| `test_ClaimTreasuryOnlyTreasury` | a non-treasury calls claimTreasury | PASS — reverts NotTreasury |

Defense note: on every path, the contract's CEI ordering (state zeroed
BEFORE the transfer) makes most reentrancy fail even before
ReentrancyGuard engages; the guard blocks the rest (including cross-function
since there is one shared guard). Defense-in-depth verified, no
extraction path beyond entitlement.

### Brief item mapping → EXISTING coverage (not duplicated)
| Item | Location |
|---|---|
| Double refund claim (2nd reverts) | `RefundFail.t.sol:29-31` (NothingOwed) |
| claimRefund before failureTime | `RefundFail.t.sol:85-90` (NotFailed); after pool open `:77-83` |
| Exit after pool open | `RefundExit.t.sol:75-81` (ExitClosed) |
| Mint while paused | `Baishou.t.sol::test_MintWhilePausedReverts`; freeMint paused `Mint.t.sol:134-140` |
| Mint past deadline / close | `Baishou.t.sol::test_SaleFailedAfterDeadline`; post-pool close `PoolOpen.t.sol:65-74` |
| freeMint 2× | `Mint.t.sol:105-121` (AlreadyGranted) |
| Cap 168/wallet / MAX_PER_TX | `Mint.t.sol:20-29` (Quota) / `:31-36` (BadShares) |
| claimReferral before pool open | `PoolOpen.t.sol:142-149`, `ForkRefund.t.sol:66-69` (NotOpen) |
| sweepUnclaimed before window / after | `RefundFail.t.sol:65-75` (NotSweepable, incl. exactly at the boundary) / `:49-63` (to DEAD exactly) |
| Pause does not block claimRefund / exit | `RefundFail.t.sol:104-113` / `RefundExit.t.sol:83-91` |
| Self-referral & referrer without Agent ID | `Mint.t.sol:60-75` (5% falls to the pool) |
| Zero-address referrer | `Mint.t.sol:49-58` (pendingBnb 85%) |
| Dividend < 0,001 BNB reverts, accrual not forfeited | `Dividend.t.sol:102-124` (DividendTooSmall + withdrawable intact) |

---

## 4. FINDINGS

**No contract findings.** Not a single actual behavior deviates
from spec/design across all wave-2 tests (adversarial + multi-seed +
512-run invariants). No test was forced green; no src/
was touched.

What exists is only test-quality notes (W1–W7 in §1) — assertion
weaknesses, not contract bugs. Two wave-3 recommendations if they are to be closed:
(1) literal-pin the post-pool price in the treasury accrual test (W2);
(2) an independent absolute dividend calculation for one holder in a controlled
scenario (W4). Both are test fixes, not contract fixes.

Remaining limitations, the same as wave-1 (outside this wave's scope):
pair/registry/WBNB are still local mocks; interactions against real PancakeSwap and
the real Agent ID registry have not been tested on a real mainnet fork.

---

## WAVE-3 ADDENDUM (19 Nov 2026) — W2 & W4 CLOSED

The only new file: `test/Wave3Pin.t.sol` (2 tests). src/ and all
old tests NOT changed. Full suite after wave-3: **225 tests green**
(211 wave-2 + 12 inherited base tests in the new suite + 2 wave-3 tests).

### W2 — CLOSED (literal pin of post-pool treasury accrual)
`test_W2_PostPoolTreasuryAccrualPinnedLiteral`: the pool is opened (helper
`_openPool`, totalMinted = 168.000), then bob mints **100 post-pool shares
(#168.001–#168.100, epoch 1)**. The price is recomputed inside the test from
spec literals only (BASE 0,00168 BNB; unit = BASE/100; epoch =
(n−168.001)/16.800+1; units = min(100+2·epoch, 200)) — the contract's `costOf`
is not used for expectations. Pins that passed exactly:
- Cost of 100 epoch-1 shares (0,0017136 BNB/share) = **0,17136 BNB**;
  bob's balance decreased by exactly that (refund 0, maxCost = the spec number).
- `claimTreasury` pays **0,025704 BNB** — exactly 15% × 0,17136,
  computed per share with per-share floor as per spec.
- The second claim reverts `NothingOwed`. The initial anchor is also literal: the cut
  of the trigger mint at `_open` = 0,000252 BNB (1 × 0,00168 × 15%).

### W4 — CLOSED (absolute pin of the dividend amount, independent)
`test_W4_DividendClaimMatchesIndependentComputation`: a fully controlled scenario
from setup literals — alice mints 168 shares + `openEarly`; bob buys
10 billion tokens (gross) paying 10 BNB WBNB (2% buy tax = 200M tokens
to the minter); `swapTax` flushed until the tax is exhausted; bob sells 5 billion tokens
(1% burn = 50M to DEAD, 1% kept = 50M to the minter, takes 1 BNB out);
second flush. The expectation is computed by a **shadow model** inside the test
(pair reserves, tax balance, totalSupply, and mdps maintained from the setup
numbers + the AMM `amountOut` formula with a 30 bps fee + the accumulator formula
`(D × 2^128)/totalSupply` per deposit) — `withdrawableDividendOf` is not
used for expectations. Pins that passed with **exactly 0 wei tolerance**:
- Alice's claim = **102_951_825_930_676_097 wei
  (0,102951825930676097 BNB)**, equal to
  floor(28_224_000_000 tokens × shadow mdps / 2^128), and also pinned
  as a hard literal in the test.
- Model validation: the contract's `totalDividends` == shadow total deposits.
- Pair pro-rata covered: the accumulator denominator is the full totalSupply
  (the pair holds ±35% of supply in this scenario) — not circulating supply.

A model correction found during the work (not a contract finding):
the test's initial assumption that the sell tax "burn" lowers totalSupply was WRONG —
in `AgentToken` a burn is a transfer to DEAD, the tokens stay in
totalSupply, keep joining pro-rata dividends (and are never claimed).
The contract's behavior is consistent with its design; the test model was fixed.
With this, both wave-3 recommendations in §4 are done: **W2 and W4 closed,
zero contract findings in wave-3.**
