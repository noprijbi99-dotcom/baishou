// SPDX-License-Identifier: MIT
// *****************************************************************************
// BAISHOU — AgentMint.sol — FINAL (step 2, 19 Nov 2026)
// Fork basis: $AIC AgentMint (BscScan-verified, MIT). Desain final:
// ~/workspace/launchpad-research/POLA-BARU-ARUNIKA.md §3/§4/§8b/§10 (Opsi B).
//
// ANGKA FINAL (user 19 Nov 13:22 WIB, shares 10x): TOTAL 1.680.000 share;
// pre-pool 168.000 @ 0,00168 BNB flat, 168.000.000 token/share TETAP
// (pre-pool DAN pasca-pool — JANGAN rumus AIC pay*p.t/p.u); pool buka di
// share 168.000: 225,792 BNB + 22,5792 triliun token; kurva LINEAR +2% per
// epoch 16.800 share, cap 0,00336 BNB (2x) di share 1.008.000, lalu flat.
// MAX_SUPPLY 510,8544 triliun — dicek tiap mint, revert SoldOut/SupplyCap.
//
// YANG DIHAPUS dari fork AIC: BurnMath/floor total (FLOOR/BURN_BUDGET/
// RISE_WINDOW/RISE_CAP/POOL_FLOOR, floorValue, _resetWindow, riseWindow*,
// PoolBurned, burn di _settle, burnFromPair); invite/poin/level/rebate
// instan (points, invitesOn, dayAwarded, awardDay, levelOf, rebateBpsOf,
// _creditInvite, _rebate, REBATE_MIN/POINTS_PER_LEVEL/MAX_LEVEL/AWARDS_PER_DAY);
// social tasks (claimSocial, TASK_*, socialDone, accountAgent, extraQuota);
// DAY_SECONDS/DAY_OFFSET/today(); quotaSigner (tak terpakai lagi).
//
// ESCROW (§8b, MENGIKAT): treasury 15% + referral 5% TIDAK PERNAH dibayar
// sebelum pool buka. Pre-pool: 15% -> escrowTreasury, 5% -> referralAccrued
// (atau ke pool kalau tak ada referrer valid), 80% -> pendingBnb. Saat pool
// buka (_open): escrowTreasury dibayar ke treasury (gagal -> owedOf, PULL via
// claimOwed); referral pre-pool tetap claimable via claimReferral() sesudah
// pool buka. Pasca-pool: pola SAMA (akumulasi + claim) — konsisten: treasury
// klaim via claimTreasury(), referrer via claimReferral(). NOL push instan.
// Refund/exit TIDAK PERNAH diblokir pause. TIDAK ADA fungsi withdraw/drain:
// dana hanya ke deposan (refund/exit) atau ke pool.
// *****************************************************************************
pragma solidity ^0.8.24;

import {IERC20} from "./vendor/openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "./vendor/openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "./vendor/openzeppelin/utils/ReentrancyGuard.sol";
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

contract AgentMint is ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant TOTAL_SHARES = 1_680_000;
    uint256 public constant MAX_SUPPLY = 510_854_400_000_000 ether;
    uint256 public constant OPEN_AT = 168_000;
    uint256 public constant PROD_BASE_PRICE = 0.00168 ether;
    uint256 public constant PROD_OPEN_BNB = 225.792 ether;
    uint256 public constant USER_SHARE = 168_000_000 ether;
    uint256 public constant POOL_SHARE = 134_400_000 ether;
    uint256 public constant OPEN_TOKENS = OPEN_AT * POOL_SHARE;
    uint256 public constant TREASURY_BPS = 1_500;
    uint256 public constant REFERRAL_BPS = 500;
    uint256 public constant MINT_PRICE_BPS = 10_000;
    uint256 public constant TAX_SWAP_BPS = 10;
    uint256 public constant BASE_PER_ID = 168;
    uint256 public constant MAX_PER_TX = 168;
    /// @notice Kuota invite DIHAPUS (audit fair-for-all §0): dipertahankan = 0
    ///         sebagai jejak audit — referral HANYA komisi BNB 5%.
    uint256 public constant INVITE_QUOTA = 0;
    uint256 public constant FREE_SHARES = 16_800;
    uint256 public constant EPOCH_SHARES = 16_800;
    /// @notice Jendela target sale: 14 hari sejak startSale() (v2, keputusan
    ///         user 19 Nov 2026 — "target dua minggu, setelah itu refund").
    uint256 public constant SALE_WINDOW = 14 days;
    /// @notice Mint pasca-pool tutup 7 hari sesudah pool buka (tetap).
    uint256 public constant POST_POOL_WINDOW = 7 days;
    uint256 public constant REFUND_WINDOW = 90 days;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    AgentToken public immutable token;
    IPancakePair public immutable pair;
    address public immutable wbnb;
    IAgentHandles public immutable registrar;
    /// @notice Penerima treasury 15% — hanya terima dana (escrow saat pool
    ///         buka + claim pasca-pool); tanpa hak admin apa pun.
    address public immutable treasury;
    /// @notice feeTreasury dipertahankan untuk kompatibilitas Config; TIDAK
    ///         LAGI menerima pajak trading (hasil swap pajak -> dividend pool).
    address public immutable feeTreasury;
    address public immutable admin;
    uint256 public immutable swapFeeBps;
    uint256 public immutable BASE_PRICE;
    uint256 public immutable OPEN_BNB;
    /// @notice Waktu deploy — INFORMATIONAL saja (v2/RT-01: tidak ada jam
    ///         yang berjangkar deploy; jam sale mulai di startSale()).
    uint256 public immutable deployTime;
    bool private immutable _bnbIs0;

    uint256 public totalMinted;
    uint256 public totalPaid;
    bool public paused = true; // deploy dalam keadaan pause; admin buka via startSale()
    bool public renounced;
    bool public reviewPassed;
    uint256 public pendingBnb;
    uint256 public pendingTokens;
    uint256 public openedTime;
    uint256 public lastTaxSwapBlock;

    // —— Escrow / refund ——
    uint256 public escrowTreasury;
    uint256 public forfeitPool;
    mapping(address => uint256) public referralAccrued;
    mapping(address => address) public referrerOf;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public forfeitOf;
    mapping(address => uint256) public owedOf;
    uint256 public totalOwed;

    // —— Free mint ——
    mapping(uint256 => bool) public claimedFree;
    uint256 public freeClaimed;

    // —— Agent Registry (ringan, bukti peserta unik hackathon) ——
    mapping(uint256 => bool) public registered;
    uint256[] public participants;
    uint256 public participantCount;

    mapping(uint256 => uint256) public mintedCount;

    mapping(address => bool) public unblockable;

    // —— v2: jam sale berjangkar MULAI SALE (RT-01) ——
    /// @notice Waktu startSale() dipanggil admin; 0 = sale belum dimulai
    ///         (jam kegagalan BELUM jalan — saleFailed() selalu false dan
    ///         failureTime() = 0). Ditaruh di slot storage terakhir supaya
    ///         layout v1 tidak bergeser.
    uint256 public saleStartTime;

    event PausedSet(bool paused);
    event SaleStarted(uint256 startTime);
    event Renounced();
    event ReviewPassedSet(bool passed);
    event Minted(address indexed minter, uint256 indexed agentTokenId, uint256 firstSerial, uint256 shares, uint256 paid);
    event FreeMinted(address indexed minter, uint256 indexed agentTokenId, uint256 totalFree);
    event ParticipantRegistered(uint256 indexed agentTokenId, address indexed wallet);
    event Opened(uint256 bnbIn, uint256 tokensIn, uint256 lp);
    event TaxSwapped(uint256 tokensIn, uint256 bnbOut);
    event TaxSwapFailed(bytes reason);
    event Exited(address indexed user, uint256 indexed agentTokenId, uint256 shares, uint256 refunded, uint256 forfeited);
    event RefundClaimed(address indexed user, uint256 amount);
    event Swept(uint256 amount);
    event ReferralClaimed(address indexed referrer, uint256 amount);
    event TreasuryClaimed(address indexed treasury, uint256 amount);
    event OwedClaimed(address indexed user, uint256 amount);

    error NotAdmin();
    error BadConfig();
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
    error NotBlockable();
    error NotOpen();
    error NothingToSwap();
    error SwappedThisBlock();
    error OnlySelf();
    error ZeroAddress();
    error AlreadyStarted();
    error ReviewNotPassed();
    error NotFailed();
    error RefundExpired();
    error NotSweepable();
    error ExitClosed();
    error NotTreasury();

    struct Config {
        address token;
        address registrar;
        address treasury;
        address feeTreasury;
        address admin;
        address wbnb;
        uint256 swapFeeBps;
        address[] unblockable;
        /// @dev Formal 1; test boleh > 1 asal membagi habis harga & OPEN_BNB.
        uint256 priceDiv;
    }

    constructor(Config memory c) {
        if (
            c.token == address(0) || c.registrar == address(0) || c.treasury == address(0) || c.feeTreasury == address(0)
                || c.admin == address(0) || c.wbnb == address(0)
        ) revert ZeroAddress();
        token = AgentToken(c.token);
        if (token.wbnb() != c.wbnb) revert BadPayment();
        pair = IPancakePair(token.pair());
        wbnb = c.wbnb;
        registrar = IAgentHandles(c.registrar);
        treasury = c.treasury;
        feeTreasury = c.feeTreasury;
        admin = c.admin;
        swapFeeBps = c.swapFeeBps;
        if (c.priceDiv == 0 || PROD_BASE_PRICE % c.priceDiv != 0 || PROD_OPEN_BNB % c.priceDiv != 0
            || (PROD_BASE_PRICE / c.priceDiv) % 100 != 0
        ) revert BadConfig();
        BASE_PRICE = PROD_BASE_PRICE / c.priceDiv;
        OPEN_BNB = PROD_OPEN_BNB / c.priceDiv;
        deployTime = block.timestamp;
        _bnbIs0 = pair.token0() == c.wbnb;
        for (uint256 i; i < c.unblockable.length; i++) {
            unblockable[c.unblockable[i]] = true;
        }
    }

    receive() external payable {
        if (msg.sender != wbnb) revert BadPayment();
    }

    /// @notice Harga per share ke-n dalam satuan BASE_PRICE/100.
    ///         n <= 168.000 -> 100 (flat). Sesudah itu epoch =
    ///         (n-168.001)/16.800 + 1, units = min(100 + 2*epoch, 200).
    ///         Cap 0,00336 (2x) tercapai di share 1.008.000, lalu flat.
    function priceUnits(uint256 n) public pure returns (uint256) {
        if (n <= OPEN_AT) return 100;
        uint256 epoch = (n - OPEN_AT - 1) / EPOCH_SHARES + 1;
        uint256 units = 100 + 2 * epoch;
        return units > 200 ? 200 : units;
    }

    function costOf(uint256 shares) public view returns (uint256 cost) {
        uint256 n = totalMinted;
        // BASE_PRICE % 100 == 0 dijamin constructor, jadi (BASE_PRICE/100)
        // eksak — tidak ada kehilangan presisi dari pembagian ini.
        uint256 unit = BASE_PRICE / 100;
        for (uint256 i; i < shares; i++) {
            cost += priceUnits(n + 1 + i) * unit;
        }
    }

    /// @notice Kuota = BASE_PER_ID untuk semua Agent ID (extraQuota dihapus).
    function quotaOf(uint256) public pure returns (uint256) {
        return BASE_PER_ID;
    }

    function opened() public view returns (bool) {
        return openedTime != 0;
    }

    /// @notice Deadline target sale = saleStartTime + SALE_WINDOW (14 hari).
    ///         Mengembalikan 0 sebelum sale dimulai (jam belum jalan).
    function failureTime() public view returns (uint256) {
        return saleStartTime == 0 ? 0 : saleStartTime + SALE_WINDOW;
    }

    /// @notice Launch gagal: sale SUDAH dimulai, deadline 14 hari lewat &
    ///         pool belum buka. Sebelum startSale(): selalu false, di
    ///         timestamp berapa pun (tidak ada bom waktu dari deploy).
    function saleFailed() public view returns (bool) {
        return saleStartTime != 0 && !opened() && block.timestamp > failureTime();
    }

    /// @notice Mint tutup 7 hari sesudah pool buka ATAU saat 1.680.000 share.
    function mintClosed() public view returns (bool) {
        return opened() && (block.timestamp > openedTime + POST_POOL_WINDOW || totalMinted >= TOTAL_SHARES);
    }

    function reserves() public view returns (uint256 rBnb, uint256 rToken) {
        (uint112 r0, uint112 r1,) = pair.getReserves();
        (rBnb, rToken) = _bnbIs0 ? (uint256(r0), uint256(r1)) : (uint256(r1), uint256(r0));
    }

    function circulating() public view returns (uint256) {
        return token.totalSupply() - token.balanceOf(address(pair)) - token.balanceOf(DEAD)
            - token.balanceOf(address(this));
    }

    function bnbQuote(uint256 shares) public view returns (uint256) {
        return costOf(shares);
    }

    function isParticipant(uint256 id) public view returns (bool) {
        return registered[id];
    }

    function _register(uint256 id) private {
        if (registered[id]) return;
        registered[id] = true;
        participants.push(id);
        participantCount++;
        emit ParticipantRegistered(id, msg.sender);
    }

    /// @notice Klaim PULL atas pembayaran yang gagal ditransfer (mis. treasury
    ///         saat _open). Bukan jalur refund — lihat claimRefund().
    function claimOwed() external nonReentrant {
        uint256 amount = owedOf[msg.sender];
        if (amount == 0) revert NothingOwed();
        owedOf[msg.sender] = 0;
        totalOwed -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert PayoutFailed();
        emit OwedClaimed(msg.sender, amount);
    }

    /// @dev Admin hanya admin; treasury tidak punya hak admin.
    function _onlyAdmin() private view {
        if (msg.sender != admin) revert NotAdmin();
        if (renounced) revert AdminRenounced();
    }

    function setPaused(bool next) external {
        _onlyAdmin();
        paused = next;
        emit PausedSet(next);
    }

    /// @notice Gerbang review independen: renounce() terkunci sampai true.
    function setReviewPassed(bool next) external {
        _onlyAdmin();
        reviewPassed = next;
        emit ReviewPassedSet(next);
    }

    /// @notice Mulai sale — SATU KALI, admin (v2/RT-01+RT-02): menetapkan
    ///         saleStartTime = sekarang (jam target 14 hari mulai jalan)
    ///         dan membuka pause secara atomik dalam satu tx. Sebelum
    ///         fungsi ini dipanggil, kontrak boleh menunggu selamanya:
    ///         tidak ada deadline yang berjalan dari deploy. Pool hanya
    ///         bisa buka lewat jalur mint mencapai OPEN_AT (openEarly
    ///         DIHAPUS di v2 — tidak ada lagi jalur buka pool dini yang
    ///         membatalkan janji escrow/refund).
    function startSale() external {
        _onlyAdmin();
        if (saleStartTime != 0) revert AlreadyStarted();
        saleStartTime = block.timestamp;
        paused = false;
        emit SaleStarted(saleStartTime);
        emit PausedSet(false);
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
        if (!reviewPassed) revert ReviewNotPassed();
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

    /// @return refAddr referrer valid (Agent ID, bukan minter) atau address(0)
    function _validReferrer(address from, uint256 id, address referrer) private view returns (address refAddr) {
        if (referrer == address(0) || referrer == from) return address(0);
        (uint256 rid, bool rok) = _agent(referrer);
        if (!rok || rid == id) return address(0);
        return referrer;
    }

    // ============ MINT ============

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
        _register(id);
        _mintShares(id, shares, cost, referrer);
        uint256 refund = msg.value - cost;
        if (refund > 0) {
            (bool ok,) = msg.sender.call{value: refund}("");
            if (!ok) revert RefundFailed();
        }
    }

    function _check(uint256 shares) private view returns (uint256 id) {
        if (paused) revert Paused();
        if (saleFailed()) revert SoldOut();
        if (mintClosed()) revert SoldOut();
        if (shares == 0 || shares > MAX_PER_TX) revert BadShares();
        if (totalMinted + shares > TOTAL_SHARES) revert SoldOut();
        bool ok;
        (id, ok) = _agent(msg.sender);
        if (!ok) revert NoAgent();
        if (mintedCount[id] + shares > quotaOf(id)) revert Quota();
    }

    /// @notice Free claim: 1x per Agent ID, 168.000.000 token, tanpa BNB,
    ///         first-come sampai 16.800 klaim. TIDAK menambah mintedCount
    ///         (tidak mengurangi cap beli 168). Pause memblokir free mint.
    function freeMint() external nonReentrant {
        if (paused) revert Paused();
        if (saleFailed()) revert SoldOut();
        if (mintClosed()) revert SoldOut();
        (uint256 id, bool ok) = _agent(msg.sender);
        if (!ok) revert NoAgent();
        if (claimedFree[id]) revert AlreadyGranted();
        if (freeClaimed >= FREE_SHARES) revert SoldOut();
        claimedFree[id] = true;
        freeClaimed++;
        _register(id);
        token.mint(msg.sender, USER_SHARE);
        emit FreeMinted(msg.sender, id, freeClaimed);
    }

    struct Pool {
        uint256 u;
        uint256 t;
        uint256 circ;
        uint256 supply;
        uint256 addU;
        uint256 addT;
        uint256 userT;
    }

    function _mintShares(uint256 id, uint256 shares, uint256 cost, address referrer) private {
        // Referrer divalidasi SEKALI per tx; 5% masuk referralAccrued (escrow),
        // bukan dibayar instan. Tanpa referrer valid -> 5% masuk pool.
        address refAddr = _validReferrer(msg.sender, id, referrer);
        if (refAddr != address(0) && referrerOf[msg.sender] == address(0)) {
            referrerOf[msg.sender] = refAddr;
        }
        mintedCount[id] += shares;
        bool live = opened();
        uint256 first = totalMinted + 1;
        Pool memory p = Pool(0, 0, 0, 0, 0, 0, 0);
        if (live) _loadPool(p);

        uint256 userT = 0;
        uint256 unit = BASE_PRICE / 100;
        for (uint256 n = first; n < first + shares; n++) {
            uint256 pay = priceUnits(n) * unit;
            uint256 treasuryCut = pay * TREASURY_BPS / 10_000;
            uint256 referralCut = pay * REFERRAL_BPS / 10_000;
            escrowTreasury += treasuryCut;
            uint256 poolPart;
            if (refAddr != address(0)) {
                referralAccrued[refAddr] += referralCut;
                poolPart = pay - treasuryCut - referralCut;
            } else {
                poolPart = pay - treasuryCut; // referral 5% jatuh ke pool
            }
            totalPaid += pay;
            deposits[msg.sender] += pay;
            if (!live) {
                userT += USER_SHARE;
                pendingBnb += poolPart;
                pendingTokens += POOL_SHARE;
                token.mint(address(this), POOL_SHARE);
                if (n == OPEN_AT) {
                    token.mint(msg.sender, userT);
                    userT = 0;
                    // poolPart bisa 80% (ada referrer) atau 85% (tanpa
                    // referrer) per share, jadi pendingBnb >= OPEN_BNB.
                    if (pendingBnb < OPEN_BNB || pendingTokens != OPEN_TOKENS) revert BadPayment();
                    _open(pendingBnb + forfeitPool, OPEN_TOKENS);
                    live = true;
                    _loadPool(p);
                }
            } else {
                _curveShare(p, poolPart);
            }
        }
        totalMinted = first + shares - 1;

        uint256 toUser = userT + p.userT;
        if (toUser > 0) token.mint(msg.sender, toUser);
        if (live && p.addU > 0) _settle(p);
        emit Minted(msg.sender, id, first, shares, cost);

        // Swap otomatis pajak yang terkumpul (sekali per blok); gagal -> event.
        if (live && lastTaxSwapBlock != block.number && token.balanceOf(address(this)) > 0) {
            try this.swapTaxSelf() {}
            catch (bytes memory why) {
                emit TaxSwapFailed(why);
            }
        }
    }

    function _loadPool(Pool memory p) private view {
        (p.u, p.t) = reserves();
        p.circ = circulating();
        p.supply = token.totalSupply();
    }

    /// @dev FIXED TOKENS: userT = USER_SHARE tetap per share (pre-pool DAN
    ///      pasca-pool); lpT ikut kurva pool. JANGAN rumus AIC
    ///      pay*p.t/p.u (rata-rata pasca-pool ~290 jt/share, max supply
    ///      jebol ke ~1,097 kuadriliun vs cap 510,8544 triliun).
    function _curveShare(Pool memory p, uint256 lpBnb) private {
        uint256 userT = USER_SHARE;
        uint256 lpT = (lpBnb * p.t + p.u - 1) / p.u;
        p.supply += userT + lpT;
        if (p.supply > MAX_SUPPLY) revert SoldOut();
        p.userT += userT;
        p.circ += userT;
        p.u += lpBnb;
        p.t += lpT;
        p.addU += lpBnb;
        p.addT += lpT;
    }

    function _settle(Pool memory p) private {
        IERC20(wbnb).safeTransfer(address(pair), p.addU);
        token.mint(address(pair), p.addT);
        pair.mint(DEAD);
        pair.sync();
    }

    function _open(uint256 bnbIn, uint256 tokensIn) private {
        // Tandai buka DULU sebelum panggilan eksternal apa pun (CEI).
        openedTime = block.timestamp;
        pendingBnb = 0;
        pendingTokens = 0;
        forfeitPool = 0;
        // Bayar escrow treasury SEKALI saat pool buka; gagal -> owedOf (PULL).
        uint256 treasuryDue = escrowTreasury;
        escrowTreasury = 0;
        if (treasuryDue > 0) _payOrOwe(treasury, treasuryDue);
        IERC20(wbnb).safeTransfer(address(pair), bnbIn);
        IERC20(address(token)).safeTransfer(address(pair), tokensIn);
        uint256 lp = pair.mint(DEAD);
        token.enableTrading();
        pair.sync();
        emit Opened(bnbIn, tokensIn, lp);
    }

    // ============ EXIT / REFUND ============
    // Pause TIDAK PERNAH memblokir fungsi-fungsi di seksi ini (§8b).

    /// @notice Keluar sebelum pool buka: kembali 80% x shares x harga
    ///         pre-pool flat; 20% ditahan sebagai forfeit kondisional
    ///         (ke LP kalau sukses, kembali 100% kalau launch gagal).
    ///         Bakar share + token pemanggil. Hanya selama net shares
    ///         < target (168.000) dan pool belum buka.
    function exit(uint256 shares) external nonReentrant {
        if (opened() || totalMinted >= OPEN_AT) revert ExitClosed();
        (uint256 id, bool ok) = _agent(msg.sender);
        if (!ok) revert NoAgent();
        if (shares == 0 || shares > mintedCount[id]) revert BadShares();
        uint256 value = shares * BASE_PRICE; // pre-pool flat
        uint256 refund = value * 80 / 100;
        uint256 forfeit = value - refund;
        address refAddr = referrerOf[msg.sender];
        uint256 treasuryCut = value * TREASURY_BPS / 10_000;
        uint256 referralCut = value * REFERRAL_BPS / 10_000;
        escrowTreasury -= treasuryCut;
        if (refAddr != address(0)) {
            referralAccrued[refAddr] -= referralCut;
            pendingBnb -= refund;
        } else {
            pendingBnb -= refund + referralCut; // 5% dulu masuk pool
        }
        forfeitOf[msg.sender] += forfeit;
        forfeitPool += forfeit;
        deposits[msg.sender] -= value;
        mintedCount[id] -= shares;
        totalMinted -= shares;
        pendingTokens -= shares * POOL_SHARE;
        token.burnFrom(msg.sender, shares * USER_SHARE);
        token.burnFrom(address(this), shares * POOL_SHARE);
        emit Exited(msg.sender, id, shares, refund, forfeit);
        _pay(msg.sender, refund);
    }

    /// @notice Refund 100% PULL kalau launch GAGAL (deadline lewat, pool
    ///         belum buka): deposits + forfeit. Jendela 90 hari sejak gagal.
    ///         TIDAK PERNAH dibayar kalau pool sudah buka.
    function claimRefund() external nonReentrant {
        if (!saleFailed()) revert NotFailed();
        if (block.timestamp > failureTime() + REFUND_WINDOW) revert RefundExpired();
        uint256 amount = deposits[msg.sender] + forfeitOf[msg.sender];
        if (amount == 0) revert NothingOwed();
        deposits[msg.sender] = 0;
        forfeitOf[msg.sender] = 0;
        emit RefundClaimed(msg.sender, amount);
        _pay(msg.sender, amount);
    }

    /// @notice Sesudah jendela refund 90 hari lewat, siapa pun boleh sapu
    ///         sisa escrow ke DEAD (dibakar, bukan ke tim). Setelah ini escrow 0.
    function sweepUnclaimed() external nonReentrant {
        if (!saleFailed() || block.timestamp <= failureTime() + REFUND_WINDOW) revert NotSweepable();
        pendingBnb = 0;
        escrowTreasury = 0;
        forfeitPool = 0;
        uint256 wbnbBal = IERC20(wbnb).balanceOf(address(this));
        uint256 amount = wbnbBal + address(this).balance;
        if (wbnbBal > 0) IWrappedBNB(wbnb).withdraw(wbnbBal);
        if (amount > 0) {
            (bool ok,) = DEAD.call{value: amount}("");
            if (!ok) revert PayoutFailed();
        }
        emit Swept(amount);
    }

    // ============ CLAIM (treasury / referral, PULL, sesudah pool buka) ============

    /// @notice Treasury klaim akumulasi 15% pasca-pool (pre-pool sudah dibayar
    ///         sekali di _open). Hanya treasury.
    function claimTreasury() external nonReentrant {
        if (msg.sender != treasury) revert NotTreasury();
        if (!opened()) revert NotOpen();
        uint256 amount = escrowTreasury;
        if (amount == 0) revert NothingOwed();
        escrowTreasury = 0;
        emit TreasuryClaimed(msg.sender, amount);
        _pay(msg.sender, amount);
    }

    /// @notice Referrer klaim komisi 5% yang terakumulasi (pre-pool + pasca-pool).
    ///         Hanya sesudah pool buka; sebelum itu NOL dibayar.
    function claimReferral() external nonReentrant {
        if (!opened()) revert NotOpen();
        uint256 amount = referralAccrued[msg.sender];
        if (amount == 0) revert NothingOwed();
        referralAccrued[msg.sender] = 0;
        emit ReferralClaimed(msg.sender, amount);
        _pay(msg.sender, amount);
    }

    // ============ TAX SWAP -> DIVIDEN ============

    function swapTax() external nonReentrant {
        if (!opened()) revert NotOpen();
        if (lastTaxSwapBlock == block.number) revert SwappedThisBlock();
        _swapTax();
    }

    function swapTaxSelf() external {
        if (msg.sender != address(this)) revert OnlySelf();
        _swapTax();
    }

    /// @dev BNB hasil swap pajak masuk DIVIDEND POOL token (bukan feeTreasury).
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
        if (bnbOut > 0) {
            IWrappedBNB(wbnb).withdraw(bnbOut);
            token.depositDividends{value: bnbOut}();
        }
        emit TaxSwapped(amount, bnbOut);
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

    /// @dev Bayar atau catat utang (fallback PULL) — dipakai _open untuk treasury.
    function _payOrOwe(address to, uint256 amount) private {
        IWrappedBNB(wbnb).withdraw(amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) {
            owedOf[to] += amount;
            totalOwed += amount;
        }
    }

    function _pay(address to, uint256 amount) private {
        IWrappedBNB(wbnb).withdraw(amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert PayoutFailed();
    }
}
