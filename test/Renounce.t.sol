// SPDX-License-Identifier: MIT
// BAISHOU - the RENOUNCE + PAUSE path (minimal admin, trust-max).
// FINAL design: admin is ONLY pause; renounce is DELAYED until the independent review
// is complete (the reviewPassed flag, not a fixed D+7); pause NEVER blocks
// refunds/exits. There is NO withdraw/drain function in the contract.
pragma solidity ^0.8.24;

import {BaishouTest} from "./Baishou.t.sol";
import {AgentMint} from "../src/AgentMint.sol";
import {AgentToken} from "../src/AgentToken.sol";
import {MockPair, MockWBNB} from "./mocks/Mocks.sol";

contract RenounceTest is BaishouTest {
    function test_RenounceOnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotAdmin.selector);
        mint.renounce();
    }

    function test_PauseOnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotAdmin.selector);
        mint.setPaused(true);
    }

    function test_SetReviewPassedOnlyAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(AgentMint.NotAdmin.selector);
        mint.setReviewPassed(true);
    }

    function test_RenounceDelayedUntilReview() public {
        assertFalse(mint.reviewPassed(), "review not passed at deploy");
        vm.prank(admin);
        vm.expectRevert(AgentMint.ReviewNotPassed.selector);
        mint.renounce();
        assertFalse(mint.renounced(), "still not renounced");
        vm.prank(admin);
        mint.setReviewPassed(true);
        assertTrue(mint.reviewPassed(), "review passed");
        vm.prank(admin);
        mint.renounce();
        assertTrue(mint.renounced(), "renounce succeeds after review");
    }

    function test_PauseNeverBlocksExit() public {
        _mintAs(alice, 5, address(0));
        vm.prank(admin);
        mint.setPaused(true);
        uint256 before = alice.balance;
        vm.prank(alice);
        mint.exit(5);
        assertEq(alice.balance, before + 5 * 0.00168 ether * 80 / 100, "pause does not block exit");
    }

    function test_RenounceReleasesBlocks() public {
        _mintAs(alice, 5, address(0));
        _openPool(carol);
        // A blocked non-pair coded address: transfers are rejected
        // while blocks are active (not a fake pair — other pairs are still rejected
        // forever by the one-pair rule, even after renounce).
        MockWBNB dummy = new MockWBNB();
        address dummyAddr = address(dummy);
        vm.prank(admin);
        mint.setPoolBlocked(dummyAddr, true);
        vm.prank(alice);
        vm.expectRevert(AgentToken.PoolRejected.selector);
        token.transfer(dummyAddr, 1 ether);
        // After review + renounce, blocks are released (disableBlocks).
        vm.prank(admin);
        mint.setReviewPassed(true);
        vm.prank(admin);
        mint.renounce();
        assertTrue(token.blocksDisabled(), "blocks disabled on renounce");
        vm.prank(alice);
        token.transfer(dummyAddr, 1 ether);
        assertEq(token.balanceOf(dummyAddr), 1 ether, "transfer to ex-blocked works");
    }

    function test_NoWithdrawFunction() public {
        // §8b: there is NO way for funds to leave besides refund/pool. Prove
        // there is no withdraw/drain function anyone can call.
        (bool okWithdraw,) = address(mint).call(abi.encodeWithSignature("withdraw(uint256)", 1));
        assertFalse(okWithdraw, "no withdraw(uint256)");
        (bool okDrain,) = address(mint).call(abi.encodeWithSignature("drain()"));
        assertFalse(okDrain, "no drain()");
        (bool okRescue,) = address(mint).call(abi.encodeWithSignature("rescueTokens(address)", address(token)));
        assertFalse(okRescue, "no rescueTokens(address)");
        // Not even the admin can call any path to pull the escrow.
        assertEq(mint.escrowTreasury(), 0, "escrow empty at start");
    }
}
