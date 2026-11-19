# BAISHOU — BSC Mainnet (chain 56) — STATUS: ✅ MAINNET LIVE — MINT STAYS CLOSED (paused=true)

**User's order:** 19 Nov 2026 07:10 UTC — "just deploy all the contracts
but don't open the mint yet". **Mint STAYS CLOSED** (paused=true is the
initial state; the script does NOT call setPaused(false) / openEarly /
mint / seed).
**Deploy completed 19 Nov 2026 ~07:36 UTC — see §7. The parent's green
light was given; the broadcast succeeded.**

## 0. Funding blocker — RESOLVED (path b, user's choice 07:23 UTC)

**Deployer funding was BLOCKED by Binance's risk engine (~07:17 UTC):**
`baw wallet send` → `{"code": 351703, ... "recipient address is not in your
address book..."}` — sending 0,006103075125 BNB to the deployer failed, no
funds moved. **Solution used: path (b)** — user: "just move it over":
moved 0,0025 BNB from `0xad5d…` (testnet deployer — its mainnet balance
was 0,0025 BNB, a faucet requirement) to the mainnet deployer `0x3730…` —
tx `0xe41a687b883e3cc9cb310f052e2476da97b4c83bf7afbe7ee96b308859cb33fa`
status 1, block 134.462.747. The mainnet deployer now holds 0,0024979 BNB,
nonce 0, address predictions still valid; low broadcast gas at 0,1 gwei.

## 1. Predicted addresses (dry-run against live mainnet state, deployer nonce 0)

Two independent dry-runs gave the SAME predicted addresses:

| Contract | Predicted address |
|---|---|
| AgentToken | `0x42c40Bf7E152315d947484d37CC6d0E74d29cD88` |
| Pair BAISHOU/WBNB | `0x339b0e7cC4B6dBCe18E63632Ab379F76F9aE5F73` |
| AgentMint | `0x6cA8489C75641bdf7a0A2Af1Eee4375f52a51F00` |
| Deployer (new mainnet key) | `0x3730f81E6f311ab40222da1393e07Af6F68AffB5` |

⚠️ These are PREDICTIONS — valid as long as the deployer nonce stays 0. Not live addresses.

## 2. Constructor args (complete)

**AgentToken** — `new AgentToken("BAISHOU", "BAISHOU", wbnb, factory,
poolManager, infinityVault)`:
- name = `"BAISHOU"`, symbol = `"BAISHOU"`
- wbnb = `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`
- factory = `0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73`
- poolManager = `0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b`
- infinityVault = `0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F`

**AgentMint** — `new AgentMint(Config{...})`:
- token = the deployed AgentToken address (above)
- registrar = `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`
- treasury = `0x319581821414b324Dd5Db9795e42E7ee3A287900` (user's main wallet)
- feeTreasury = `0x319581821414b324Dd5Db9795e42E7ee3A287900`
- admin = `0x319581821414b324Dd5Db9795e42E7ee3A287900`
- wbnb = `0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`
- swapFeeBps = 30
- unblockable = [] (empty)
- priceDiv = 1

Contract constants (from source, tested): TOTAL_SHARES 1.680.000,
MAX_SUPPLY 510.854.400.000.000 ether, OPEN_AT 168.000, PROD_BASE_PRICE
0,00168 ether, PROD_OPEN_BNB 225,792 ether, TREASURY_BPS 1500,
REFERRAL_BPS 500, MINT_PRICE_BPS 10000, BASE_PER_ID 168, MAX_PER_TX 168,
FREE_SHARES 16.800, EPOCH_SHARES 16.800.

## 3. Proof that every mainnet address is verified (chain 56, block 134.461.092)

| Address | Proof |
|---|---|
| Registrar `0x60B9…022F` | `eth_getCode` → bytecode `0x6080…`; functional: `balanceOf(0x3195…8900)` = 1, `handleOf(0x3195…8900)` = `"nosa"` — the official Agent ID registry with the user's ID registered |
| WBNB `0xbb4C…095c` | `eth_getCode` → code; `symbol()` = `"WBNB"` |
| Factory `0xcA14…0c73` | `eth_getCode` → code; `allPairsLength()` = 3.729.190; address from the official PancakeSwap docs (developer.pancakeswap.finance/contracts/v2/addresses) + Bitquery. NOTE: the correct address ends in `…0c73` — writing `…0c6` (39 digits) is a typo and is rejected by cast |
| PoolManager `0xa0Ff…058b` | `eth_getCode` → code; functional: `protocolFeeController()` = `0x74Aa9b14049Eccf0eE2183818658B84df427Cb5C`; source verified on Etherscan V2: `src/pool-cl/CLPoolManager.sol`, "Copyright (C) 2024 PancakeSwap"; two independent sources (Bitquery Infinity API + defiformal research) name this address as the BSC CL pool manager |
| InfinityVault `0x0e32…361F` | `eth_getCode` → code; source verified on Etherscan V2: `contract InfinityVault is` (BscScan: "InfinityVault", Exact Match) |

The `DeployMainnet.s.sol` script also has layered defense: it `require`s
code-length > 0 for all five addresses above BEFORE broadcasting — if even
one is empty, the deploy reverts with no half-finished broadcast. The
`0x…0001` sentinel is NOT used on mainnet. MockRegistry is NOT deployed.

## 4. Script + tests + dry-runs

- New script: `script/DeployMainnet.s.sol` (not the testnet `Deploy.s.sol` —
  the old script hardcodes roles = deployer + deploys MockRegistry if the
  registrar is empty; running it on mainnet would lock the treasury to a
  throwaway wallet. FORBIDDEN on mainnet).
- `forge build` OK. **`forge test`: 139 passed, 0 failed, 0 skipped**
  (7 suites, 19 Nov 2026).
- Dry-run 1 (1,2x multiplier): total gas 10.730.681, predicted addresses =
  §1. Dry-run 2 (no multiplier): total gas 11.624.905, predicted addresses
  THE SAME. Forge gas estimates vary ±10% between runs; the highest figure
  was used for funding. Reference: actual testnet 7.988.496 gas
  (including MockRegistry 317.527).
- Gas price at dry-run: `eth_gasPrice` = 0,05 gwei.

## 5. Deployer funding (math + status)

- Deployer: `0x3730f81E6f311ab40222da1393e07Af6F68AffB5` — NEW mainnet key
  (`cast wallet new --json`), file `mainnet-deployer-key.json` mode 600,
  gitignored, its contents NEVER printed. The deployer holds NO role
  whatsoever (treasury/feeTreasury/admin = the user's main wallet).
- Funding math: highest gas 11.624.905 × 0,5 gwei (10× the going rate of
  0,05 gwei — headroom so the broadcast is not underpriced) =
  0,0058124525 BNB × 1,05 buffer = **0,006103075125 BNB**.
- Main wallet balance at calculation time: 0,010306309470965425 BNB (checked
  live via cast). Main wallet remainder after sending: ≈ 0,004203234345965425 BNB
  (excluding baw's own send gas, ~21.000 gas).
- **Status: SENT via path (b) — see §0.** The mainnet deployer was funded
  with 0,0024979 BNB (from 0xad5d…, tx `0xe41a68…33fa`). The actual broadcast
  cost was 0,0004469663 BNB (gas 8.910.142 @ ~0,05 gwei effective —
  far below the 0,00116 BNB estimate @ 0,1 gwei); **the deployer remainder
  of 0,0020509337 BNB is LEFT IN PLACE (user 07:25 UTC: "don't sweep it back
  right away, just leave it for now") — do NOT sweep back until the user says so.**
- Broadcast plan (AFTER the parent's green light): `forge script
  script/DeployMainnet.s.sol:DeployBaishouMainnet --rpc-url
  https://bsc-dataseed.binance.org/ --broadcast --with-gas-price
  500000000` (0,5 gwei max fee), then `token.initialize(mint)` is already
  included in the script. Verify the source on mainnet BscScan + Sourcify, then
  read state: paused MUST be true, totalMinted 0, name BAISHOU, costOf(1)
  0,00168 BNB, treasury/admin = main wallet.

## 6. Still missing before the mint opens (after deploy)

1. Source verification on mainnet BscScan + Sourcify.
2. Read live state (paused/totalMinted/treasury/admin).
3. Echidna/formal invariants — not yet run.
4. Square community forensic audit + independent review — the
   `reviewPassed` gate exists; `renounce()` is locked until the review passes.
5. Open the mint — needs the user's own word (this deploy does NOT open the mint).

## 7. ✅ MAINNET LIVE — deploy completed 19 Nov 2026 ~07:36 UTC

**Broadcast:** `forge script script/DeployMainnet.s.sol:DeployBaishouMainnet
--rpc-url https://bsc-dataseed.binance.org/ --broadcast --with-gas-price
100000000 --priority-gas-price 50000000 --start-fresh`, inside `script`
(recorded — see §8). The first two attempts FAILED before any tx was
sent (nonce stayed 0, predicted addresses unchanged):
1. a 0,01 gwei tip was rejected by the network ("gas tip cap 10000000, minimum needed
   50000000") — fixed to a 0,05 gwei tip;
2. forge refused because the previous run had not finished ("unfinished
   operations") — fixed with `--start-fresh` (failed run archived).
Third attempt: **ONCHAIN EXECUTION COMPLETE & SUCCESSFUL.**

Key file note: `mainnet-deployer-key.json` turned out to be in the baw envelope
format (`{success, data: [{address, public_key, private_key}]}`), NOT
`{private_key}` like the testnet file — the first dry-run failed with
`KeyError: 'private_key'`. The correct path:
`json.load(...)['data'][0]['private_key']`. The address from the key was verified
to match the deployer `0x3730…AffB5` before broadcasting. The key was NEVER
printed (only the address was shown).

| Contract | Address (ACTUAL = §1 prediction exactly) | Tx | Gas |
|---|---|---|---|
| AgentToken | `0x42c40Bf7E152315d947484d37CC6d0E74d29cD88` | `0x6b788a4b63e3c53b8c817c440ee66c5cb9a487abfbb4a9817af11c81744d864b` | 4.821.292 |
| AgentMint | `0x6cA8489C75641bdf7a0A2Af1Eee4375f52a51F00` | `0x4d5b4c0fb1e494999579c948cb0d3906fb3002a7dc2c08984bf00eafbdba7171` | 4.043.241 |
| Pair BAISHOU/WBNB | `0x339b0e7cC4B6dBCe18E63632Ab379F76F9aE5F73` | created during the AgentToken deploy (liquidity 0 — pool opens at share 168.000) | — |
| `token.initialize(mint)` | — | `0x7c2a64caeaadc04231d1e573d9ceeb22109c8fe8d477d0ab2dfe93ed5543882d` | 45.609 |

All 3 txs status 1, block 134.462.865. Total deploy gas: **8.910.142**
(0,0004469663 BNB @ ~0,05 gwei effective). Mainnet BscScan:
https://bscscan.com/address/0x42c40Bf7E152315d947484d37CC6d0E74d29cD88 and
https://bscscan.com/address/0x6cA8489C75641bdf7a0A2Af1Eee4375f52a51F00

**Source verification — BOTH exact_match / verified in both places:**
- **Sourcify: ✅ exact_match for BOTH** (creation + runtime) —
  AgentToken job `8d58ffe4-a174-4625-b022-8e246a5eb772` (verifiedAt
  2026-11-19T07:34:00Z), AgentMint job `7b52e748-c07f-496d-a3e4-d06296b55f41`
  (verifiedAt 2026-11-19T07:35:00Z). The first forge attempt to Sourcify
  timed out on the status query — a retry succeeded.
- **Mainnet BscScan: ✅ verified for BOTH** (read live via
  `getsourcecode`): AgentToken ContractName "AgentToken", compiler
  v0.8.28+commit.7893614a, optimizer runs 200, EVM paris, source 35.446
  characters; AgentMint ContractName "AgentMint", same compiler, source
  93.942 characters, checkverifystatus "Pass - Verified" (GUID
  `y94afrsdr4pvu4ube2pb6gwyjjvw3dzbdqwzyfvpnc1imdtyyu`). AgentToken
  was recorded as "already verified" on submit — the Sourcify exact_match
  was auto-imported by BscScan; AgentMint was submitted manually via the script
  `/tmp/bscscan_verify.py` (standard-JSON POST using the etherscan-v2 connector
  surrogate — forge cannot use the surrogate). Unlike
  testnet (chain 97 blocked on the free tier), chain 56 PASSED.

**Live state (read via cast, chain 56, block 134.463.810 — ALL AS EXPECTED):**
- code present: AgentToken 13.667 B, AgentMint 36.389 B
- `name()` = `"BAISHOU"`, `symbol()` = `"BAISHOU"`
- `pair()` = `0x339b…5F73` (as predicted), `minter()` = AgentMint
- `paused()` = **true** ✅ (mint STAYS CLOSED)
- `totalMinted()` = **0** ✅
- `costOf(1)` = 1.680.000.000.000.000 wei = **0,00168 BNB** ✅
- `treasury()` = `feeTreasury()` = `admin()` = `0x3195…8900` ✅
  (user's main wallet)
- `opened()` = **false** ✅
- Final deployer: balance **0,0020509337 BNB**, nonce 3 — **LEFT IN PLACE,
  NOT swept back** (user's order 07:25 UTC).

## 8. Broadcast recording (X video)

- Typescript: `broadcast-mainnet.typescript` (5.900 B — 3 attempts:
  tip failure, resume failure, success). The key export was done in the OUTER shell,
  not recorded.
- **Secret audit BEFORE publishing (AGENTS.md rule, user 07:28 UTC):
  CLEAN** — grep: 0 strings of 0x+64hex, 0 sensitive words
  (private_key/mnemonic/apikey/etc.); deployer key value check vs file contents:
  False/False (the key value was NEVER printed, only True/False).
  Only public addresses + txs + forge logs appear. Safe to publish.
- MP4: `broadcast-mainnet.mp4` (9,8 MB, 60 sec, 1280×720, h264 30fps) —
  ffmpeg drawtext render from the clean typescript (DejaVu Sans Mono font,
  terminal green, scrolling). Frames visually checked (t=30: deploy log +
  addresses; t=57: "ONCHAIN EXECUTION COMPLETE & SUCCESSFUL."). Two cosmetic
  defects: the "Archived ..." line is cut off at the right edge; one Braille
  spinner glyph renders as a box — neither affects the content.
- X post draft #3 (mainnet live, 209 characters) was prepared by the parent —
  do NOT post until the deploy is verified live (it is verified
  now — §7).

## 9. V2 — PRE-BROADCAST CHECKPOINT (19 Nov 2026 evening) — ✅ BROADCAST DONE, see §10

**Why v2:** red-team RT-01 — in v1 `failureTime` = deploy + 7 days
(26 Nov 2026 07:28:47 UTC); while the mint stays closed awaiting review,
that clock keeps running and v1 could expire before it ever starts (balance 0,
totalMinted 0 — no funds at risk). RT-02 — `openEarly` could
open the pool below target and break the escrow promise. The user's
decision 19 Nov 11:02 UTC: redeploy v2, target window **14 DAYS from
sale start**; all other numbers identical to v1. **v1 (§1–§8) is SUPERSEDED
by this section for the next deploy.**

### Source diff vs v1 (`git diff e0669d0..HEAD -- src/`)

- ONLY `src/AgentMint.sol` changed: **+44 / −17 lines**. `AgentToken.sol`
  byte-identical.
- `SALE_DURATION` (7 days from deploy) → `SALE_WINDOW` = 14 days +
  `POST_POOL_WINDOW` = 7 days (separate constants).
- `failureTime` immutable → **view**: `saleStartTime == 0 ? 0 :
  saleStartTime + SALE_WINDOW`. `deployTime` stays an informational
  immutable.
- New state `saleStartTime` (slot 22 — no v1 slot shifted)
  + one-time admin function `startSale()` (sets `saleStartTime` +
  unpauses atomically; reverts `AlreadyStarted` if repeated).
- `saleFailed()` = started && !opened && now > failureTime().
  `mintClosed()` is now `openedTime + POST_POOL_WINDOW`.
- **`openEarly` REMOVED entirely** (function + error `CannotOpenEarly` +
  event `EarlyOpened`). The pool only opens at `OPEN_AT` in the mint path.
- Everything else behaviorally identical: price curve, BASE_PRICE 0,00168,
  OPEN_BNB 225,792, 15/5 split, cap 168/Agent ID, free claim 16.800,
  exit 80%, refund 100%, dividends, `REFUND_WINDOW` 90 days from
  `failureTime()`.

### Verification (all parent-checkable in the repo)

- Suite: **243/243 green** on the default seed AND `--fuzz-seed 42`;
  invariants **512 runs green** (FOUNDRY_INVARIANT_RUNS=512).
- openEarly tests adapted to the REAL open path (fill of 1.000 agents):
  ForkDividend, Wave3Pin W4 (new pin exactly 2_653_293_237_882_583 wei
  via an independent shadow model), Adversarial claimTreasury
  (42,336 + 0,00025704 BNB exactly). New test `SaleClock.t.sol`:
  without startSale, warp +365 days still does not fail + mint Paused;
  the exact 14-day boundary; 100% refund on the new clock; a day-10 open
  kills failure; mintClosed at openedTime+7 days.
- Slither re-run: 76 findings (4H/8M/31L/33I) vs v1's 74 — delta +3
  (incorrect-equality sentinel `saleStartTime == 0` + timestamp ×2,
  all by-design) −1 (openEarly timestamp gone): **0 real findings**
  (SLITHER-TRIAGE.md § V2 DELTA). Patch commit: `4492e8e`.
- Testnet v2 LIVE + smoke passed (TESTNET.md §9): AgentToken
  `0xd851de404c1c7f42194aefd8f1afa9ca1bada722`, AgentMint
  `0x48452c8b2947f1b4f3de86dece6c3a16b3e373e5`, Pair
  `0xC4B47AF896673dac8fC27cc3FcBD30061D625faB` — startSale →
  failureTime exactly +14 days; mint/freeMint/exit 80% live; 100% refund
  proven on a local anvil with identical bytecode (public forks are not archive nodes).

### Predicted v2 mainnet addresses (simulation WITHOUT broadcast, 19 Nov evening)

Deployer `0x3730f81E6f311ab40222da1393e07Af6F68AffB5` — **nonce 3,
balance 0,0020509337 BNB** (checked read-only BEFORE and AFTER the simulation:
unchanged → proven no broadcast from this lane).
Gas needs: actual v1 0,0004469663 BNB → the balance covers ~4,6×.

| Contract | Predicted v2 address | Nonce |
|---|---|---|
| AgentToken | `0x155F36ff76242281c4b29689D51c197296e706a2` | 3 |
| AgentMint | `0x443eABC5567e1F4838920f74Fc6401B09f93bf53` | 4 |
| Pair BAISHOU/WBNB | `0xF5BD30CCa572F5f57eeBA508d532B432aDA3A705` | (from factory) |

Predictions from a `forge script DeployMainnet` simulation (without
`--broadcast`) and **independently matched** with
`cast compute-address` for nonce 3/4 — identical results.
⚠️ Predictions are only valid while the deployer nonce stays 3.

### Config (identical to v1)

treasury = feeTreasury = admin = `0x319581821414b324Dd5Db9795e42E7ee3A287900`;
registrar `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F`; WBNB
`0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c`; factory
`0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73`; PoolManager
`0xa0FfB9c1CE1Fe56963B0321B32E7A0302114058b`; InfinityVault
`0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F`; swapFeeBps 30; priceDiv 1.

### Broadcast checklist (for the parent)

1. Export `DEPLOYER_PRIVATE_KEY` from `mainnet-deployer-key.json`
   (`data[0].private_key`) — never print its value.
2. `forge script script/DeployMainnet.s.sol:DeployBaishouMainnet
   --rpc-url https://bsc-dataseed.binance.org/ --broadcast`
   (if the default tip is rejected like v1/testnet: add
   `--with-gas-price 1000000000 --priority-gas-price 100000000`).
   The script does NOT call startSale — the sale is born closed AND not
   started.
3. Verify live state: addresses == predictions; `paused()` = true;
   `saleStartTime()` = 0; `failureTime()` = 0; `saleFailed()` = false;
   `totalMinted()` = 0; roles == main wallet; `costOf(1)` = 0,00168.
4. Verify the source on Sourcify (the v1 path: exact_match) for both
   contracts.
5. Leave the deployer remainder in place (do not sweep without the user's word).

**CHECKPOINT STATUS: READY — broadcast HAS been done, results in §10.**

## 10. ✅ V2 MAINNET LIVE — deploy completed 19 Nov 2026 ~11:52 UTC

**Broadcast:** ONE attempt, the plain §9 step-2 command (no gas
flags — forge's 0,05 gwei tip estimate was accepted by the network this time), exit
code 0, inside `script` (recorded — see the bottom of this section). Pre-flight in
the shell outside the recording session: the key-derived address == deployer `0x3730…AffB5`,
nonce == 3 confirmed on 4 RPC endpoints, balance 0,0020509337 BNB.

| Contract | Address (ACTUAL = §9 prediction exactly) | Tx | Gas |
|---|---|---|---|
| AgentToken | `0x155F36ff76242281c4b29689D51c197296e706a2` | `0x3cac0519f660cb9e7ee6abd1e27f2d9591b505185ad36c1d6950c212c7aae1e4` | 4.843.820 |
| AgentMint | `0x443eABC5567e1F4838920f74Fc6401B09f93bf53` | `0xa30e9f6cf628e43d9d46c2b2636884970a54ab4d823ea0a1519b8bc06cb66153` | 4.037.105 |
| Pair BAISHOU/WBNB | `0xF5BD30CCa572F5f57eeBA508d532B432aDA3A705` | created during the AgentToken deploy (liquidity 0 — pool opens at share 168.000) | — |
| `token.initialize(mint)` | — | `0x753971cbeb78ff09a82b7557ca58d24c249b2b76a1cbdd6a88ad2f0e9d244690` | 45.621 |

All 3 txs status 1, block 134.498.551. Total deploy gas: **8.926.546**
(0,0004463273 BNB @ 0,05 gwei effective). Mainnet BscScan:
https://bscscan.com/address/0x155F36ff76242281c4b29689D51c197296e706a2 and
https://bscscan.com/address/0x443eABC5567e1F4838920f74Fc6401B09f93bf53
**These v2 addresses REPLACE the v1 addresses (§7) for all use.**

**Live state (read via cast, chain 56, after broadcast — ALL AS EXPECTED):**
- `name()` = `"BAISHOU"`, `symbol()` = `"BAISHOU"`, `totalSupply()` = 0
- `pair()` = `0xF5BD…A705` (as predicted), `minter()` = AgentMint,
  pair `getReserves()` = 0/0 (liquidity 0)
- `paused()` = **true** ✅ (mint STAYS CLOSED)
- `saleStartTime()` = **0** ✅ (sale NOT started — the 14-day clock is not running)
- `failureTime()` = **0** ✅, `saleFailed()` = **false** ✅
- `totalMinted()` = **0** ✅, `opened()` = **false** ✅
- `costOf(1)` = 1.680.000.000.000.000 wei = **0,00168 BNB** ✅
- `treasury()` = `feeTreasury()` = `admin()` = `0x3195…8900` ✅
  (user's main wallet)
- Final deployer: balance **0,0016046064 BNB**, nonce 6 — **LEFT IN PLACE,
  NOT swept back** (the user's order still stands).
- `startSale` was NOT called. ✅

**Source verification — BOTH exact_match / verified in both places:**
- **Sourcify: ✅ exact_match for BOTH** (creation + runtime) —
  AgentToken job `a4d0ac03-40ea-45f9-bfe4-d61a5e102d0a` (completed
  2026-11-19T11:57:10Z), AgentMint job `a475b930-8ca2-4b0e-a39b-85088347211a`
  (completed 2026-11-19T11:57:37Z).
- **Mainnet BscScan: ✅ verified for BOTH** (read live via
  `getsourcecode`): AgentToken ContractName "AgentToken", compiler
  v0.8.28+commit.7893614a, optimizer runs 200, EVM paris, source 35.446
  characters (auto-imported from Sourcify — source identical to v1);
  AgentMint ContractName "AgentMint", same compiler, source 95.432
  characters, checkverifystatus "Pass - Verified" (GUID
  `a6bizrbmnz1yxw7jgmsuh1amayhbcifdzymaecn4y35bm3wptf`). Sourcify's Etherscan
  relay for AgentMint hit the daily relay limit
  ("Daily limit of 500 source code submissions reached") → AgentMint
  was submitted manually via a standard-JSON POST script using the etherscan-v2 connector
  surrogate (the same v1 pattern; the standard input was reconstructed from
  the artifact metadata: 15 sources, optimizer 200, paris; constructor args
  of 352 bytes extracted from the deploy tx).

**v2 broadcast recording (X video):**
- Typescript: `broadcast-mainnet-v2.typescript` (2.867 B — one
  successful attempt; key export in the OUTER shell, not recorded).
- **Secret audit BEFORE publishing: CLEAN** — grep: 0 strings of 0x+64hex,
  0 sensitive words (private_key/mnemonic/apikey/secret/password/etc.);
  deployer key value check vs recording contents: False (the key value is NOT in the
  recording, only the boolean result was noted). Frames visually checked
  (t=30: deploy log + public addresses; t=57: roles + "MINT STAYS CLOSED"
  + estimates). Only public addresses + txs + forge logs appear.
- MP4: `broadcast-mainnet-v2.mp4` (4.895.173 B ≈ 4,9 MB, 60 sec,
  1280×720, h264 30fps) — ffmpeg drawtext render from the clean
  typescript (DejaVu Sans Mono font, terminal green, scrolling). Cosmetic
  defects of the v1 class: spinner glyphs render as boxes; the command header line
  is cut off at the right edge.

## 11. ✅ V3 MAINNET LIVE — deployed 19 Nov 2026 ~13:20 UTC

**Why v3:** user order 19 Nov 2026 13:12 UTC. The v2 verified source
contained one Indonesian comment line; v3 redeploys the identical logic
from the fully English-cleaned source so every public surface is
zero-Indonesian. v2 never sold a single share (paused, totalMinted 0) —
nothing to migrate. The src/ diff vs v2 is comment-only (cleanup commits
`9d18055`, `f4192de`, `1993d2c`); the compiled bytecode was verified
byte-identical to the v2 build except the metadata hash (creation +
runtime, both contracts, compared locally before broadcast).

| Contract | Address | Tx | Gas |
|---|---|---|---|
| AgentToken | `0x20e62E10C18b14F36E323835B5FCe6F45FE31c1E` | `0x17e7024b2a09ce76aae2d1c7bbf68b39743dc68d82289b151118408f5ee19314` | 4,843,820 |
| AgentMint | `0xE69708358EC640C0bc86980893a4Afd01Aff6F9B` | `0x45b2a597ac88edd3619f2964e83e85a78fe95b704c7edcd81779fc0a799c7e13` | 4,037,105 |
| Pair BAISHOU/WBNB | `0x86b5c0cD0f07d613E7c8b10E10a45BD0D858e4f6` | created inside the AgentToken deploy (0 liquidity — pool opens at 168,000 shares) | — |
| `token.initialize(mint)` | — | `0xeb28a8bb5bce043e2bd51842b8104bcaaac12075752343d02aaf6e1d4f709f03` | 45,621 |

All 3 txs status 1, block 134,510,220. Total gas: **8,926,546**
(0.0004463273 BNB @ 0.05 gwei effective) — identical to v2. BscScan:
https://bscscan.com/address/0x20e62E10C18b14F36E323835B5FCe6F45FE31c1E and
https://bscscan.com/address/0xE69708358EC640C0bc86980893a4Afd01Aff6F9B
**These v3 addresses REPLACE the v2 addresses (§10) for all uses.**

**Live state (read via cast, chain 56, after broadcast — ALL AS EXPECTED):**
- `name()` = `"BAISHOU"`, `symbol()` = `"BAISHOU"`, `totalSupply()` = 0
- `pair()` = `0x86b5…e4f6`, `minter()` = AgentMint v3
- `paused()` = **true** ✅ (mint STAYS CLOSED)
- `saleStartTime()` = **0** ✅, `failureTime()` = **0** ✅, `saleFailed()` = **false** ✅
- `totalMinted()` = **0** ✅, `opened()` = **false** ✅
- `costOf(1)` = 1,680,000,000,000,000 wei = **0.00168 BNB** ✅
- `treasury()` = `feeTreasury()` = `admin()` = `0x3195…8900` ✅ (user's main wallet)
- Deployer after: balance **0.0011582791 BNB**, nonce 9 — **LEFT PARKED,
  NOT swept** (standing user order).
- `startSale` NOT called. The opening is handled by a separate job,
  rescheduled to **19 Nov 2026 15:00 UTC**.

**Source verification — BOTH exact_match / verified in both places:**
- **Sourcify: ✅ exact_match BOTH** (creation + runtime) — AgentToken
  matchId 59523985 (job `9c5667c5-7ea4-4bb3-93d4-2b435489ad86`, verified
  2026-11-19T13:25:26Z), AgentMint matchId 59524046 (job
  `7233fc2e-88de-4cc8-9dea-605b585328fb`, verified 2026-11-19T13:26:47Z).
  The verified source is the English-cleaned source (line 7 now reads
  "FINAL NUMBERS (user, 19 Nov 06:22 UTC, shares 10x)" — zero Indonesian).
- **BscScan: ✅ Pass - Verified BOTH** via the Sourcify relay (AgentToken
  GUID `qwsrx5f7vqt6sj8hrjrwwrrra9getsdaf1mcelwwukhtripimt`, AgentMint GUID
  `krqyjnpwttljbshjaymu1n4rji12jc1xuuv6wvebzqjyvhayyr`), confirmed via
  `checkverifystatus` and a `getsourcecode` read (cleaned English source).

**Website:** https://baishou.pages.dev swapped to v3 everywhere (contract
sections, BscScan links, Board read config, countdown eth_call target);
countdown `CD_LAUNCH` = **1795100400** (19 Nov 2026 15:00 UTC — the opening
was rescheduled from 14:00 UTC); llms.txt updated to v3 with the same
transparency note. Live curl verification: HTTP 200, v3 Mint ×5 / Token ×3 /
Pair ×2, v2 addresses 0, Indonesian scan (WIB/Jakarta/Indonesia) 0,
countdown element present.

## 12. ✅ MINT OPENED — startSale() executed 19 Nov 2026 15:04 UTC

**Authorization:** user order "Gas aja bro" (19:36 WIB) for the opening,
then v3 redeploy (20:12 WIB) and opening moved to 22:00 WIB (20:13 WIB).

**Execution (Binance Agentic Wallet, `baw contract-call`):**
- Pre-flight (21:57 WIB): devMode enabled (expires 2026-11-26), `paused() = true`,
  `saleStartTime() = 0`, `failureTime() = 0`, `totalMinted() = 0`, main-wallet
  balance 0.0166 BNB.
- Preview at 22:00 WIB: requestId `e7d7ce1381a0439dab4b8c3783c50a10`,
  parsed as `startSale()` (`0xb66a0e5d`) on AgentMint v3
  `0xE69708358EC640C0bc86980893a4Afd01Aff6F9B`, simulation clean
  (`simulationCode 000000000`, no risks). Preview expiry 15:07:15 UTC.
- First execute attempt failed on a bad flag: `baw contract-call execute`
  does NOT accept `--binanceChainId` (`error: unknown option`). Nothing was
  sent; on-chain state re-checked (still `saleStartTime = 0`).
- Retry with `baw contract-call execute --requestId <id> --json`:
  status `BROADCASTED`, orderId `26111900002066661491`.

**On-chain result (verified from the receipt + fresh reads):**

| Field | Value |
|---|---|
| startSale tx | `0x045725d3995dcfb365442bd42587e41a3b42421817256c800fa295d749715ac1` |
| Block | 134524066, status 1 (success) |
| From → To | `0x319581821414b324Dd5Db9795e42E7ee3A287900` → AgentMint v3 `0xE69708358EC640C0bc86980893a4Afd01Aff6F9B` |
| Gas used | 45,933 @ 0.072473727 gwei effective = **0.0000033289 BNB** |
| `paused()` | `false` |
| `saleStartTime()` | 1795100652 = **19 November 2026, 15:04:12 UTC** (22:04:12 WIB) |
| `failureTime()` | 1796310252 = **3 December 2026, 15:04:12 UTC** (22:04:12 WIB) |
| Window | 1,209,600 s = 14 days exactly ✅ |
| `totalMinted()` | 0 |

The sale landed 4 minutes after the 15:00 UTC target (preview + the
flag-fix retry); the deadline is therefore 15:04 UTC on 3 Dec, not 15:00.
Free-claim window runs until the deadline or until all 16,800 free shares
are claimed.

**Recording:** `startsale-2200.typescript` (full session: BEFORE reads,
preview, the failed first execute, the retry, AFTER reads, closing lines).
**Video:** `startsale-2200.mp4` (67 s, 1280×720, h264 30fps) — title card 3 s
+ scrolling terminal render of the session + end card 4 s. Secret audit:
0 sensitive words; the only 64-hex strings are the public startSale tx
hash (shown twice) — public on-chain data, not a secret. Render text
contains zero WIB/Indonesian references (the one spoken "22:00 WIB" line
was rendered as "15:00 UTC" for the public cut; the raw typescript keeps
the original). Frames checked at t=1/25/50/65.

**Website + llms.txt:** artifact `baishou` edited (EN + ZH): status strip →
mint LIVE, the three TBD launch fields filled from chain values, mint state
→ Open, trust lede/note, simulator/how-to/referral notes updated; countdown
element and its JS untouched (switches to the deadline countdown from
on-chain state on its own). `llms.txt` STATUS section → LIVE with start,
deadline, tx hash and block, in UTC. Deployed via artifact export →
`baishou-pages/index.html` → `wrangler pages deploy` (project `baishou`).
Live verification: https://baishou.pages.dev (LIVE status + deadline text,
countdown present, v3 addresses, zero WIB/Indonesian text) and
https://baishou.pages.dev/llms.txt.
