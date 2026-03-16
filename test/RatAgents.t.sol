// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// RatAgentsTest — Foundry tests for the RatAgents ERC-721 contract.
// Tests minting, metadata, TBA provisioning, access control, and view functions.

import {Test, console} from "forge-std/Test.sol";
import {RatAgents} from "../src/contracts/RatAgents.sol";

contract RatAgentsTest is Test {
    RatAgents rats;

    address owner   = address(0x1);
    address treasury = address(0x2);
    address stranger = address(0x3);
    address tbaImpl  = address(0x999); // Mock TBA implementation

    string constant BASE_URI = "ipfs://QmRatMetadata/";

    function setUp() public {
        vm.prank(owner);
        rats = new RatAgents(owner, tbaImpl);
    }

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    function test_Constructor_Name() public view {
        assertEq(rats.name(), "Falafel Rat Agents");
        assertEq(rats.symbol(), "FRAT");
    }

    function test_Constructor_MaxSupply() public view {
        assertEq(rats.MAX_SUPPLY(), 11);
        assertEq(rats.totalSupply(), 11);
    }

    function test_Constructor_TBAImplementation() public view {
        assertEq(rats.tbaImplementation(), tbaImpl);
    }

    function test_Constructor_RevertZeroOwner() public {
        vm.expectRevert();
        new RatAgents(address(0), tbaImpl);
    }

    function test_Constructor_RevertZeroTBAImpl() public {
        vm.expectRevert(bytes("RA: zero tbaImpl"));
        new RatAgents(owner, address(0));
    }

    // -------------------------------------------------------------------------
    // Rat names and roles
    // -------------------------------------------------------------------------

    function test_RatNames() public view {
        assertEq(rats.ratName(1),  "Compliance Rat");
        assertEq(rats.ratName(2),  "Yield Rat");
        assertEq(rats.ratName(3),  "RWA Issuance Rat");
        assertEq(rats.ratName(4),  "Invoice Rat");
        assertEq(rats.ratName(5),  "Securities Rat");
        assertEq(rats.ratName(6),  "DevOps Rat");
        assertEq(rats.ratName(7),  "Frontend Rat");
        assertEq(rats.ratName(8),  "Orchestrator Rat");
        assertEq(rats.ratName(9),  "Analytics Rat");
        assertEq(rats.ratName(10), "Revenue Rat");
        assertEq(rats.ratName(11), "Research Rat");
    }

    function test_RatRoles() public view {
        assertEq(rats.ratRole(1),  "KYC/AML checks and whitelist management");
        assertEq(rats.ratRole(8),  "Rat team ERC-8183 coordination");
        assertEq(rats.ratRole(11), "DeFi/RWA trend research");
    }

    function test_RatName_RevertInvalidId() public {
        vm.expectRevert(bytes("RA: invalid tokenId"));
        rats.ratName(0);
    }

    function test_RatName_RevertTooHighId() public {
        vm.expectRevert(bytes("RA: invalid tokenId"));
        rats.ratName(12);
    }

    // -------------------------------------------------------------------------
    // mintAllRats
    // -------------------------------------------------------------------------

    function test_MintAllRats() public {
        vm.prank(owner);
        rats.mintAllRats(treasury, BASE_URI);

        assertTrue(rats.allRatsMinted());
        assertEq(rats.balanceOf(treasury), 11);

        for (uint256 i = 1; i <= 11; i++) {
            assertEq(rats.ownerOf(i), treasury);
        }
    }

    function test_MintAllRats_TokenURIs() public {
        vm.prank(owner);
        rats.mintAllRats(treasury, BASE_URI);

        assertEq(rats.tokenURI(1), string(abi.encodePacked(BASE_URI, "1.json")));
        assertEq(rats.tokenURI(11), string(abi.encodePacked(BASE_URI, "11.json")));
    }

    function test_MintAllRats_RevertTwice() public {
        vm.prank(owner);
        rats.mintAllRats(treasury, BASE_URI);
        vm.prank(owner);
        vm.expectRevert(bytes("RA: already minted"));
        rats.mintAllRats(treasury, BASE_URI);
    }

    function test_MintAllRats_RevertNonOwner() public {
        vm.prank(stranger);
        vm.expectRevert();
        rats.mintAllRats(treasury, BASE_URI);
    }

    // -------------------------------------------------------------------------
    // setRatMetadata
    // -------------------------------------------------------------------------

    function test_SetRatMetadata() public {
        vm.prank(owner);
        rats.mintAllRats(treasury, BASE_URI);
        vm.prank(owner);
        rats.setRatMetadata(1, "ipfs://new-uri/1.json");
        assertEq(rats.tokenURI(1), "ipfs://new-uri/1.json");
    }

    // -------------------------------------------------------------------------
    // setTBAImplementation
    // -------------------------------------------------------------------------

    function test_SetTBAImplementation() public {
        address newImpl = address(0xABC);
        vm.prank(owner);
        rats.setTBAImplementation(newImpl);
        assertEq(rats.tbaImplementation(), newImpl);
    }

    function test_SetTBAImplementation_RevertZero() public {
        vm.prank(owner);
        vm.expectRevert(bytes("RA: zero impl"));
        rats.setTBAImplementation(address(0));
    }

    // -------------------------------------------------------------------------
    // provisionTBAs (mocked — canonical registry not deployed in test env)
    // -------------------------------------------------------------------------

    function test_ProvisionTBAs_RevertNotMinted() public {
        vm.prank(owner);
        vm.expectRevert(bytes("RA: rats not minted"));
        rats.provisionTBAs();
    }

    // Note: Full provisionTBAs() test requires deploying a mock ERC-6551 registry.
    // The canonical registry is not available in the default forge test environment.
    // Integration tests against Fuji use the real registry.

    // -------------------------------------------------------------------------
    // allRatTBAs — returns zeros before provisioning
    // -------------------------------------------------------------------------

    function test_AllRatTBAs_BeforeProvisioning() public view {
        address[11] memory tbas = rats.allRatTBAs();
        for (uint256 i = 0; i < 11; i++) {
            assertEq(tbas[i], address(0));
        }
    }

    // -------------------------------------------------------------------------
    // supportsInterface
    // -------------------------------------------------------------------------

    function test_SupportsERC721Interface() public view {
        assertTrue(rats.supportsInterface(0x80ac58cd)); // ERC-721
    }

    function test_SupportsERC721MetadataInterface() public view {
        assertTrue(rats.supportsInterface(0x5b5e139f)); // ERC-721 Metadata
    }
}
