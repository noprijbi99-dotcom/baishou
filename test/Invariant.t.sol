// SPDX-License-Identifier: MIT
// BAISHOU - INVARIANT tests (forge invariant, satu stack Foundry).
// Tiga invarian uang yang tidak boleh dilanggar oleh urutan aksi apa pun
// (mint / exit / freeMint / claimRefund / warp waktu secara acak):
//   1. Solvabilitas escrow pra-pool: saldo WBNB kontrak >= total
//      kewajiban refund (sum deposits + forfeitOf semua agen handler).
//   2. totalMinted tidak pernah melebihi TOTAL_SHARES.
//   3. totalSupply token tidak pernah melebihi MAX_SUPPLY.
// Pool TIDAK pernah buka di sini (8 agen x cap 168 = maks 1.344 share
// << OPEN_AT 168.000), jadi invarian 1 selalu aktif, termasuk sesudah
// deadline (klaim refund acak ikut menguras escrow secara sah).
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
            "escrow WBNB < total kewajiban refund"
        );
    }

    function invariant_TotalMintedNeverExceedsTotalShares() public view {
        assertLe(mint.totalMinted(), mint.TOTAL_SHARES(), "totalMinted > TOTAL_SHARES");
    }

    function invariant_TokenSupplyNeverExceedsMaxSupply() public view {
        assertLe(token.totalSupply(), token.MAX_SUPPLY(), "totalSupply > MAX_SUPPLY");
    }
}
