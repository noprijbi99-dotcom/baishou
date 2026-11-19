# Slither Triage — BAISHOU step 2 (19 Nov 2026)

Command: `~/.venvs/slither/bin/slither . --exclude-dependencies`
(Slither 0.11.6, solc 0.8.28, Foundry 1.9.0).
Full results: `slither-2026-11-19.json` (74 findings).
Initial fork baseline: `slither-baseline-2026-11-19.json` (78 findings:
2 High, 17 Medium, 25 Low, 34 Informational).

## Summary

| Severity | Baseline | Now | Status |
|---|---|---|---|
| High | 2 | 4 | 0 real — all justified below (same pattern as baseline, now in 2 places because there is a new payment path `_payOrOwe`) |
| Medium | 17 | 7 | 0 real — 2 fixed in code (see § "Fixed"), 5 false positive / by-design |
| Low | 25 | 30 | 0 real — all by-design / vendor / false positive |
| Informational | 34 | 33 | 0 real — mostly from `src/vendor/` (OpenZeppelin) |

**The 2 baseline Highs did NOT disappear — both still exist in the same form
and are justified in writing below, per the task instruction ("gone or
justified in writing").** Both are patterns inherent to the PULL-payment design
+ `nonReentrant`, not bugs: `_pay arbitrary-send-eth` and
`_mintWithBnb reentrancy-eth`. The two "new" Highs are appearances of the
same patterns in new code (`_payOrOwe`, `_mintShares`).

## Fixed in code (before this triage)

- `divide-before-multiply` in `costOf` / `_mintShares` (old): recomputed
  as `priceUnits(n) * (BASE_PRICE / 100)` — exact because the constructor
  forces `BASE_PRICE % 100 == 0` (and `(PROD_BASE_PRICE / priceDiv) % 100 == 0`).
- `uninitialized-local` (`userT`, `Pool p` in `_mintShares`): explicit
  initialization (`= 0`, `Pool(0,0,0,0,0,0,0)`).
- `redundant-statements` (`id;`, `n;`): parameters removed/made nameless.
- `events-access` (`AgentToken.initialize`): added the `MinterInitialized` event
  + emit.
- Hardening: `_open()` now sets `openedTime` on the first line (CEI)
  before any external call.

## HIGH — justified (not bugs)

### 1. `arbitrary-send-eth` — `AgentMint._pay` and `AgentMint._payOrOwe`
Slither treats `to` as an arbitrary address. In fact `to` can ONLY
be: (a) `msg.sender` — the caller itself (overpay refund, `exit`,
`claimRefund`, `claimReferral`, `claimOwed`); or (b) `treasury` —
an `immutable` set at deploy. There is no path whatsoever where
a caller can choose another person's recipient address. Amounts are also bounded by
accounting (`deposits`, `forfeitOf`, `referralAccrued`, `escrowTreasury` —
all reduced BEFORE the `call`, checks-effects-interactions), and every
calling function uses `nonReentrant`. Switching to another pattern (e.g. paying
WBNB instead of BNB) would change the product promise (BNB refunds) without reducing
real risk. **Accepted.**

### 2. `reentrancy-eth` — `AgentMint._mintWithBnb` and `AgentMint._mintShares`
Every public entry point touching ETH uses `nonReentrant`
(OZ `ReentrancyGuard`); `_mintShares` is `private` and only called
from the already-guarded `_mintWithBnb`. External calls inside the flow
go only to trusted `immutable` contracts (WBNB, own token, pair) or to
the refund `call` at the end after all state is updated. There is no
re-entry path that can alter accounting: `mintedCount`/`totalMinted`/
`deposits`/`pendingBnb` are updated before the final `_pay`, and the guard
blocks re-calling `mint`/`exit`/`claim*` mid-execution.
**Accepted (mitigation: guard + CEI + immutable addresses).**

## MEDIUM — justified (not bugs)

### 3. `divide-before-multiply` ×2 (`costOf`, `_mintShares`)
The remaining pattern is `unit = BASE_PRICE / 100` then `priceUnits * unit`.
This division is EXACT: the constructor `revert BadConfig()` unless
`PROD_BASE_PRICE % priceDiv == 0` and `(PROD_BASE_PRICE / priceDiv) % 100 == 0`
(0,00168 ether / 1 = 1,68e15, exactly divisible by 100). No precision
loss; verified by test `test_FlatPricePrePool` (`costOf(1)` exactly
0,00168 ether, `costOf(168)` exactly 168×). **False positive.**

### 4. `incorrect-equality` ×2 (`swapTax`: `lastTaxSwapBlock == block.number`; `_swapTax`: `amount == 0`)
Both are intentional equalities, not manipulable balance comparisons: (a) a once-per-block guard for tax swaps; (b) revert if
there are no tax tokens to swap. **By-design.**

### 5. `unused-return` ×3 (`reserves`, `_swapOn`: the third `getReserves` value;
`_settle`: the return of `pair.mint`)
The reserve timestamp is indeed unused (not needed data);
the amount of LP minted to DEAD is indeed unused (LP is burned, does not
need recording). **By-design.**

## LOW — summarized (all by-design / false positive / vendor)

- `calls-loop` ×14: the `_mintShares` loop is bounded by `MAX_PER_TX = 168`
  (enforced by `_check`); the external calls in `_open`/`_payOrOwe` are inside
  a loop only per Slither's static analysis (one call per
  execution, not a user-controlled iteration). Target contracts are `immutable`.
- `timestamp` ×8: the 7-day deadline / 90-day refund window / 7-day mint close
  are indeed defined over `block.timestamp` (design §3/§10);
  validator deviation of a few seconds does not affect day-scale boundaries.
- `reentrancy-benign` ×3, `reentrancy-events` ×3: see High #2 justification;
  events are emitted after the call in `renounce`/`claimDividend`/`_swapTax` —
  state is already final before the call (`renounced`/`withdrawnDividends`/
  `lastTaxSwapBlock` are set first).
- `missing-zero-check` ×2 (`poolManager_`, `infinityVault_` in the `AgentToken`
  constructor): DELIBERATELY not checked — `address(0)` means "no
  Infinity contract" and is harmless: `rejects()` only compares
  equality, and transfers to `address(0)` are burns handled
  before the `rejects()` check.
- `return-bomb` ×1 (`_probe`): the staticcall is bounded by `PROBE_GAS = 20_000`
  and the result is validated for 32-byte length + address range. **Mitigation already in place.**

## INFORMATIONAL — summarized

- `assembly` ×16, `dead-code` ×2, `solc-version` ×4, `pragma` ×1:
  all from `src/vendor/` (OpenZeppelin, untouched) — audited OZ assembly, and pragma `^0.8.24` used alongside solc 0.8.28
  (pinned in `foundry.toml`).
- `low-level-calls` ×7: intentional `call`/`staticcall` (PULL BNB payments
  , pair probe) — see High #1 justification.
- `naming-convention` ×2: `BASE_PRICE`/`OPEN_BNB` (immutable, the AIC constant style retained).
- `cyclomatic-complexity` ×1 (`_mintShares`, 13): a single mint path that
  indeed branches pre/post-pool + escrow; splitting it further would
  obscure the escrow invariant — accepted, covered by 139 tests.

## V2 DELTA — sale-clock patch (19 Nov 2026, evening)

Re-run: `~/.venvs/slither/bin/slither . --exclude-dependencies`
(Slither 0.11.6, solc 0.8.28). Results: `slither-v2-2026-11-19.json`
(**76 findings**: 4 High, 8 Medium, 31 Low, 33 Informational) vs v1's 74
(4/7/30/33). Per-(check, function) diff against the v1 JSON:

**NEW (3):**
- `Medium incorrect-equality` — `failureTime()`: `saleStartTime == 0`.
  This is a SENTINEL test for "sale not started" (0 = not started), not
  a manipulable balance/timestamp comparison. Exact equality
  is indeed the only correct test for a sentinel. **By-design.**
- `Low timestamp` — `failureTime()` and `startSale()`: the 14-day sale window
  is indeed defined over `block.timestamp` (the core of the v2 patch);
  validator deviation of a few seconds is immaterial at day scale —
  the same justification as `timestamp` ×8 in v1. **By-design.**

**GONE (1):**
- `Low timestamp` — `openEarly`: gone together with the function (removed, RT-02).

**Unchanged:** the same 4 Highs (justifications §1–2 still apply —
no new payment/reentrancy paths; `startSale` only writes
`saleStartTime` + `paused` and touches no ETH), other Medium/Low/Info
identical per (check, function). **Net delta: 0 real findings.**

## Not yet done (for independent review)

- Slither does not replace an audit: a paid independent review is still needed
  from the treasury AFTER the pool opens (per §10 #13) before
  `renounce()` — the `reviewPassed` gate already exists in the contract.
- Echidna / formal invariant tests have not been run (outside step 2 scope).
