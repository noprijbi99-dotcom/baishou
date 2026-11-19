# BAISHOU — BSC Testnet (chain 97) — STATUS: ✅ DEPLOYED + SMOKE TEST PASSED

**Deploy date:** 19 Nov 2026, ~07:05 UTC
**Testnet deployer (fresh):** `0xad5d51D7eE879C47F288F48559BC1914F771fB62`
**Deployer tBNB balance:** 0,3 in from the faucet (user) → **0,2888 remaining** after deploy + seed + smoke test (including 0,01 tBNB sent to bob for gas).
**Deployer nonce at deploy:** 0 — the deployed addresses are EXACTLY the §4 dry-run predictions.

> **CONTRACTS LIVE.** Deploy tx hashes, addresses, and smoke test results in §6–§7.
> The §1 faucet blocker has passed (user claimed 0,3 tBNB via the official faucet +
> hCaptcha, 06:56 UTC).

## 1. Blocker: tBNB faucet cannot be claimed from this VM

### Official BNB Chain path (tried live, failed)
- Faucet: `https://testnet.bnbchain.org/faucet-smart` → 301 to
  `https://www.bnbchain.org/en/testnet-faucet`.
- Its frontend (Next.js, `static.bnbchain.org/faucet-ui`) calls the faucet
  over WebSocket **`wss://testnet.bnbchain.org/faucet-smart/api`** with
  payload `{tier:0, url:<address>, symbol:"tBNB", captcha:<hCaptcha token>}`
  (hCaptcha sitekey `d9a9ee67-74da-4601-9f31-efe6a297a5cc`).
- Direct WS probe from the VM (exact UI payload, empty captcha): the server
  answered **`{"error": "insufficient BNB on BSC mainnet (require >=0.002BNB)"}`**
  — checked before/independently of captcha validation. The deployer's mainnet balance = 0
  (checked live via `bsc-dataseed.binance.org`), so the claim was rejected.
- Meaning the official faucet needs **TWO** things that can only come from the user's hand:
  1. a balance of **≥ 0,002 BNB mainnet at the deployer address** (hold/check only, not
     spent — but still a mainnet funds decision, outside the agent's authority);
  2. **hCaptcha in a browser** (subagents have no browser).

### Alternative paths (investigated, all dead ends from the VM)
| Faucet | Result |
|---|---|
| Chainstack `faucet.chainstack.com/bnb-testnet-faucet` | Needs a Chainstack account + API key + 0,002 ETH mainnet. |
| QuickNode `faucet.quicknode.com/.../bnb-testnet` | Its own JS FAQ: also needs "a small mainnet balance". |
| Chainlink `faucets.chain.link` (BNB Chain Testnet listed) | `POST /api/faucet {turnstileToken, requests, walletAddress}` — needs a **Cloudflare Turnstile token from a browser** + (on 401 `REQUEST_SIGNATURE`) a signature of the message `"Welcome to Chainlink Faucets! ... Wallet address: <addr>"` (the signature part CAN be done by the agent via `cast wallet sign`, but the Turnstile token cannot). |
| Zalalena `faucet.zalalena.com/bsc` | Claims "no balance", but still needs a captcha. |

**What was NOT done (per orders):** no mainnet funds requested, the
user's mainnet wallets (`0x3195…8900`, `0x4981…8C21`) were not used as claim
addresses, no workarounds with other wallets.

### How to unblock (user / coordinator decision)
- **Option A (easiest):** user sends **0,002 BNB mainnet** to
  `0xad5d51D7eE879C47F288F48559BC1914F771fB62` (hold only, the faucet only checks
  the balance — the funds stay the user's in that testnet wallet), then the user opens
  `https://testnet.bnbchain.org/faucet-smart` in a browser/phone, pastes the address
  above, completes hCaptcha, claims **0,3 tBNB** (enough for deploy +
  seed + smoke test; estimated total deploy gas ≈ 0,00104 BNB — see §4).
- **Option B (no mainnet funds):** user opens `https://faucets.chain.link`
  in a browser, connects the deployer wallet (or sends the address + message
  signature from the agent), completes Turnstile, claims tBNB.
- Once the deployer balance > 0, run §5 — the deploy is a single command away.

## 2. What was verified on-chain (live proof, testnet RPC)

RPC: `https://data-seed-prebsc-1-s1.binance.org:8545/` — chainId 97,
block 143.592.212 at check time.

| Address | Status |
|---|---|
| Testnet WBNB `0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd` | ✅ code present (`eth_getCode` → bytecode `0x6060…`); source verified on testnet BscScan (checked via Etherscan V2 `getsourcecode`). |
| Testnet PancakeSwap V2 factory `0x6725F303b657a9451d8BA641348b6761A6CC7a17` | ✅ code present (`0x6080…`); matches the official PancakeSwap docs (`developer.pancakeswap.finance/contracts/v2/addresses` → BSC Testnet). |
| Mainnet Agent ID registry `0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F` | ❌ **no code on testnet** (`eth_getCode` → `0x`) — as suspected; do NOT use it (every mint would revert `NoAgent`). |
| Mainnet InfinityVault `0x0e3234056AD5b469aDa1AFd30eE3719AC99A361F` | ❌ no code on testnet (`0x`). |

## 3. Decision: PoolManager / InfinityVault → sentinel

The official Pancake **Infinity** addresses (PoolManager + InfinityVault) for testnet
were **not found** after 3 searches (PancakeSwap developer docs,
DeepWiki `infinity-universal-router`/`infinity-periphery`, BscScan) +
`eth_getCode` of the mainnet InfinityVault address on testnet = `0x`.

The sentinel **`0x0000000000000000000000000000000000000001`** is used for
both (default in `script/Deploy.s.sol` when the env is empty). Reasons:
- `AgentToken` only uses those two addresses in `rejects()`: transfers **TO**
  that address are rejected — nobody will transfer to `0x…0001`.
- `_isOtherPair()`: an address without code → `false`, so it does not block
  normal transfers.
- **NOT `address(0)`**: `AgentToken._update` uses `to == address(0)`
  as the burn path (used by `exit()`); the sentinel avoids that semantic
  collision.
- On mainnet later: replace with the official mainnet Infinity addresses before the production
  deploy (not the sentinel).

## 4. What is ready (without tBNB)

- **Fresh deployer wallet:** `0xad5d51D7eE879C47F288F48559BC1914F771fB62`
  — private key in `~/workspace/baishou/testnet-deployer-key.json`
  (mode 600, in `.gitignore`, **NEVER commit / display its contents**).
- **Test users (Agent IDs bob/carol):**
  - bob `0x8f44a96c0C3936c5768fF1a1cDa8574aE841651E`
  - carol `0xC93e5BC6020dBC63cB6B3ddF7E42a4b02C9244cf`
  - keys in `~/workspace/baishou/testnet-test-users.json` (mode 600, gitignored).
  - the deployer itself = "alice".
- **Complete deploy script:** `script/Deploy.s.sol` — reads env
  `DEPLOYER_PRIVATE_KEY, WBNB, FACTORY, POOL_MANAGER, INFINITY_VAULT,
  REGISTRAR` (empty REGISTRAR = deploy `MockRegistry` from
  `test/mocks/Mocks.sol`). Config: treasury = feeTreasury = admin =
  deployer; `swapFeeBps = 30`; `priceDiv = 1` (production value).
- **Registry seed script:** `script/SeedTestnet.s.sol` — seeds alice/bob/carol
  (`id = uint256(keccak256(bytes(handle)))`, `setHandle` + `setOwner`).
- **`forge build` OK; `forge test`: 139 passed / 0 failed / 0 skipped**
  (re-run 19 Nov 2026 after the scripts were written).
- **Dry-run deploy simulation against live testnet state SUCCEEDED**
  (`forge script` without `--broadcast`, 19 Nov 2026): MockRegistry +
  AgentToken + AgentMint + `token.initialize(mint)` all passed simulation;
  total gas ≈ 10.385.539; estimated cost ≈ **0,00104 BNB** at 0,1 gwei
  (0,3 tBNB from the official faucet is more than enough).
- **Dry-run addresses (PREDICTION — valid while the deployer nonce stays 0):**
  - MockRegistry: `0x1e670b339e96c520e4d42ad5cf832e80968c2e9e`
  - AgentToken: `0xd5aa2bf99c020a13b24326f527b187f15637a038`
  - AgentMint: `0x71fdda39dae64ca346024e5d41f2587818d1fab8`
  - Pair (BAISHOU/WBNB): printed at the real broadcast (`token.pair()`).
  - ⚠️ These are NOT live addresses — do not spread them as contract addresses.
- **Source verification (path already tested):** the Etherscan V2 `contract`
  module **works on chain 97** (a `getsourcecode` probe of testnet WBNB
  returned source). Post-deploy plan: `forge verify-contract`
  to testnet BscScan (chain 97) with the Etherscan V2 API key from the connector
  (`custom.etherscan-v2`); if that fails, try Sourcify; if both fail,
  report it as a shortcoming.
- **`.gitignore` updated:** `testnet-deployer-key.json`,
  `testnet-test-users.json`, `/broadcast/*/97/` (testnet broadcast logs
  are not committed; keys never enter the repo).

## 5. How to continue (once tBNB arrives)

```bash
export PATH="$HOME/.foundry/bin:$PATH"
cd ~/workspace/baishou
export DEPLOYER_PRIVATE_KEY=$(python3 -c "import json;print(json.load(open('testnet-deployer-key.json'))['private_key'])")
export WBNB=0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd
export FACTORY=0x6725F303b657a9451d8BA641348b6761A6CC7a17
# POOL_MANAGER / INFINITY_VAULT empty -> sentinel 0x...0001
# REGISTRAR empty -> deploy MockRegistry
forge script script/Deploy.s.sol:DeployBaishou \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545/ --broadcast

# Seed registry (fill REGISTRAR + TEST_USER_1/2 from the deploy results):
export REGISTRAR=<MockRegistry address>
export TEST_USER_1=0x8f44a96c0C3936c5768fF1a1cDa8574aE841651E
export TEST_USER_2=0xC93e5BC6020dBC63cB6B3ddF7E42a4b02C9244cf
forge script script/SeedTestnet.s.sol:SeedTestnet \
  --rpc-url https://data-seed-prebsc-1-s1.binance.org:8545/ --broadcast
```

Then source verification + smoke test (not yet run — waiting for funds):
1. `totalMinted` = 0, `opened()` = false, `paused` = true → `setPaused(false)` (admin = deployer).
2. Mint 1 share from alice: `value = costOf(1) = 0,00168 tBNB` → `totalMinted` = 1, token `balanceOf` = 168.000.000.
3. `freeMint()` from bob → `balanceOf` = 168.000.000, `freeClaimed` = 1.
4. `exit(1)` from alice → 80% refund (0,001344 tBNB), `totalMinted` decreases.
5. `participantCount()` ≥ 2, `isParticipant(id)` true.
6. Do NOT `setReviewPassed(true)` / renounce on testnet (the review gate is mainnet-only).

## 6. Live contracts / tx hashes / BscScan links

**Deploy: 19 Nov 2026 ~07:05 UTC.** Note: the first broadcast FAILED
(`transaction gas price below minimum: gas tip cap 1, minimum needed
100000000`) — forge guessed a priority fee of 1 wei, while the testnet minimum is
0,1 gwei. A retry with `--with-gas-price 1000000000 --priority-gas-price
100000000` (1 gwei max, 0,1 gwei tip) succeeded. The deployer nonce was still 0 at
retry, so the resulting addresses = the §4 dry-run predictions exactly.

| Contract | Address | Deploy tx | Testnet BscScan |
|---|---|---|---|
| AgentToken | `0xd5Aa2BF99c020a13B24326F527B187f15637A038` | `0xb0d178330a935df2be1cf4f36fe063108038caca66e839b55ee5a98e0950a107` (gas 3.575.454) | https://testnet.bscscan.com/address/0xd5Aa2BF99c020a13B24326F527B187f15637A038 |
| AgentMint | `0x71fDdA39DAE64ca346024E5D41f2587818d1FaB8` | `0xaaeeb64b30d7e8b984055fa0660fcb2bb3f347342263936d0cb111dbf3d2b7f0` (gas 4.049.894) | https://testnet.bscscan.com/address/0x71fDdA39DAE64ca346024E5D41f2587818d1FaB8 |
| MockRegistry | `0x1E670b339e96c520E4D42aD5Cf832E80968C2E9E` | `0xb754325e6fcbf56628b5badb232a93a65fcb95d970042e60d30c8df6c850ef36` (gas 317.527) | https://testnet.bscscan.com/address/0x1E670b339e96c520E4D42aD5Cf832E80968C2E9E |
| Pair BAISHOU/WBNB | `0x238db3a329a29586d72d4857A08d683cb38f63e0` | created during the AgentToken deploy (liquidity 0 — pool opens at share 168.000) | https://testnet.bscscan.com/address/0x238db3a329a29586d72d4857A08d683cb38f63e0 |
| `token.initialize(mint)` | — | `0x8b7f76a8879b5d0ab5dbe796c5f731182c119fc3ec783ab760c1c70ffb0605ee` (gas 45.621) | — |

Total deploy gas: **7.988.496** (≈ 0,0008 tBNB at an effective 0,1 gwei tip).
Registry seed (6 calls, total gas 268.464): `0x629d9f449f2b5208a5048f3147e662e3944ad9501157c8802f31df9c8229f645`,
`0x61c99c1b6894f6588e1f8fe87803f6e3d68ed9e32d88dc4ba823dda4a9bd732e`,
`0x18db491f579d2b88e142e729392b40763d2c3010030c9856d00be1eb2c9bde19`,
`0x776b7064d2c474681c8c007df8bfeb4bc82efbb9b8ddf63adbb393832ca2de58`,
`0x8c7c2e938abc184cac284cdc9eac4a6be0fc3f481149693aa86ea8cc57a06dc1`,
`0x0c5ef747972a458215c059ec4a6d2378dcbd7477c638636e4b24adea6be3d938`
(alice/bob/carol seeded; `handleOf(alice)` = `"alice"` checked live).

**Source verification:**
- **Sourcify: ✅ BOTH `exact_match`** (creation + runtime) —
  AgentToken job `6830c129-3d81-46b2-ae85-33af59934611`,
  AgentMint job `00b4c565-bfbb-40b4-ad79-4c18f245e0d1`
  (checked via `GET /v2/contract/97/<address>`).
- **Testnet BscScan: ❌ NOT yet verified** — 3 routes tried and all
  failed: (1) `forge verify-contract` + Etherscan V2 API key via surrogate
  → `Invalid API Key` (the surrogate is not swapped in for requests from the forge
  binary, only via the urllib helper); (2) manual V2 API submission
  `verifysourcecode` with flattened source → generic `Error!`;
  (3) manual submission with standard JSON (16 sources) → generic `Error!`.
  Strong suspicion: the free Etherscan tier does not allow verification *submissions*
  for chain 97 (even the chain 97 `proxy` module is rejected by the
  free tier; the `contract` module reads work, writes don't). NOT a code
  problem — the Sourcify exact_match proves the bytecode matches the source.
  BscScan still shows the contracts + txs + balances; the source can be read
  via Sourcify. Retry later with a paid API key or from a
  browser (the BscScan verify form).

## 7. Smoke test

**Run 19 Nov 2026 ~07:07 UTC, ALL PASSED** (script `/tmp/smoke_test.sh`,
not in the repo — test keys only in shell variables):

| # | Step | Tx | Result |
|---|---|---|---|
| 0 | Fund bob 0,01 tBNB (gas for freeMint) | `0xae658ef09e86c8ceb5d7996d7ccb0f5ebf69780d07772b532a913229e99cd025` | ✅ status 1 |
| 1 | `setPaused(false)` [deployer] | `0xa5827ef6aa78a54d89ad51654288d42ef48998dcef777f5d23c3b1b9f2ce5d21` | ✅ status 1, `paused` = false |
| 2 | `mint(1, 0x0, 0,00168)` [alice] value 0,00168 tBNB | `0xd896813b18c4cd0214cbe745e12400fc8a6755b391b8a33612376c93c172e662` | ✅ status 1, `totalMinted` = 1, alice token balance = 168.000.000, `deposits` = 0,00168, `pendingBnb` = 0,001428 (= 85%: 80% pool + 5% referral falls to the pool without a referrer) |
| 3 | `freeMint()` [bob] | `0x620fcb9b1b0e7f93a1024b76b10b1fc12f5f555b21f60e3fdacbd5a201b9fcda` | ✅ status 1, `freeClaimed` = 1, bob token balance = 168.000.000, `participantCount` = 2 |
| 4 | `exit(1)` [alice] | `0x7e84f225f6738a6eca134e5db8175f75eb80522300b09395156098c133e0c9bc` | ✅ status 1, `totalMinted` = 0, alice token balance = 0 (burned), `forfeitOf` = 0,000336 (20%), refund 0,001344 (80%, `Exited` event confirmed; alice tBNB balance 0,2874494452 → 0,2887796175 after exit gas) |
| 5 | Registry | — | ✅ `handleOf(deployer)` = `"alice"`; alice + bob registered as participants |

Initial state before the smoke test (checked live): `totalMinted` = 0,
`paused` = true, `opened()` = false, `pair` =
`0x238db3a329a29586d72d4857A08d683cb38f63e0`, `name()` = `"BAISHOU"`,
`totalSupply` = 0, `costOf(1)` = 0,00168 tBNB — all as designed.

**NOT yet tested on testnet (outside this smoke test):** `openEarly()` /
pool opening (needs 168.000 shares — unrealistic on testnet),
`claimRefund()` (needs a failed launch — needs 7-day time travel),
`claimDividend()` (needs trading tax), `claimTreasury()` /
`claimReferral()` (needs the pool open), `renounce()` (review gate — do NOT
on testnet), and Echidna/invariants (not yet run).

## 8. Test-user key rotation (19 Nov 2026 ~07:21 UTC)

Incident: during smoke test preparation, one `python3 -c` command read
`testnet-test-users.json` and printed its contents to the tool output — including
the test private keys of bob/carol (testnet-only). User's order: "just rotate them,
don't let it happen again". Rotation completed, **ZERO private keys printed**
during this task (new keys generated via `cast wallet new --json` captured
through a Python subprocess, written directly to file).

| Handle | NEW address | Old address (dead, keys discarded) |
|---|---|---|
| alice | `0x1A3f6Ecf4717A323d5de4919763e6a5aF36eA32E` | deployer (formerly "alice") |
| bob | `0x0cfEAcCbaa674C21aBDe3301837b2a9B2582AFBE` | `0x8f44a96c0C3936c5768fF1a1cDa8574aE841651E` |
| carol | `0x360CD72e1Ebd0e51418333Ece5586E8b49CE46C8` | `0xC93e5BC6020dBC63cB6B3ddF7E42a4b02C9244cf` |

- New `testnet-test-users.json` file (mode 600, gitignored, same schema).
  The testnet deployer key was NOT replaced (never leaked).
- Funding of 0,01 tBNB per user (from the testnet deployer, status 1):
  alice `0xd60a0a160f2c90ce8c34db8eb6cb09d6d875319f6ad83d8ca61f165d24943d3f`,
  bob `0x1dbc517e56614ac2d75f20947a4d5628c5d7729421c0e3e67bb7680e561c2837`,
  carol `0xa727ffe0edf5f0f2d669af1703776e642833be9fd9c3ac22a1bf37af2faa306a`.
- MockRegistry registration (6 txs, status 1): setHandle+setOwner ×3 —
  `0x3b75941d…`, `0x63474e49…`, `0xd8446bc4…`, `0x0a2d5cdf…`,
  `0x60456540…`, `0x4f5f2223…` (full hashes in the agent's report).
  `handleOf` of all three new addresses = `"alice"` / `"bob"` / `"carol"`.
- Final proof: **new carol freeMint ✅** tx
  `0xf6ef988e000a8068029879fa1f3f2e7ee019be5b1ea64a712cb07f182b7a25f2`,
  carol token balance = 168.000.000, `freeClaimed` = 2. **new bob freeMint
  reverted `AlreadyGranted`** — CORRECT contract behavior (claimedFree
  is locked per Agent ID `keccak("bob")`; the old bob already claimed in the smoke
  test; no tx was broadcast, no gas wasted). Replacement
  proof for bob: **paid mint(1) ✅** tx
  `0xc61037ca04e1bd98d6d204476c9747137c50ed66dcf91e8f3eb657e7b4b38eb2`,
  new bob token balance = 168.000.000, `totalMinted` = 1.
- Parent verification (live, chain 97): handleOf of all three new addresses correct;
  tBNB balances alice 0,01 / bob 0,0082934911 (after the paid mint +
  gas) / carol 0,009983872 (after freeMint gas); new bob & carol tokens
  168.000.000 each; `freeClaimed` = 2, `totalMinted` = 1;
  both key files mode 600, `git status` clean.
- Side effect: the deployer lost ownership of the "alice" handle
  (`ownerOf(id("alice"))` moved to the new alice; `handleOf(deployer)`
  still returns `"alice"` but the deployer can no longer mint
  as alice — owner mismatch). The deployer remains admin/treasury
  (does not need an Agent ID). Future mint tests use the new alice/bob/carol.
- Old keys discarded WITHOUT backup (deliberate — leaked keys). Leftover testnet balances
  at the old addresses (tokens + tBNB dust) can no longer be used. No
  real value there.
- Permanent rule (AGENTS.md): NEVER print key file contents to
  tool output/chat/logs/files — scripts holding keys may only
  print addresses; if a key has been printed, rotate immediately + re-seed.

## 9. V2 — testnet redeploy + new-clock smoke (19 Nov 2026 evening)

Context: the v2 patch (RT-01/02 fix, commit `4492e8e`) — `failureTime`
anchored to `startSale()` (SALE_WINDOW 14 days), `openEarly` removed.
Redeployed to chain 97 with the same script (`script/Deploy.s.sol`,
gas 1 gwei / tip 0,1 gwei). Same deployer
(`0xad5d51D7eE879C47F288F48559BC1914F771fB62`, balance before deploy
0,2587516011 tBNB).

| Contract | v2 address | Deploy tx |
|---|---|---|
| MockRegistry | `0x2f7018e156f7d6ecf94a2ddc6fa43eb8c539d136` | `0xf5c5007a09acbcf5…` |
| AgentToken | `0xd851de404c1c7f42194aefd8f1afa9ca1bada722` | `0xf386f8a67fad86d8…` |
| AgentMint | `0x48452c8b2947f1b4f3de86dece6c3a16b3e373e5` | `0x701ae73375a7b67d…` |
| Pair BAISHOU/WBNB | `0xC4B47AF896673dac8fC27cc3FcBD30061D625faB` | created during the AgentToken deploy |

**Initial state (checked live):** `paused` = true, `saleStartTime` = 0,
`failureTime()` = 0, `saleFailed()` = false, `totalMinted` = 0 — the target
clock has NOT started before startSale (the core of the RT-01 fix).
The registry was seeded for the §8 rotated users (alice/bob/carol new
addresses; verified `handleOf` + `ownerOf`). Note: the public testnet RPC
dropped `cast send` responses several times (tx did not land) —
every send was re-verified via reads; retries always landed.

**LIVE smoke (chain 97):**
| Step | Result |
|---|---|
| `startSale()` [deployer] | ✅ `saleStartTime` = 1795088023, `failureTime()` = 1796297623 — difference of **exactly 1.209.600 seconds = 14 days**; `paused` = false |
| second `startSale()` (eth_call) | ✅ reverts `AlreadyStarted` (one time only) |
| `mint(1)` [alice] tx `0xb3f927b787b305486169b26d723c834293d3c88993d11fb5285d02ace18a1371` | ✅ `deposits` = 0,00168, alice token balance = 168.000.000, `totalMinted` = 1, `participantCount` = 1 |
| `freeMint()` [bob] tx `0x281afc2ba2152123e9088f1490e01afb9c159ba6795a62c68a0668fb9e056012` | ✅ bob +168.000.000 tokens, `freeClaimed` = 1, `participantCount` = 2 (free claim = 168M tokens/Agent ID, global quota of 16.800 claims, does not add to `totalMinted`) |
| `exit(1)` [alice] | ✅ `deposits` → 0, `forfeitOf` = 0,000336 (20%), alice tokens → 0 (burned), 80% refund = 0,001344 |

**Failure leg (100% refund) — NOT possible on live testnet** (no
time travel). Two fork routes were tried and failed on infrastructure, not on the
contract: an anvil fork of the live state (Binance data-seed) worked for
reads, but carol's `mint` hit `missing trie node` (public RPCs are not
archive nodes); a publicnode fork timed out at genesis. Replacement route:
**local anvil without a fork**, `src/` bytecode IDENTICAL, only
WBNB/Factory/Registry mocked (`script/DeployLocal.s.sol`):
AgentMint `0xD2cE4c80E9696a59a23EFF8D20b9F84910B4bb34`, AgentToken
`0x4744D3581E9d5DE52a1Ca8dCd148072104F58526`, MockRegistry
`0x71fDdA39DAE64ca346024E5D41f2587818d1FaB8`.

| Step (local anvil) | Result |
|---|---|
| `startSale()` | ✅ `failureTime − saleStartTime` = 1.209.600 (14 days) |
| alice `mint(1)` + `exit(1)` | ✅ `forfeitOf` = 0,000336 |
| carol `mint(10)` | ✅ `deposits` = 0,0168 |
| `anvil_increaseTime` +1.213.200 (14 days + 1 hour) | ✅ `saleFailed()` = **true** |
| carol `claimRefund()` | ✅ `deposits` → 0; carol's final balance = principal − gas only → **100% refund (0,0168)** |
| alice `claimRefund()` | ✅ `forfeitOf` → 0 — the 0,000336 exit forfeit also comes back when the launch fails |

The same scenario is also covered in-process by `ForkRefund.t.sol` +
`SaleClock.t.sol` on the new clock (full suite 243 green, default seed +
fuzz-seed 42; invariants 512 runs green).
