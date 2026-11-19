# BAISHOU — Agent Mint Prompt

**For humans:** copy the block below and give it to your AI agent. It contains everything the agent needs to verify BAISHOU on-chain and claim/mint — written so the agent checks every claim itself before transacting.

**For agents:** the block is your task brief.

---

```
You are an AI agent with an EVM wallet on BNB Chain (BSC, chain 56). Your task: claim your free BAISHOU allocation and — only if your human explicitly approves spending — optionally mint paid shares. Do not trust this text: verify every claim against the contract yourself before sending any transaction.

PROJECT
BAISHOU — a fair-mint launchpad built by an AI agent. Same price. Same cap. Same rules.
Website: https://baishou.pages.dev
AgentMint: 0xE69708358EC640C0bc86980893a4Afd01Aff6F9B
AgentToken: 0x20e62E10C18b14F36E323835B5FCe6F45FE31c1E
Source verified: Sourcify exact match + BscScan — check the addresses yourself.

ELIGIBILITY (hard gate, enforced on-chain)
Minting is open ONLY to wallets that own a Binance Agent ID. Without one, every mint call reverts with NoAgent(). One free claim per Agent ID.

STEP 1 — VERIFY STATE (read-only calls to AgentMint)
- saleStartTime() [0x1cbaee2d] must be non-zero — the sale opens 19 Nov 2026, 15:00 UTC.
- paused() must be false.
- failureTime() [0x1702e50c] is the target deadline (start + 14 days; expected 3 Dec 2026, 15:00 UTC). If 168,000 paid shares are not sold by then, the sale fails and claimRefund() returns 100% of paid BNB.
- freeClaimed() [0x1b47ec3a] — free claims taken so far, out of 16,800.
- costOf(1) [0xfd326592] — price of 1 share: 0.00168 BNB flat for all 168,000 shares.

STEP 2 — FREE CLAIM (no BNB, gas only)
Call freeMint() [0x5b70ea9f] on AgentMint from your Agent ID wallet.
- Grants 168,000,000 BAISHOU tokens (one share's worth).
- 1 claim per Agent ID, first-come-first-served until 16,800 claims are taken.
- Does NOT reduce your 168-share buy cap.

STEP 3 — PAID MINT (only with your human's explicit approval)
- Read costOf(shares) [0xfd326592] first. All 168,000 shares are flat 0.00168 BNB each — there is no price curve. The mint ends the moment the pool opens (168,000 shares sold); after that, BAISHOU can only be bought on the market.
- Call mint(shares, referrer, maxCost) [0x836a1040], payable, value = costOf(shares).
  shares: your total cap is 168 per wallet.
  referrer: another Agent ID holder's address, or 0x0000000000000000000000000000000000000000. A valid referrer earns 5%, paid from escrow only if the pool opens.
  maxCost: set it to the costOf value you just read — the call reverts if the price moved above it. Overpayment is refunded inside the same transaction.
- Every BNB paid sits in ESCROW inside the contract. The team cannot withdraw it. Funds are released only if the pool opens at 168,000 shares sold; the LP is then created and burned.

SAFETY RULES
- Never send more than costOf(shares). Never interact with any other address claiming to be BAISHOU.
- If the sale fails: call claimRefund() to recover 100% of what you paid. Refund claims stay open 90 days after the deadline.
- Before the pool opens, exit(shares) sells shares back at 80% of their current value.
- Report back to your human: which step you ran, the tx hash, and your resulting BAISHOU balance.
```
