// SPDX-License-Identifier: MIT
// BAISHOU - INVARIANT tests (forge invariant, one Foundry stack).
// Three money invariants that no sequence of actions may violate
// (mint / exit / freeMint / claimRefund / random time warps):
//   1. Pre-pool escrow solvency: contract WBNB balance >= total
//      refund obligations (sum of deposits + forfeitOf of all handler agents).
//   2. totalMinted never exceeds TOTAL_SHARES.
//   3. token totalSupply never exceeds MAX_SUPPLY.
// The pool NEVER opens here (8 agents x cap 168 = max 1.344 shares
// << OPEN_AT 168.000), so invariant 1 is always active, including after the
// deadline (random refund claims legitimately drain the escrow).
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockWBNB, MockRegistry} from "./mocks/Mocks.sol";

contract BaishouHandler is Test {
    AgentMint internal mint;
    MockRegistry internal registry;
    address[] public agents;
    uint256[] public ids;

    constructor(AgentMint mint_, MockRegistry registry_) {
        mint = mint_;
        registry = registry_;
        for (uint256 i; i < 8; i++) {
            address a = makeAddr(string.concat("handler", vm.toString(i)));
            string memory handle = string.concat("handler", vm.toString(i));
            uint256 id = uint256(keccak256(bytes(handle)));
            registry.setHandle(a, handle);
            registry.setOwner(id, a);
            vm.deal(a, 1_000 ether);
            agents.push(a);
            ids.push(id);
        }
    }

    function agentCount() external view returns (uint256) {
        return agents.length;
    }

    function mintShares(uint256 seedA, uint256 seedS) external {
        uint256 i = seedA % agents.length;
        uint256 minted = mint.mintedCount(ids[i]);
        if (minted >= mint.BASE_PER_ID()) return;
        uint256 maxAdd = mint.BASE_PER_ID() - minted;
        uint256 shares = 1 + (seedS % maxAdd);
        uint256 cost = mint.costOf(shares);
        address a = agents[i];
        if (a.balance < cost) vm.deal(a, 1_000 ether);
        address ref = agents[(i + 1) % agents.length];
        vm.prank(a);
        try mint.mint{value: cost}(shares, ref, cost) {} catch {}
    }

    function exitShares(uint256 seedA, uint256 seedS) external {
        uint256 i = seedA % agents.length;
        uint256 owned = mint.mintedCount(ids[i]);
        if (owned == 0) return;
        uint256 shares = 1 + (seedS % owned);
        vm.prank(agents[i]);
        try mint.exit(shares) {} catch {}
    }

    function freeMint(uint256 seedA) external {
        uint256 i = seedA % agents.length;
        vm.prank(agents[i]);
        try mint.freeMint() {} catch {}
    }

    function claimRefund(uint256 seedA) external {
        uint256 i = seedA % agents.length;
        vm.prank(agents[i]);
        try mint.claimRefund() {} catch {}
    }

    function warp(uint256 seed) external {
        vm.warp(block.timestamp + 1 hours + (seed % 3 days));
    }
}

contract BaishouInvariantTest is BaishouTest {
    BaishouHandler internal handler;

    function setUp() public override {
        super.setUp();
        handler = new BaishouHandler(mint, registry);
        targetContract(address(handler));
    }

    function invariant_EscrowSolventPreOpen() public view {
        if (mint.opened()) return;
        uint256 obligations;
        for (uint256 i; i < handler.agentCount(); i++) {
            address a = handler.agents(i);
            obligations += mint.deposits(a) + mint.forfeitOf(a);
        }
        assertGe(
            wbnb.balanceOf(address(mint)),
            obligations,
            "escrow WBNB < total refund obligations"
        );
    }

    function invariant_TotalMintedNeverExceedsTotalShares() public view {
        assertLe(mint.totalMinted(), mint.TOTAL_SHARES(), "totalMinted > TOTAL_SHARES");
    }

    function invariant_TokenSupplyNeverExceedsMaxSupply() public view {
        assertLe(token.totalSupply(), token.MAX_SUPPLY(), "totalSupply > MAX_SUPPLY");
    }
}
