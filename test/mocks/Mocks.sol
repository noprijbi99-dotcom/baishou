// SPDX-License-Identifier: MIT
// Test mocks for the BAISHOU fork base. These are NOT production code:
// they stand in for WBNB, the Pancake factory/pair and the Binance Agent ID
// registry (0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F) on a local Anvil chain.
//
// Agent ID derivation in AgentMint._agent():
//   id = uint256(keccak256(bytes(handleOf(user)))); ok = ownerOf(id) == user
// so the mock registry must be seeded with BOTH the handle AND the owner:
//   registry.setHandle(alice, "alice");
//   registry.setOwner(uint256(keccak256(bytes("alice"))), alice);
pragma solidity ^0.8.24;

import {IERC20} from "../../src/vendor/openzeppelin/token/ERC20/IERC20.sol";

/// @notice Minimal ERC20 + WBNB deposit/withdraw, just enough for AgentMint.
contract MockWBNB {
    string public name = "Wrapped BNB";
    string public symbol = "WBNB";
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "bnb send failed");
        emit Transfer(msg.sender, address(0), amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "insufficient");
        require(allowance[from][msg.sender] >= amount, "allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }

    receive() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }
}

/// @notice Minimal Pancake pair: sorted token0/token1, settable reserves,
/// mint() returns dummy liquidity (credited to `to`, e.g. DEAD),
/// swap() pays out from the pair's real token balances and re-syncs reserves
/// from actual balances (enough to make swapTax() move real WBNB in tests).
contract MockPair {
    address public token0;
    address public token1;
    uint112 public reserve0;
    uint112 public reserve1;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;

    constructor(address a, address b) {
        (token0, token1) = a < b ? (a, b) : (b, a);
    }

    function setReserves(uint112 r0, uint112 r1) external {
        reserve0 = r0;
        reserve1 = r1;
    }

    function getReserves() external view returns (uint112, uint112, uint32) {
        return (reserve0, reserve1, uint32(block.timestamp));
    }

    function price0CumulativeLast() external pure returns (uint256) {
        return 0;
    }

    function price1CumulativeLast() external pure returns (uint256) {
        return 0;
    }

    function swap(uint256 out0, uint256 out1, address to, bytes calldata) external {
        if (out0 > 0) {
            require(IERC20(token0).transfer(to, out0), "payout0 failed");
        }
        if (out1 > 0) {
            require(IERC20(token1).transfer(to, out1), "payout1 failed");
        }
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
    }

    function mint(address to) external returns (uint256 liquidity) {
        liquidity = 1000;
        totalSupply += liquidity;
        balanceOf[to] += liquidity;
        return liquidity;
    }

    function sync() external {
        reserve0 = uint112(IERC20(token0).balanceOf(address(this)));
        reserve1 = uint112(IERC20(token1).balanceOf(address(this)));
    }
}

/// @notice Minimal Pancake factory: createPair deploys a MockPair.
contract MockFactory {
    mapping(address => mapping(address => address)) public getPair;

    function createPair(address a, address b) external returns (address) {
        require(getPair[a][b] == address(0), "pair exists");
        MockPair pair = new MockPair(a, b);
        getPair[a][b] = address(pair);
        getPair[b][a] = address(pair);
        return address(pair);
    }
}

/// @notice Minimal Agent ID registry mock (IAgentHandles: handleOf + ownerOf).
contract MockRegistry {
    mapping(address => string) private _handles;
    mapping(uint256 => address) private _owners;

    function setHandle(address user, string calldata handle) external {
        _handles[user] = handle;
    }

    function setOwner(uint256 id, address user) external {
        _owners[id] = user;
    }

    function handleOf(address user) external view returns (string memory) {
        return _handles[user];
    }

    function ownerOf(uint256 id) external view returns (address) {
        return _owners[id];
    }
}
