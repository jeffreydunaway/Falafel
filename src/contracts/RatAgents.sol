// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// RatAgents — Mints exactly 11 Rat Agent NFTs (ERC-721). Each rat is a
// specialized AI employee of Falafel. Each NFT gets an ERC-6551 Token Bound
// Account (TBA) — a smart-contract wallet — provisioned via the canonical
// ERC-6551 registry at 0x000000006551c19487814612e58FE06813775758.
//
// OZ 5.x: inherits ERC721URIStorage + Ownable. Uses _update() hook (NOT
// _beforeTokenTransfer which was removed in OZ 5.x).

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721URIStorage} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// Minimal interface for the canonical ERC-6551 registry
interface IERC6551Registry {
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address);

    function account(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external view returns (address);
}

contract RatAgents is ERC721URIStorage, Ownable {
    using Strings for uint256;

    // -------------------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------------------

    uint256 public constant MAX_SUPPLY = 11;

    /// @notice Canonical ERC-6551 registry — same address on all EVM chains.
    address public constant ERC6551_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    // -------------------------------------------------------------------------
    // Events
    // -------------------------------------------------------------------------

    event RatMinted(uint256 indexed tokenId, address indexed to, string name);
    event TBAProvisioned(uint256 indexed tokenId, address indexed tba);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    address public tbaImplementation;
    mapping(uint256 => address) private _ratTBA;
    bool public allRatsMinted;
    bool public allTBAsProvisioned;

    // Index 0 unused; indices 1–11 hold rat data
    string[12] private RAT_NAMES;
    string[12] private RAT_ROLES;

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner_, address tbaImplementation_)
        ERC721("Falafel Rat Agents", "FRAT")
        Ownable(initialOwner_)
    {
        require(initialOwner_ != address(0), "RA: zero owner");
        require(tbaImplementation_ != address(0), "RA: zero tbaImpl");

        tbaImplementation = tbaImplementation_;

        // Populate rat metadata arrays (index 0 left empty)
        RAT_NAMES[1]  = "Compliance Rat";
        RAT_NAMES[2]  = "Yield Rat";
        RAT_NAMES[3]  = "RWA Issuance Rat";
        RAT_NAMES[4]  = "Invoice Rat";
        RAT_NAMES[5]  = "Securities Rat";
        RAT_NAMES[6]  = "DevOps Rat";
        RAT_NAMES[7]  = "Frontend Rat";
        RAT_NAMES[8]  = "Orchestrator Rat";
        RAT_NAMES[9]  = "Analytics Rat";
        RAT_NAMES[10] = "Revenue Rat";
        RAT_NAMES[11] = "Research Rat";

        RAT_ROLES[1]  = "KYC/AML checks and whitelist management";
        RAT_ROLES[2]  = "Trader Joe LP + Aave yield optimization";
        RAT_ROLES[3]  = "Real-world asset tokenization";
        RAT_ROLES[4]  = "Invoice financing workflows";
        RAT_ROLES[5]  = "Securities tokenization compliance";
        RAT_ROLES[6]  = "GCP VM management and CI/CD";
        RAT_ROLES[7]  = "falafel.work dashboard updates";
        RAT_ROLES[8]  = "Rat team ERC-8183 coordination";
        RAT_ROLES[9]  = "On-chain metrics and reporting";
        RAT_ROLES[10] = "Revenue split tracking and claims";
        RAT_ROLES[11] = "DeFi/RWA trend research";
    }

    // -------------------------------------------------------------------------
    // Mint
    // -------------------------------------------------------------------------

    /// @notice Mint all 11 Rat Agent NFTs to `recipient` in a single transaction.
    ///         Can only be called once (guarded by `allRatsMinted`).
    function mintAllRats(address recipient, string calldata baseMetadataURI)
        external
        onlyOwner
    {
        require(!allRatsMinted, "RA: already minted");

        for (uint256 i = 1; i <= MAX_SUPPLY; i++) {
            _safeMint(recipient, i);
            // Construct URI: baseMetadataURI + tokenId + ".json"
            _setTokenURI(i, string(abi.encodePacked(baseMetadataURI, i.toString(), ".json")));
            emit RatMinted(i, recipient, RAT_NAMES[i]);
        }

        allRatsMinted = true;
    }

    // -------------------------------------------------------------------------
    // ERC-6551 TBA Provisioning
    // -------------------------------------------------------------------------

    /// @notice Deploy ERC-6551 TBAs for all 11 rats using the canonical registry.
    ///         Requires rats to be minted first. Can only be called once.
    function provisionTBAs() external onlyOwner {
        require(allRatsMinted, "RA: rats not minted");
        require(!allTBAsProvisioned, "RA: TBAs already provisioned");

        IERC6551Registry registry = IERC6551Registry(ERC6551_REGISTRY);

        for (uint256 i = 1; i <= MAX_SUPPLY; i++) {
            bytes32 salt = _ratSalt(i);
            address tba = registry.createAccount(
                tbaImplementation,
                salt,
                block.chainid,
                address(this),
                i
            );
            _ratTBA[i] = tba;
            emit TBAProvisioned(i, tba);
        }

        allTBAsProvisioned = true;
    }

    /// @notice Compute (read-only) the deterministic TBA address for rat `tokenId`.
    function computeTBA(uint256 tokenId) external view returns (address) {
        require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "RA: invalid tokenId");
        return IERC6551Registry(ERC6551_REGISTRY).account(
            tbaImplementation,
            _ratSalt(tokenId),
            block.chainid,
            address(this),
            tokenId
        );
    }

    // -------------------------------------------------------------------------
    // Metadata management
    // -------------------------------------------------------------------------

    /// @notice Update a rat's metadata URI after Aleph/Pinata upload.
    function setRatMetadata(uint256 tokenId, string calldata uri) external onlyOwner {
        require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "RA: invalid tokenId");
        _setTokenURI(tokenId, uri);
    }

    /// @notice Update the TBA implementation address (before provisioning).
    function setTBAImplementation(address newImpl) external onlyOwner {
        require(newImpl != address(0), "RA: zero impl");
        tbaImplementation = newImpl;
    }

    // -------------------------------------------------------------------------
    // View functions
    // -------------------------------------------------------------------------

    function ratTBA(uint256 tokenId) external view returns (address) {
        return _ratTBA[tokenId];
    }

    function ratName(uint256 tokenId) external view returns (string memory) {
        require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "RA: invalid tokenId");
        return RAT_NAMES[tokenId];
    }

    function ratRole(uint256 tokenId) external view returns (string memory) {
        require(tokenId >= 1 && tokenId <= MAX_SUPPLY, "RA: invalid tokenId");
        return RAT_ROLES[tokenId];
    }

    function allRatTBAs() external view returns (address[11] memory tbas) {
        for (uint256 i = 0; i < 11; i++) {
            tbas[i] = _ratTBA[i + 1];
        }
    }

    function totalSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }

    // -------------------------------------------------------------------------
    // OZ 5.x overrides
    // -------------------------------------------------------------------------

    /// @dev ERC721URIStorage.supportsInterface extends ERC721 with ERC-4906.
    ///      We must explicitly override to resolve the inheritance chain.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Deterministic salt for ERC-6551 TBA: keccak256("falafel-rat-" + tokenId)
    function _ratSalt(uint256 tokenId) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("falafel-rat-", tokenId));
    }
}
