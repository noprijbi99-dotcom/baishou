# BAISHOU — FAQ

Short answers. Full design: [WHITEPAPER.md](WHITEPAPER.md).

**What is BAISHOU?**
A fair-mint launchpad on BSC, run by an AI agent (nosa.ai) under a human's
direction. You mint *shares*; every share carries a fixed 168,000,000
BAISHOU tokens. Same price, same cap, same rules — for everyone.

**Who can mint?**
Only holders of a **Binance Agent ID** — for the entire sale, in every
phase. The contract checks your Agent ID. Regular wallets can't mint, but
anyone can buy on the BAISHOU/WBNB market after the pool opens.

**How do I mint?**
1. Open https://baishou.pages.dev and connect the wallet that holds your
   Agent ID.
2. Choose how many shares you want (max 168 per wallet).
3. Confirm the transaction. Your BNB stays in escrow inside the contract
   until the target resolves.

**How much is a share?**
The first 168,000 shares cost a flat **0.00168 BNB** each. After the pool
opens, the price rises +2% per 16,800 shares sold, capped at
**0.00336 BNB**. The tokens per share never change: always 168,000,000.

**Is there a free claim?**
Yes — **16,800 shares are free**, one free allocation per Agent ID,
first-come, first-served while they last.

**What happens at 168,000 shares?**
The pool opens: at least **225.792 BNB** and **22,579,200,000,000 tokens**
seed the BAISHOU/WBNB pair, the LP is burned, and the escrowed treasury
(15%) and referral (5%) shares are paid out. The mint then stays open for
7 more days at the rising curve price.

**What if the target is missed?**
The sale has 14 days from its start (opens 19 Nov 2026, 15:00 UTC;
deadline 3 Dec 2026, 15:00 UTC). If 168,000 shares aren't sold by then,
call `claimRefund()` and get **100% of your BNB back**. You have 90 days
to claim; unclaimed amounts are burned afterwards. The team gets nothing
from a failed sale.

**Can I get out before the pool opens?**
Yes — `exit()` returns **80%** of your BNB immediately. If the sale later
fails anyway, `claimRefund()` tops you back up to 100% of everything you
paid.

**What does the referral link do?**
If you mint through someone's referral link, they earn a flat **5%** in
BNB, paid from escrow when the pool opens. It changes nothing for you:
same price, same 168-share cap. Build your own link (with your wallet
address) in the Invite section of the website.

**Is there a team allocation?**
No. Zero tokens are pre-minted to the team. The project's only income is
the 15% treasury share of sale proceeds — paid only if the pool opens.

**What's the tax?**
2% on buys and 2% on sells: 1% is burned to the DEAD address, 1% goes to
holder dividends. Dividend amounts are small by construction — it's a
mechanism, not an income promise.

**What's the max supply?**
510,854,400,000,000 BAISHOU — a hard cap enforced by the contract on
every mint.

**Can the admin take the escrowed money?**
No. There is no admin withdraw function. The admin can pause the mint,
start the sale once, and claim the treasury after the pool opens — and
nothing else. Pause never blocks refunds or exits.

**Where can I verify all this?**
Contracts (BSC mainnet): AgentToken
`0x20e62E10C18b14F36E323835B5FCe6F45FE31c1E`, AgentMint
`0xE69708358EC640C0bc86980893a4Afd01Aff6F9B` — source verified on Sourcify
(exact match) and BscScan. Code and tests:
https://github.com/noprijbi99-dotcom/baishou
