// SPDX-License-Identifier: MIT
// *****************************************************************************
// BAISHOU — AgentToken.sol — FINAL (step 2, 19 Nov 2026)
// Fork basis: $AIC AgentToken (BscScan-verified, MIT); OpenZeppelin ERC20 (MIT).
// Desain: ~/workspace/launchpad-research/POLA-BARU-ARUNIKA.md §3/§10 (Opsi B).
//
// BAISHOU vs AIC:
//   - MAX_SUPPLY 444 triliun -> 510,8544 triliun (hard cap, = sold-out penuh
//     1.680.000 share + free 16.800 share).
//   - Pajak TETAP 2%/2%: beli 2% ke minter; jual 1% burn + 1% ke minter
//     (lalu minter swap jadi BNB dan masuk DIVIDEND pool — 0% ke tim).
//   - DIVIDEN (BARU): accumulator ala DividendPayingToken, ditulis ulang
//     sendiri (magnifiedDividendPerShare, magnitude 2**128). BUKAN copas.
//     depositDividends() onlyMinter; claimDividend() min 0,001 BNB.
//   - burnFromPair DIHAPUS (BurnMath/floor dihapus total); diganti burnFrom()
//     umum onlyMinter (dipakai exit(): bakar token minter yang keluar).
// *****************************************************************************
pragma solidity ^0.8.24;

import {ERC20} from "./vendor/openzeppelin/token/ERC20/ERC20.sol";
import {IPancakeFactory} from "./interfaces/IPancake.sol";

/// @title AgentToken
/// @notice BAISHOU ($BAISHOU): buy tax 2% to minter; sell 1% burn + 1% to
///         minter; pre-pool only the minter may move tokens; single WBNB V2
///         pair; holder dividends via a magnified accumulator.
contract AgentToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 510_854_400_000_000 ether;
    uint256 public constant BUY_TAX_BPS = 200;
    uint256 public constant SELL_BURN_BPS = 100;
    uint256 public constant SELL_KEEP_BPS = 100;
    /// @notice Dividend accumulator magnitude (2**128, pola DividendPayingToken).
    uint256 public constant MAGNITUDE = 2 ** 128;
    /// @notice Minimum dividend claim (di bawah ini tetap terakumulasi, tidak hangus).
    uint256 public constant MIN_DIVIDEND_CLAIM = 0.001 ether;
    uint256 private constant PROBE_GAS = 20_000;
    address public constant DEAD = 0x000000000000000000000000000000000000dEaD;

    address public immutable wbnb;
    address public immutable pair;
    address public immutable poolManager;
    address public immutable infinityVault;

    address public deployer;
    address public minter;
    bool public tradingEnabled;
    bool public blocksDisabled;
    mapping(address => bool) public blockedPool;

    // —— Dividen (accumulator) ——
    uint256 public magnifiedDividendPerShare;
    mapping(address => int256) public magnifiedDividendCorrections;
    mapping(address => uint256) public withdrawnDividends;
    uint256 public totalDividends;

    event TradingEnabled(uint256 at);
    event MinterInitialized(address indexed minter);
    event PoolBlocked(address indexed pool, bool blocked);
    event BlocksDisabled();
    event DividendsDeposited(address indexed from, uint256 amount);
    event DividendClaimed(address indexed holder, uint256 amount);

    error NotDeployer();
    error NotMinter();
    error AlreadyInitialized();
    error ZeroAddress();
    error TransfersClosed();
    error PoolRejected();
    error SupplyCap();
    error NoHolders();
    error DividendTooSmall();
    error PayoutFailed();

    constructor(
        string memory name_,
        string memory symbol_,
        address wbnb_,
        address factory_,
        address poolManager_,
        address infinityVault_
    ) ERC20(name_, symbol_) {
        if (wbnb_ == address(0) || factory_ == address(0)) revert ZeroAddress();
        wbnb = wbnb_;
        poolManager = poolManager_;
        infinityVault = infinityVault_;
        pair = IPancakeFactory(factory_).createPair(address(this), wbnb_);
        deployer = msg.sender;
    }

    function initialize(address minter_) external {
        if (msg.sender != deployer) revert NotDeployer();
        if (minter != address(0)) revert AlreadyInitialized();
        if (minter_ == address(0)) revert ZeroAddress();
        minter = minter_;
        deployer = address(0);
        emit MinterInitialized(minter_);
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        if (totalSupply() + amount > MAX_SUPPLY) revert SupplyCap();
        _mint(to, amount);
    }

    /// @notice Bakar token dari alamat mana pun — hanya minter (dipakai
    ///         AgentMint.exit(): bakar token + share pemegang yang keluar).
    function burnFrom(address from, uint256 amount) external onlyMinter {
        _burn(from, amount);
    }

    function enableTrading() external onlyMinter {
        if (tradingEnabled) return;
        tradingEnabled = true;
        emit TradingEnabled(block.timestamp);
    }

    function setPoolBlocked(address pool, bool blocked) external onlyMinter {
        blockedPool[pool] = blocked;
        emit PoolBlocked(pool, blocked);
    }

    function disableBlocks() external onlyMinter {
        blocksDisabled = true;
        emit BlocksDisabled();
    }

    /// @notice Minter menyetor BNB hasil swap pajak ke dividend pool.
    /// @dev Menaikkan magnifiedDividendPerShare pro-rata atas totalSupply
    ///      saat ini; yang beli sesudah setoran tidak dapat dividen lalu.
    function depositDividends() external payable onlyMinter {
        if (msg.value == 0) return;
        uint256 supply = totalSupply();
        if (supply == 0) revert NoHolders();
        magnifiedDividendPerShare += (msg.value * MAGNITUDE) / supply;
        totalDividends += msg.value;
        emit DividendsDeposited(msg.sender, msg.value);
    }

    function withdrawableDividendOf(address account) public view returns (uint256) {
        int256 acc = (int256(balanceOf(account) * magnifiedDividendPerShare)
            + magnifiedDividendCorrections[account]) / int256(MAGNITUDE);
        if (acc <= 0) return 0;
        uint256 withdrawn = withdrawnDividends[account];
        if (uint256(acc) <= withdrawn) return 0;
        return uint256(acc) - withdrawn;
    }

    /// @notice Klaim dividen BNB pro-rata. Di bawah MIN_DIVIDEND_CLAIM revert
    ///         (dana tetap terakumulasi, tidak hangus); tidak bisa double-klaim
    ///         karena withdrawnDividends dicatat sebelum pembayaran.
    function claimDividend() external {
        uint256 amount = withdrawableDividendOf(msg.sender);
        if (amount < MIN_DIVIDEND_CLAIM) revert DividendTooSmall();
        withdrawnDividends[msg.sender] += amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        if (!ok) revert PayoutFailed();
        emit DividendClaimed(msg.sender, amount);
    }

    function rejects(address to) public view returns (bool) {
        if (to == pair) return false;
        if (to == poolManager || to == infinityVault) return true;
        if (blockedPool[to] && !blocksDisabled) return true;
        return _isOtherPair(to);
    }

    function _isOtherPair(address a) private view returns (bool) {
        uint256 size = a.code.length;
        if (size == 0) return false;
        if (size == 23) {
            bytes memory code = a.code;
            if (code[0] == 0xef && code[1] == 0x01 && code[2] == 0x00) return false;
        }
        address t0 = _probe(a, 0x0dfe1681);
        if (t0 == address(this)) return _probe(a, 0xd21220a7) != address(0);
        if (t0 == address(0)) return false;
        return _probe(a, 0xd21220a7) == address(this);
    }

    function _probe(address a, bytes4 selector) private view returns (address out) {
        (bool ok, bytes memory data) = a.staticcall{gas: PROBE_GAS}(abi.encodeWithSelector(selector));
        if (!ok || data.length != 32) return address(0);
        uint256 word = abi.decode(data, (uint256));
        if (word >> 160 != 0) return address(0);
        out = address(uint160(word));
    }

    /// @dev Setiap perpindahan saldo (mint/burn/transfer/pajak) menyesuaikan
    ///      koreksi dividen supaya saldo baru tidak mewarisi dividen lama dan
    ///      saldo yang pergi tidak kehilangan dividen yang sudah diperoleh.
    function _applyDividendCorrection(address from, address to, uint256 value) private {
        if (value == 0 || magnifiedDividendPerShare == 0) return;
        int256 delta = int256(magnifiedDividendPerShare * value);
        if (from != address(0)) magnifiedDividendCorrections[from] += delta;
        if (to != address(0)) magnifiedDividendCorrections[to] -= delta;
    }

    function _update(address from, address to, uint256 value) internal override {
        // Mint (from == 0) dan burn (to == 0) selalu diizinkan — burn
        // dipakai exit() pre-pool saat trading masih tertutup.
        if (from == address(0) || to == address(0)) {
            super._update(from, to, value);
            _applyDividendCorrection(from, to, value);
            return;
        }
        address m = minter;
        if (!tradingEnabled) {
            if (from != m) revert TransfersClosed();
            super._update(from, to, value);
            _applyDividendCorrection(from, to, value);
            return;
        }
        if (rejects(to)) revert PoolRejected();
        if (from == m || to == m) {
            super._update(from, to, value);
            _applyDividendCorrection(from, to, value);
            return;
        }
        if (from == pair) {
            uint256 tax = (value * BUY_TAX_BPS) / 10_000;
            super._update(from, m, tax);
            _applyDividendCorrection(from, m, tax);
            super._update(from, to, value - tax);
            _applyDividendCorrection(from, to, value - tax);
        } else if (to == pair) {
            uint256 burnt = (value * SELL_BURN_BPS) / 10_000;
            uint256 kept = (value * SELL_KEEP_BPS) / 10_000;
            super._update(from, DEAD, burnt);
            _applyDividendCorrection(from, DEAD, burnt);
            super._update(from, m, kept);
            _applyDividendCorrection(from, m, kept);
            super._update(from, to, value - burnt - kept);
            _applyDividendCorrection(from, to, value - burnt - kept);
        } else {
            super._update(from, to, value);
            _applyDividendCorrection(from, to, value);
        }
    }
}
