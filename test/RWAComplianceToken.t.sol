// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// RWAComplianceTokenTest — Foundry tests for RWAComplianceToken.
// Tests compliance whitelist, freeze, pause, mint, burn, and access control.

import {Test, console} from "forge-std/Test.sol";
import {RWAComplianceToken} from "../src/contracts/RWAComplianceToken.sol";

contract RWAComplianceTokenTest is Test {
    RWAComplianceToken token;

    address owner   = address(0x1);
    address alice   = address(0x2);
    address bob     = address(0x3);
    address charlie = address(0x4);

    function setUp() public {
        vm.prank(owner);
        token = new RWAComplianceToken("RWA Test Token", "RWAT", 18, owner);
    }

    // -------------------------------------------------------------------------
    // Whitelist
    // -------------------------------------------------------------------------

    function test_OwnerIsAutoWhitelisted() public view {
        assertTrue(token.isWhitelisted(owner), "owner should be auto-whitelisted");
    }

    function test_AddToWhitelist() public {
        vm.prank(owner);
        token.addToWhitelist(alice);
        assertTrue(token.isWhitelisted(alice));
    }

    function test_AddToWhitelist_RevertAlreadyWhitelisted() public {
        vm.prank(owner);
        token.addToWhitelist(alice);
        vm.prank(owner);
        vm.expectRevert(bytes("RWA: already whitelisted"));
        token.addToWhitelist(alice);
    }

    function test_RemoveFromWhitelist() public {
        vm.prank(owner);
        token.addToWhitelist(alice);
        vm.prank(owner);
        token.removeFromWhitelist(alice);
        assertFalse(token.isWhitelisted(alice));
    }

    function test_RemoveFromWhitelist_RevertNotWhitelisted() public {
        vm.prank(owner);
        vm.expectRevert(bytes("RWA: not whitelisted"));
        token.removeFromWhitelist(alice);
    }

    // -------------------------------------------------------------------------
    // Mint
    // -------------------------------------------------------------------------

    function test_MintCompliant_RevertNonWhitelisted() public {
        vm.prank(owner);
        vm.expectRevert(bytes("RWA: recipient not whitelisted"));
        token.mintCompliant(alice, 1000e18);
    }

    function test_MintCompliant_Success() public {
        vm.prank(owner);
        token.addToWhitelist(alice);
        vm.prank(owner);
        token.mintCompliant(alice, 1000e18);
        assertEq(token.balanceOf(alice), 1000e18);
    }

    // -------------------------------------------------------------------------
    // Transfer
    // -------------------------------------------------------------------------

    function _setupTransfer() internal {
        vm.prank(owner);
        token.addToWhitelist(alice);
        vm.prank(owner);
        token.addToWhitelist(bob);
        vm.prank(owner);
        token.mintCompliant(alice, 1000e18);
    }

    function test_Transfer_SenderNotWhitelisted() public {
        vm.prank(owner);
        token.addToWhitelist(alice);
        vm.prank(owner);
        token.mintCompliant(alice, 500e18);
        // charlie not whitelisted — add alice, remove to simulate unwhitelisted sender
        vm.prank(owner);
        token.removeFromWhitelist(alice);
        vm.prank(alice);
        vm.expectRevert(bytes("RWA: sender not whitelisted"));
        token.transfer(bob, 100e18);
    }

    function test_Transfer_RecipientNotWhitelisted() public {
        _setupTransfer();
        // Remove bob from whitelist
        vm.prank(owner);
        token.removeFromWhitelist(bob);
        vm.prank(alice);
        vm.expectRevert(bytes("RWA: recipient not whitelisted"));
        token.transfer(bob, 100e18);
    }

    function test_Transfer_SenderFrozen() public {
        _setupTransfer();
        vm.prank(owner);
        token.setFrozen(alice, true);
        vm.prank(alice);
        vm.expectRevert(bytes("RWA: sender is frozen"));
        token.transfer(bob, 100e18);
    }

    function test_Transfer_RecipientFrozen() public {
        _setupTransfer();
        vm.prank(owner);
        token.setFrozen(bob, true);
        vm.prank(alice);
        vm.expectRevert(bytes("RWA: recipient is frozen"));
        token.transfer(bob, 100e18);
    }

    function test_Transfer_Success() public {
        _setupTransfer();
        vm.prank(alice);
        token.transfer(bob, 200e18);
        assertEq(token.balanceOf(alice), 800e18);
        assertEq(token.balanceOf(bob), 200e18);
    }

    // -------------------------------------------------------------------------
    // Pause
    // -------------------------------------------------------------------------

    function test_Pause_BlocksTransfers() public {
        _setupTransfer();
        vm.prank(owner);
        token.pause();
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 100e18);
    }

    function test_Unpause_ResumesTransfers() public {
        _setupTransfer();
        vm.prank(owner);
        token.pause();
        vm.prank(owner);
        token.unpause();
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    // -------------------------------------------------------------------------
    // ForceBurn
    // -------------------------------------------------------------------------

    function test_ForceBurn() public {
        vm.prank(owner);
        token.addToWhitelist(alice);
        vm.prank(owner);
        token.mintCompliant(alice, 1000e18);
        vm.prank(owner);
        token.forceBurn(alice, 300e18);
        assertEq(token.balanceOf(alice), 700e18);
    }

    // -------------------------------------------------------------------------
    // Access Control
    // -------------------------------------------------------------------------

    function test_NonOwnerCannotAddWhitelist() public {
        vm.prank(alice);
        vm.expectRevert();
        token.addToWhitelist(bob);
    }

    function test_NonOwnerCannotMint() public {
        vm.prank(owner);
        token.addToWhitelist(alice);
        vm.prank(alice);
        vm.expectRevert();
        token.mintCompliant(alice, 100e18);
    }

    function test_NonOwnerCannotPause() public {
        vm.prank(alice);
        vm.expectRevert();
        token.pause();
    }

    // -------------------------------------------------------------------------
    // Compliance registry
    // -------------------------------------------------------------------------

    function test_SetComplianceRegistry() public {
        address registry = address(0xABCD);
        vm.prank(owner);
        token.setComplianceRegistry(registry);
        assertEq(token.complianceRegistry(), registry);
    }

    // -------------------------------------------------------------------------
    // Fuzz
    // -------------------------------------------------------------------------

    function testFuzz_MintCompliant(uint256 amount) public {
        vm.assume(amount > 0 && amount <= type(uint128).max);
        vm.prank(owner);
        token.addToWhitelist(alice);
        vm.prank(owner);
        token.mintCompliant(alice, amount);
        assertEq(token.balanceOf(alice), amount);
    }
}
