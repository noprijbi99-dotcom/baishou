// SPDX-License-Identifier: MIT
// *****************************************************************************
// BAISHOU — AgentMint.sol — DRAFT FORK BASE (BUKAN KONTRAK FINAL)
// Asal: $AIC AgentMint (0x55E1501815127A199314B586e59239608Ce4C15C), diverifikasi
// BscScan. Disalin sebagai titik awal fork; parameter masih AIC.
// Perubahan BAISHOU vs AIC (lihat POLA-BARU-ARUNIKA.md §3/§10):
//   - BurnMath DIHAPUS (floor 1,5x dihapus total, §10 #1) — import + call site
//     sudah dicabut di file ini; sisa dead-code burn ditandai TODO(final).
//   - TOTAL_SHARES 4.440.000 -> 168.000 | OPEN_AT 10.000 -> 16.800 share
//   - PROD_BASE_PRICE 0,002 -> 0,00168 BNB | USER_SHARE 50 jt -> 168.000
//   - POOL_SHARE 40 jt -> 134.400 | TREASURY_BPS 2.000 (20%) -> 1.500 (15%)
//   - MINT_PRICE_BPS 9.900 -> 10.000 (tepat 168.000/share; selisih 1% dihapus)
//   - INVITE_QUOTA +2 DIHAPUS | referral 5% flat dibayar SAAT pool buka (escrow)
//   - BARU (belum ada di file ini): freeMint 1.680 share, exit 80% pre-pool,
//     refund 100% PULL saat gagal, dividen holder (accumulator), Agent Registry.
// JANGAN DEPLOY file ini. Finalisasi = parameterisasi + fungsi baru + Slither
// + test penuh + review independen, sesuai skill baishou.
// *****************************************************************************
pragma solidity ^0.8.24;

import {IERC20} from "./vendor/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "./vendor/openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "./vendor/openzeppelin/utils/ReentrancyGuard.sol";
import {ECDSA} from "./vendor/openzeppelin/utils/cryptography/ECDSA.sol";
import {IPancakePair, PancakeMath} from "./interfaces/IPancake.sol";
import {AgentToken} from "./AgentToken.sol";

interface IAgentHandles {
    function ownerOf(uint256 tokenId) external view returns (address);
    function handleOf(address owner) external view returns (string memory);
}

interface IWrappedBNB {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}

/// @title AgentMint
/// @notice 铸造盘通用模板：持 Agent ID 铸造，第 10,000 份自动开池，开池后铸造按池价出币并带 80% 资金加池；
///         市值低于底线时燃烧池中代币托价（温和版：底线 1 倍、燃烧预算与投入挂钩 + 每小时限速、池中保底按流通量比例）
/// @dev 价格档位、开池流程、税费、额度、管理权限与安小将（AnXiaoJiangMint）完全一致，只改烧池三处参数
///      AIC 在模板上加了三处（详见 contracts/参数说明.md 第八节、docs/邀请返利与等级.md）：
///      1. 邀请额度：被邀请人首次付费铸造（任意份数）时，邀请人额度 +2（模板是 +1）
///      2. 邀请返利：开池后，新 Agent ID 首次铸造且单笔满 10 份，邀请人按等级拿这笔支付额的 2%–10%，
///         用 BNB 在同一笔交易里实时发放，从 20% 收款份额里扣，不动进池资金
///      3. 等级积分：每天"有效邀请数"榜前 50 名各得 1 分，由 quotaSigner 每天提交一次；积分永久累计，每 7 分升一级
contract AgentMint is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_SHARES = 4_440_000;
    uint256 public constant MAX_SUPPLY = 444_000_000_000_000 ether;
    uint256 public constant OPEN_AT = 10_000;
    /// @notice 正式版单价与开池资金；测试版按 priceDiv 同比例缩小（见 Config）
    uint256 public constant PROD_BASE_PRICE = 0.002 ether;
    uint256 public constant PROD_OPEN_BNB = 16 ether;
    uint256 public constant USER_SHARE = 50_000_000 ether;
    uint256 public constant POOL_SHARE = 40_000_000 ether;
    uint256 public constant OPEN_TOKENS = OPEN_AT * POOL_SHARE;
    uint256 public constant TREASURY_BPS = 2_000;
    uint256 public constant MINT_PRICE_BPS = 9_900;
    /// @notice 市值底线倍数（万分比）：底线 = 累计铸造额 × 1.0
    uint256 public constant FLOOR_BPS = 10_000;
    /// @notice 每份燃烧预算（万分比）：每份最多烧掉价值 = 该份支付额 × 1 倍 的池中代币
    uint256 public constant BURN_BUDGET_BPS = 10_000;
    /// @notice 全局限速窗口长度
    uint256 public constant RISE_WINDOW = 1 hours;
    /// @notice 窗口内燃烧可把池价抬到的上限：窗口起点价格 × (1 + 5%)
    uint256 public constant RISE_CAP_BPS = 500;
    /// @notice 池中代币保底：不低于流通量 × 35%
    uint256 public constant POOL_FLOOR_BPS = 3_500;
    uint256 public constant TAX_SWAP_BPS = 10;
    uint256 public constant BASE_PER_ID = 10;
    uint256 public constant MAX_PER_TX = 10;
    /// @notice 每个邀请给邀请人加的额度
    uint256 public constant INVITE_QUOTA = 2;
    /// @notice 有效邀请：被邀请人开池后首次铸造，单笔至少这么多份
    uint256 public constant REBATE_MIN_SHARES = 10;
    /// @notice 每升一级需要的积分
    uint256 public constant POINTS_PER_LEVEL = 7;
    /// @notice 最高等级（0 青铜 … 6 王者）
    uint256 public constant MAX_LEVEL = 6;
    /// @notice 每天最多给多少个 Agent ID 加分（邀请榜前 50 名）
    uint256 public constant AWARDS_PER_DAY = 50;
    /// @notice 日期按北京时间（UTC+8）切分
    /// @notice 正式版：一天 86400 秒，按北京时间（UTC+8）切分
    uint256 public constant PROD_DAY_SECONDS = 1 days;
    uint256 public constant PROD_DAY_OFFSET = 8 hours;
    /// @notice 转给邀请人时的 gas 上限；对方收款失败就记账，自己来领
    uint256 public constant REBATE_GAS = 50_000;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    bytes32 public constant TASK_FOLLOW = keccak256("FOLLOW");
    bytes32 public constant TASK_TWEET = keccak256("TWEET");
    bytes32 public constant TASK_TELEGRAM = keccak256("TELEGRAM");
    bytes32 public constant REASON_INVITE = keccak256("INVITE");
    bytes32 private constant SOCIAL_TYPEHASH =
        keccak256("Social(address user,bytes32 task,bytes32 account,uint256 deadline)");
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");

    AgentToken public immutable token;
    IPancakePair public immutable pair;
    address public immutable wbnb;
    IAgentHandles public immutable registrar;
    /// @notice 收款地址：只收钱（铸造 20%、税币兑换得到的 BNB），没有任何管理权限，可以是不签交易的冷钱包
    address public immutable treasury;
    /// @notice 手续费收款地址：交易税（买 2%、卖出留存的 1%）换成的 BNB 打到这里；铸造收入仍进 treasury。只收钱，没有管理权限
    address public immutable feeTreasury;
    /// @notice 管理地址：暂停/开放、提前开池、拉黑其他池子、放弃权限
    address public immutable admin;
    address public immutable quotaSigner;
    uint256 public immutable swapFeeBps;
    /// @notice 第 1–10,000 份的单价 = PROD_BASE_PRICE / priceDiv（正式版 priceDiv = 1，即 0.002 BNB）
    uint256 public immutable BASE_PRICE;
    /// @notice 开池注入的 BNB = PROD_OPEN_BNB / priceDiv（正式版 16 BNB）
    uint256 public immutable OPEN_BNB;
    /// @notice 积分结算的"一天"有多少秒（正式版 86400）
    uint256 public immutable DAY_SECONDS;
    /// @notice 日期切分的时区偏移（正式版 8 小时）
    uint256 public immutable DAY_OFFSET;
    bool private immutable _bnbIs0;

    uint256 public totalMinted;
    uint256 public totalPaid;
    bool public paused = true; // 部署后默认暂停，到点由管理地址 admin 调 setPaused(false) 开放
    bool public renounced;
    uint256 public pendingBnb;
    uint256 public pendingTokens;
    uint256 public openedTime;
    uint256 public lastTaxSwapBlock;

    mapping(uint256 => uint256) public mintedCount;
    mapping(uint256 => uint256) public extraQuota;
    mapping(uint256 => bool) public paidOnce;
    mapping(uint256 => mapping(bytes32 => bool)) public socialDone;
    mapping(bytes32 => uint256) public accountAgent;
    mapping(address => bool) public unblockable;

    // 新增存储放在最后，前面的槽位与安小将保持一致（extraQuota 仍在槽 8）
    // 限速窗口：起点时间 + 起点储备，打包在同一个存储槽（40 + 104 + 112 = 256 位）
    /// @notice 当前限速窗口的起点时间
    uint40 public riseWindowStart;
    /// @notice 当前限速窗口起点的池中 BNB
    uint104 public riseWindowU;
    /// @notice 当前限速窗口起点的池中代币
    uint112 public riseWindowT;

    // —— AIC：邀请返利与等级 ——
    /// @notice 每个 Agent ID 的累计积分（永久）
    mapping(uint256 => uint256) public points;
    /// @notice 某天（北京时间日序号）某个邀请人 Agent ID 的有效邀请数；加分时只能选当天有有效邀请的 ID
    mapping(uint256 => mapping(uint256 => uint256)) public invitesOn;
    /// @notice 某天是否已经结算过积分（每天只能结算一次）
    mapping(uint256 => bool) public dayAwarded;
    /// @notice 实时转账失败的返利，记在这里由邀请人自己领取
    mapping(address => uint256) public owedOf;
    uint256 public totalOwed;

    event PausedSet(bool paused);
    event Renounced();
    event Minted(address indexed minter, uint256 indexed agentTokenId, uint256 firstSerial, uint256 shares, uint256 paid);
    event QuotaGranted(address indexed user, uint256 indexed agentTokenId, uint256 extra, bytes32 reason);
    event Opened(uint256 bnbIn, uint256 tokensIn, uint256 lp);
    event EarlyOpened(uint256 shares);
    event PoolBurned(uint256 atShare, uint256 amount);
    event RiseWindowReset(uint256 start, uint256 bnbReserve, uint256 tokenReserve);
    event TaxSwapped(uint256 tokensIn, uint256 bnbOut);
    event TaxSwapFailed(bytes reason);
    event InviteRebate(
        address indexed referrer,
        uint256 indexed referrerId,
        uint256 indexed inviteeId,
        uint256 day,
        uint256 paid,
        uint256 rateBps,
        uint256 rebate,
        bool owed
    );
    event PointAwarded(uint256 indexed day, uint256 indexed agentTokenId, uint256 points);
    event DayAwarded(uint256 indexed day, uint256 count);
    event OwedClaimed(address indexed user, uint256 amount);

    error NotAdmin();
    error NotKeeper();
    error BadConfig();
    error DayNotOver();
    error AlreadyAwarded();
    error BadAward();
    error NothingOwed();
    error Paused();
    error AdminRenounced();
    error BadShares();
    error SoldOut();
    error NoAgent();
    error Quota();
    error OverMaxCost();
    error BadPayment();
    error RefundFailed();
    error PayoutFailed();
    error AlreadyGranted();
    error BadTask();
    error BadSignature();
    error NotBlockable();
    error NotOpen();
    error NothingToSwap();
    error SwappedThisBlock();
    error OnlySelf();
    error ZeroAddress();
    error CannotOpenEarly();

    struct Config {
        address token;
        address registrar;
        address treasury;
        address feeTreasury;
        address admin;
        address quotaSigner;
        address wbnb;
        uint256 swapFeeBps;
        address[] unblockable;
        /// @dev 正式版填 1；测试版填 1000 等（必须整除 0.002 ether 和 16 ether）
        uint256 priceDiv;
        /// @dev 正式版 86400 / 28800；测试版可缩短，例如 600 / 0
        uint256 daySeconds;
        uint256 dayOffset;
    }

    constructor(Config memory c) {
        if (
            c.token == address(0) || c.registrar == address(0) || c.treasury == address(0) || c.feeTreasury == address(0)
                || c.admin == address(0) || c.quotaSigner == address(0) || c.wbnb == address(0)
        ) revert ZeroAddress();
        token = AgentToken(c.token);
        if (token.wbnb() != c.wbnb) revert BadPayment();
        pair = IPancakePair(token.pair());
        wbnb = c.wbnb;
        registrar = IAgentHandles(c.registrar);
        treasury = c.treasury;
        feeTreasury = c.feeTreasury;
        admin = c.admin;
        quotaSigner = c.quotaSigner;
        swapFeeBps = c.swapFeeBps;
        if (
            c.priceDiv == 0 || PROD_BASE_PRICE % c.priceDiv != 0 || PROD_OPEN_BNB % c.priceDiv != 0
                || (PROD_BASE_PRICE / c.priceDiv) % 100 != 0 || c.daySeconds < 60 || c.dayOffset >= c.daySeconds
        ) revert BadConfig();
        BASE_PRICE = PROD_BASE_PRICE / c.priceDiv;
        OPEN_BNB = PROD_OPEN_BNB / c.priceDiv;
        DAY_SECONDS = c.daySeconds;
        DAY_OFFSET = c.dayOffset;
        _bnbIs0 = pair.token0() == c.wbnb;
        for (uint256 i; i < c.unblockable.length; i++) {
            unblockable[c.unblockable[i]] = true;
        }
    }

    receive() external payable {
        if (msg.sender != wbnb) revert BadPayment();
    }

    function priceUnits(uint256 n) public pure returns (uint256) {
        if (n <= 10_000) return 100;
        if (n <= 20_000) return 110 + 10 * ((n - 10_001) / 1_000);
        if (n <= 100_000) return 210 + 2 * ((n - 20_001) / 1_000);
        if (n <= 1_000_000) return 370 + 2 * ((n - 100_001) / 10_000);
        return (5_500 + 15 * ((n - 1_000_001) / 20_000) + 5) / 10;
    }

    function costOf(uint256 shares) public view returns (uint256 cost) {
        uint256 n = totalMinted;
        for (uint256 i; i < shares; i++) {
            cost += priceUnits(n + 1 + i) * BASE_PRICE / 100;
        }
    }

    function quotaOf(uint256 id) public view returns (uint256) {
        return BASE_PER_ID + extraQuota[id];
    }

    function opened() public view returns (bool) {
        return openedTime != 0;
    }

    function reserves() public view returns (uint256 rBnb, uint256 rToken) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        (rBnb, rToken) = _bnbIs0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
    }

    function circulating() public view returns (uint256) {
        return token.totalSupply() - token.balanceOf(address(pair)) - token.balanceOf(DEAD)
            - token.balanceOf(address(this));
    }

    /// @notice 市值底线 = 累计铸造额 × FLOOR_BPS / 10_000（市值 = 流通量 × 池价）
    function floorValue() public view returns (uint256) {
        return totalPaid * FLOOR_BPS / 10_000;
    }

    function bnbQuote(uint256 shares) public view returns (uint256) {
        return costOf(shares);
    }

    /// @notice 当前日序号（北京时间）
    function today() public view returns (uint256) {
        return (block.timestamp + DAY_OFFSET) / DAY_SECONDS;
    }

    /// @notice 等级：0 青铜 / 1 白银 / 2 黄金 / 3 铂金 / 4 钻石 / 5 大师 / 6 王者
    function levelOf(uint256 id) public view returns (uint256 level) {
        level = points[id] / POINTS_PER_LEVEL;
        if (level > MAX_LEVEL) level = MAX_LEVEL;
    }

    /// @notice 返利比例（万分比）：2% / 3% / 4% / 5% / 6% / 8% / 10%
    function rebateBpsOf(uint256 id) public view returns (uint256) {
        uint256 level = levelOf(id);
        if (level >= 6) return 1_000;
        if (level == 5) return 800;
        return 200 + 100 * level;
    }

    /// @notice 结算某一天的邀请榜积分：每天一次、最多 50 个 ID、各加 1 分
    /// @dev 由 quotaSigner（后端）提交；ids 必须严格递增（防重复），且每个 ID 当天确有有效邀请。
    ///      排名在链下按事件计算（见 scripts/award-points.mjs），这样可以先剔除工作室小号再上链。
    ///      不受 renounce 影响：放弃管理权限后积分仍然每天结算。
    function awardDay(uint256 day, uint256[] calldata ids) external {
        if (msg.sender != quotaSigner) revert NotKeeper();
        if (day >= today()) revert DayNotOver();
        if (dayAwarded[day]) revert AlreadyAwarded();
        if (ids.length == 0 || ids.length > AWARDS_PER_DAY) revert BadAward();
        dayAwarded[day] = true;
        uint256 prev;
        for (uint256 i; i < ids.length; i++) {
            uint256 id = ids[i];
            if (id <= prev || invitesOn[day][id] == 0) revert BadAward();
            prev = id;
            uint256 p = points[id] + 1;
            points[id] = p;
            emit PointAwarded(day, id, p);
        }
        emit DayAwarded(day, ids.length);
    }

    /// @notice 领取实时转账失败、记在账上的返利
    function claimOwed() external nonReentrant {
        uint256 amount = owedOf[msg.sender];
        if (amount == 0) revert NothingOwed();
        owedOf[msg.sender] = 0;
        totalOwed -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert PayoutFailed();
        emit OwedClaimed(msg.sender, amount);
    }

    /// @dev 管理权限只认 admin；收款地址 treasury 不能调用任何管理函数
    function _onlyAdmin() private view {
        if (msg.sender != admin) revert NotAdmin();
        if (renounced) revert AdminRenounced();
    }

    function setPaused(bool next) external {
        _onlyAdmin();
        paused = next;
        emit PausedSet(next);
    }

    function openEarly() external nonReentrant {
        _onlyAdmin();
        if (opened() || totalMinted == 0 || totalMinted >= OPEN_AT) revert CannotOpenEarly();
        uint256 bnbIn = pendingBnb;
        uint256 tokensIn = bnbIn * OPEN_TOKENS / OPEN_BNB;
        if (bnbIn == 0 || tokensIn != pendingTokens) revert BadPayment();

        _open(bnbIn, tokensIn);
        emit EarlyOpened(totalMinted);
    }

    function setPoolBlocked(address pool, bool blocked) external {
        _onlyAdmin();
        if (
            pool == address(pair) || pool == address(this) || pool == treasury || pool == feeTreasury || pool == admin || pool == address(token)
                || pool == DEAD || unblockable[pool] || pool.code.length == 0 || _is7702(pool)
        ) revert NotBlockable();
        token.setPoolBlocked(pool, blocked);
    }

    function renounce() external {
        _onlyAdmin();
        renounced = true;
        paused = false;
        token.disableBlocks();
        emit Renounced();
    }

    function _is7702(address a) private view returns (bool) {
        if (a.code.length != 23) return false;
        bytes memory code = a.code;
        return code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00;
    }

    function claimSocial(bytes32 task, bytes32 account, uint256 deadline, bytes calldata signature) external {
        if (block.timestamp > deadline) revert BadSignature();
        if (task != TASK_FOLLOW && task != TASK_TWEET && task != TASK_TELEGRAM) revert BadTask();
        bytes32 domain = keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256("AgentMint"), keccak256("1"), block.chainid, address(this))
        );
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01", domain, keccak256(abi.encode(SOCIAL_TYPEHASH, msg.sender, task, account, deadline))
            )
        );
        (address got, ECDSA.RecoverError err,) = ECDSA.tryRecover(digest, signature);
        if (err != ECDSA.RecoverError.NoError || got != quotaSigner) revert BadSignature();
        (uint256 id, bool ok) = _agent(msg.sender);
        if (!ok) revert NoAgent();
        if (socialDone[id][task]) revert AlreadyGranted();
        uint256 bound = accountAgent[account];
        if (bound != 0 && bound != id) revert AlreadyGranted();
        socialDone[id][task] = true;
        accountAgent[account] = id;
        extraQuota[id] += 1;
        emit QuotaGranted(msg.sender, id, 1, task);
    }

    function _agent(address from) internal view returns (uint256 id, bool ok) {
        try registrar.handleOf(from) returns (string memory handle) {
            if (bytes(handle).length == 0) return (0, false);
            id = uint256(keccak256(bytes(handle)));
            try registrar.ownerOf(id) returns (address owner) {
                ok = owner == from;
            } catch {
                ok = false;
            }
        } catch {
            ok = false;
        }
    }

    /// @return rid 邀请人的 Agent ID；邀请无效时为 0
    function _creditInvite(address from, uint256 id, address referrer) private returns (uint256 rid) {
        if (referrer == address(0) || referrer == from) return 0;
        bool rok;
        (rid, rok) = _agent(referrer);
        if (!rok || rid == id) return 0;
        extraQuota[rid] += INVITE_QUOTA;
        emit QuotaGranted(referrer, rid, INVITE_QUOTA, REASON_INVITE);
    }

    /// @dev 有效邀请：记当天邀请数，按邀请人当前等级用 BNB 实时返利；返回从收款份额里扣掉的金额
    function _rebate(address referrer, uint256 rid, uint256 inviteeId, uint256 paid) private returns (uint256 amount) {
        uint256 day = today();
        invitesOn[day][rid] += 1;
        uint256 bps = rebateBpsOf(rid);
        amount = paid * bps / 10_000;
        IWrappedBNB(wbnb).withdraw(amount);
        (bool ok,) = referrer.call{value: amount, gas: REBATE_GAS}("");
        if (!ok) {
            owedOf[referrer] += amount;
            totalOwed += amount;
        }
        emit InviteRebate(referrer, rid, inviteeId, day, paid, bps, amount, !ok);
    }

    function mint(uint256 shares, address referrer, uint256 maxCost) external payable nonReentrant {
        _mintWithBnb(shares, referrer, maxCost);
    }

    function mintWithBnb(uint256 shares, address referrer, uint256 maxCost) external payable nonReentrant {
        _mintWithBnb(shares, referrer, maxCost);
    }

    function _mintWithBnb(uint256 shares, address referrer, uint256 maxCost) private {
        uint256 id = _check(shares);
        uint256 cost = costOf(shares);
        if (cost > maxCost) revert OverMaxCost();
        if (msg.value < cost) revert BadPayment();
        IWrappedBNB(wbnb).deposit{value: cost}();
        _mintShares(id, shares, cost, referrer);
        uint256 refund = msg.value - cost;
        if (refund > 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert RefundFailed();
        }
    }

    function _check(uint256 shares) private view returns (uint256 id) {
        if (paused) revert Paused();
        if (shares == 0 || shares > MAX_PER_TX) revert BadShares();
        if (totalMinted + shares > TOTAL_SHARES) revert SoldOut();
        bool ok;
        (id, ok) = _agent(msg.sender);
        if (!ok) revert NoAgent();
        if (mintedCount[id] + shares > quotaOf(id)) revert Quota();
    }

    struct Pool {
        uint256 u;
        uint256 t;
        uint256 wU;
        uint256 wT;
        uint256 circ;
        uint256 supply;
        uint256 addU;
        uint256 addT;
        uint256 burnT;
        uint256 userT;
    }

    function _mintShares(uint256 id, uint256 shares, uint256 cost, address referrer) private {
        mintedCount[id] += shares;
        bool live = opened();
        // 有效邀请（拿返利、计入邀请榜）：本笔开始前已经开池 + 新 ID 首次付费 + 单笔满 10 份；开池那一笔不算
        uint256 rebateTo;
        if (!paidOnce[id]) {
            paidOnce[id] = true;
            uint256 rid = _creditInvite(msg.sender, id, referrer);
            if (rid != 0 && live && shares >= REBATE_MIN_SHARES) rebateTo = rid;
        }
        uint256 first = totalMinted + 1;
        uint256 toTreasury;
        Pool memory p;
        if (live) _loadPool(p);

        for (uint256 n = first; n < first + shares; n++) {
            uint256 pay = priceUnits(n) * BASE_PRICE / 100;
            uint256 cut = pay * TREASURY_BPS / 10_000;
            toTreasury += cut;
            totalPaid += pay;
            if (!live) {
                p.userT += USER_SHARE;
                pendingBnb += pay - cut;
                pendingTokens += POOL_SHARE;
                token.mint(address(this), POOL_SHARE);
                if (n == OPEN_AT) {
                    token.mint(msg.sender, p.userT);
                    p.userT = 0;
                    if (pendingBnb != OPEN_BNB || pendingTokens != OPEN_TOKENS) revert BadPayment();
                    _open(OPEN_BNB, OPEN_TOKENS);
                    live = true;
                    _loadPool(p);
                }
            } else {
                _curveShare(p, n, pay - cut);
            }
        }
        totalMinted = first + shares - 1;

        if (p.userT > 0) token.mint(msg.sender, p.userT);
        if (live && p.addU > 0) _settle(p);
        // 返利最多 10%，从 20% 的收款份额里扣，进池的 80% 不受影响
        if (rebateTo != 0) toTreasury -= _rebate(referrer, rebateTo, id, cost);
        if (toTreasury > 0) _payTreasury(toTreasury);
        emit Minted(msg.sender, id, first, shares, cost);

        // 本笔发生了燃烧就跳过自动税币兑换：兑换是一次卖出，会把刚托起来的价格又压下去；
        // 税币留到下一笔不燃烧的铸造或任何人手动调用 swapTax() 时再卖
        if (live && p.burnT == 0 && lastTaxSwapBlock != block.number && token.balanceOf(address(this)) > 0) {
            try this.swapTaxSelf() {}
            catch (bytes memory why) {
                emit TaxSwapFailed(why);
            }
        }
    }

    function _loadPool(Pool memory p) private {
        (p.u, p.t) = reserves();
        // 窗口过期：用本笔交易开始时的储备重开（多笔交易、多地址共享同一个窗口）
        // 小时级窗口，出块者几秒的时间戳偏差不影响结果
        // forge-lint: disable-next-line(block-timestamp)
        if (block.timestamp >= uint256(riseWindowStart) + RISE_WINDOW) _resetWindow(p.u, p.t);
        p.wU = riseWindowU;
        p.wT = riseWindowT;
        p.circ = circulating();
        p.supply = token.totalSupply();
    }

    /// @dev 重开限速窗口。起点价格 = min(当前池价, 上一窗口上限价 = 上一窗口起点价 × (1 + RISE_CAP_BPS/10_000))，
    ///      防止"先买入拉高、再铸 1 份开窗"把本窗口的上限放宽；首个窗口（开池时，尚无上一窗口）直接用开池价。
    ///      价格用储备对 (u, t) 表示：当前价 > 上限价 ⇔ u × wT × 10_000 > t × wU × (10_000 + RISE_CAP_BPS)。
    ///      被截到上限价时，保留当前 t，按上限价折算 u 并向下取整（起点略低 → 上限略紧 → 宁可少烧）
    function _resetWindow(uint256 u, uint256 t) private {
        uint256 prevT = riseWindowT;
        if (prevT != 0) {
            uint256 capNum = uint256(riseWindowU) * (10_000 + RISE_CAP_BPS);
            if (u * prevT * 10_000 > t * capNum) u = capNum * t / (prevT * 10_000);
        }
        // 截断不可能发生：t 来自 Pair 的 uint112 储备；u 是池中 BNB，2^104 wei ≈ 2×10^13 BNB 远超总量；
        // uint40 时间戳可用到公元 36812 年
        // forge-lint: disable-next-line(unsafe-typecast)
        riseWindowStart = uint40(block.timestamp);
        // forge-lint: disable-next-line(unsafe-typecast)
        riseWindowU = uint104(u);
        // forge-lint: disable-next-line(unsafe-typecast)
        riseWindowT = uint112(t);
        emit RiseWindowReset(block.timestamp, u, t);
    }

    function _curveShare(Pool memory p, uint256 n, uint256 lpBnb) private {
        uint256 pay = priceUnits(n) * BASE_PRICE / 100;
        uint256 userT = n <= OPEN_AT ? USER_SHARE : pay * p.t * 10_000 / (p.u * MINT_PRICE_BPS);
        uint256 lpT = (lpBnb * p.t + p.u - 1) / p.u;
        p.supply += userT + lpT;
        if (p.supply > MAX_SUPPLY) revert SoldOut();
        p.userT += userT;
        p.circ += userT;
        p.u += lpBnb;
        p.t += lpT;
        p.addU += lpBnb;
        p.addT += lpT;

        // BAISHOU: floor burn DIHAPUS (desain §10 #1 — BurnMath TIDAK dipakai).
        // Pool tokens ikut kurva linear saja; tidak ada pembakaran di sini.
        // TODO(final): hapus p.burnT, event PoolBurned, _resetWindow/riseWindow*,
        // konstanta FLOOR_BPS/BURN_BUDGET_BPS/RISE_CAP_BPS/POOL_FLOOR_BPS/RISE_WINDOW,
        // dan cabang burn di _settle (burnT selalu 0 di kerangka ini).
    }

    function _settle(Pool memory p) private {
        IERC20(wbnb).safeTransfer(address(pair), p.addU);
        token.mint(address(pair), p.addT);
        pair.mint(DEAD);
        if (p.burnT > 0) {
            token.burnFromPair(p.burnT);
        }
        pair.sync();
    }

    function _open(uint256 bnbIn, uint256 tokensIn) private {
        pendingBnb = 0;
        pendingTokens = 0;
        IERC20(wbnb).safeTransfer(address(pair), bnbIn);
        IERC20(address(token)).safeTransfer(address(pair), tokensIn);
        uint256 lp = pair.mint(DEAD);
        token.enableTrading();
        pair.sync();
        openedTime = block.timestamp;
        // 开池即开第一个限速窗口，起点 = 开池储备
        (uint256 u, uint256 t) = reserves();
        _resetWindow(u, t);
        emit Opened(bnbIn, tokensIn, lp);
    }

    function _swapOn(IPancakePair lp, address tokenIn, address to) private {
        (uint112 r0, uint112 r1,) = lp.getReserves();
        bool inIs0 = lp.token0() == tokenIn;
        (uint256 rIn, uint256 rOut) = inIs0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
        uint256 actualIn = IERC20(tokenIn).balanceOf(address(lp)) - rIn;
        uint256 out = PancakeMath.amountOut(actualIn, rIn, rOut, swapFeeBps);
        (uint256 out0, uint256 out1) = inIs0 ? (uint256(0), out) : (out, uint256(0));
        lp.swap(out0, out1, to, "");
    }

    function swapTax() external nonReentrant {
        if (!opened()) revert NotOpen();
        if (lastTaxSwapBlock == block.number) revert SwappedThisBlock();
        _swapTax();
    }

    function swapTaxSelf() external {
        if (msg.sender != address(this)) revert OnlySelf();
        _swapTax();
    }

    function _swapTax() private {
        (, uint256 rToken) = reserves();
        uint256 amount = token.balanceOf(address(this));
        uint256 cap = rToken * TAX_SWAP_BPS / 10_000;
        if (amount > cap) amount = cap;
        if (amount == 0) revert NothingToSwap();
        lastTaxSwapBlock = block.number;
        IERC20(address(token)).safeTransfer(address(pair), amount);
        uint256 before = IERC20(wbnb).balanceOf(address(this));
        _swapOn(pair, address(token), address(this));
        uint256 bnbOut = IERC20(wbnb).balanceOf(address(this)) - before;
        _pay(feeTreasury, bnbOut);
        emit TaxSwapped(amount, bnbOut);
    }

    function _payTreasury(uint256 amount) private {
        _pay(treasury, amount);
    }

    function _pay(address to, uint256 amount) private {
        IWrappedBNB(wbnb).withdraw(amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert PayoutFailed();
    }
}
