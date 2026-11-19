// SPDX-License-Identifier: MIT
// *****************************************************************************
// BAISHOU — AgentToken.sol — DRAFT FORK BASE (BUKAN KONTRAK FINAL)
// Asal: $AIC AgentToken, diverifikasi BscScan. Disalin sebagai titik awal fork.
// Perubahan BAISHOU vs AIC (lihat POLA-BARU-ARUNIKA.md §3/§10):
//   - Nama/simbol -> BAISHOU / $BAISHOU (di constructor saat deploy).
//   - MAX_SUPPLY 444 triliun -> cap final dari simulasi ekonomi (yang mengikat
//     adalah 168.000 share + jendela mint 7 hari pasca-pool; supply pembeli
//     28,252224 miliar + cadangan pool).
//   - Pajak TETAP 2%/2%: beli 2% ke minter; jual 1% burn + 1% DIVIDEN holder.
//     Dividen = accumulator claims — BARU, belum ada di file ini (AIC: 1% kept
//     ke minter lalu swapTax ke feeTreasury; BAISHOU: 1% kept masuk dividend pool).
//   - burnFromPair dipakai kontrak mint saat ini; setelah BurnMath dihapus,
//     TODO(final): evaluasi apakah burnFromPair masih perlu.
// JANGAN DEPLOY file ini.
// *****************************************************************************
pragma solidity ^0.8.24;

import {ERC20} from "./vendor/openzeppelin/token/ERC20/ERC20.sol";
import {IPancakeFactory} from "./interfaces/IPancake.sol";

/// @title AgentToken
/// @notice 铸造盘通用代币模板：名称/符号由部署参数决定，其余规则与安小将完全一致
/// @dev 买入税 2% 进铸造合约；卖出 1% 销毁 + 1% 进铸造合约；开池前只允许铸造合约转出；
///      拒绝流入 Pancake Infinity 与其他交易对，只保留与 WBNB 的唯一 V2 池
contract AgentToken is ERC20 {
    uint256 public constant MAX_SUPPLY = 444_000_000_000_000 ether;
    uint256 public constant BUY_TAX_BPS = 200;
    uint256 public constant SELL_BURN_BPS = 100;
    uint256 public constant SELL_KEEP_BPS = 100;
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

    event TradingEnabled(uint256 at);
    event PoolBlocked(address indexed pool, bool blocked);
    event BlocksDisabled();

    error NotDeployer();
    error NotMinter();
    error AlreadyInitialized();
    error ZeroAddress();
    error TransfersClosed();
    error PoolRejected();
    error SupplyCap();

    /// @param name_ 代币名称（如 "CatAgent"）
    /// @param symbol_ 代币符号
    /// @param wbnb_ WBNB 地址
    /// @param factory_ PancakeSwap V2 工厂，构造时即创建唯一交易对
    /// @param poolManager_ Pancake Infinity PoolManager（拒收）
    /// @param infinityVault_ Pancake Infinity Vault（拒收）
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
    }

    modifier onlyMinter() {
        if (msg.sender != minter) revert NotMinter();
        _;
    }

    function mint(address to, uint256 amount) external onlyMinter {
        if (totalSupply() + amount > MAX_SUPPLY) revert SupplyCap();
        _mint(to, amount);
    }

    function enableTrading() external onlyMinter {
        if (tradingEnabled) return;
        tradingEnabled = true;
        emit TradingEnabled(block.timestamp);
    }

    function burnFromPair(uint256 amount) external onlyMinter {
        super._update(pair, DEAD, amount);
    }

    function setPoolBlocked(address pool, bool blocked) external onlyMinter {
        blockedPool[pool] = blocked;
        emit PoolBlocked(pool, blocked);
    }

    function disableBlocks() external onlyMinter {
        blocksDisabled = true;
        emit BlocksDisabled();
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

    function _update(address from, address to, uint256 value) internal override {
        if (from == address(0)) {
            super._update(from, to, value);
            return;
        }
        address m = minter;
        if (!tradingEnabled) {
            if (from != m) revert TransfersClosed();
            super._update(from, to, value);
            return;
        }
        if (rejects(to)) revert PoolRejected();
        if (from == m || to == m) {
            super._update(from, to, value);
            return;
        }
        if (from == pair) {
            uint256 tax = (value * BUY_TAX_BPS) / 10_000;
            super._update(from, m, tax);
            super._update(from, to, value - tax);
        } else if (to == pair) {
            uint256 burnt = (value * SELL_BURN_BPS) / 10_000;
            uint256 kept = (value * SELL_KEEP_BPS) / 10_000;
            super._update(from, DEAD, burnt);
            super._update(from, m, kept);
            super._update(from, to, value - burnt - kept);
        } else {
            super._update(from, to, value);
        }
    }
}
