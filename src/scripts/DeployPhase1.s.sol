// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// DeployPhase1 — Foundry deployment script for Falafel Phase 1.
// Deploys RWAComplianceToken, AgenticCommerce, and RatAgents in a single
// broadcast, mints all 11 rat NFTs, provisions all 11 ERC-6551 TBAs, and
// logs every deployed address to the console.

import {Script, console} from "forge-std/Script.sol";
import {RWAComplianceToken} from "../contracts/RWAComplianceToken.sol";
import {AgenticCommerce} from "../contracts/AgenticCommerce.sol";
import {RatAgents} from "../contracts/RatAgents.sol";

contract DeployPhase1 is Script {
    function run() external {
        // -----------------------------------------------------------------
        // Load configuration from environment
        // -----------------------------------------------------------------
        uint256 deployerKey  = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address treasury     = vm.envAddress("TREASURY_ADDRESS");
        address tbaImpl      = vm.envAddress("TBA_IMPL_ADDRESS");

        string memory rwaName     = vm.envString("RWA_TOKEN_NAME");
        string memory rwaSymbol   = vm.envString("RWA_TOKEN_SYMBOL");
        string memory baseMeta    = vm.envString("BASE_METADATA_URI");
        uint256 feeBps            = vm.envUint("AGENTIC_COMMERCE_FEE_BPS");

        address deployer = vm.addr(deployerKey);

        // -----------------------------------------------------------------
        // Validation
        // -----------------------------------------------------------------
        require(treasury != address(0), "Deploy: zero treasury");
        require(tbaImpl  != address(0), "Deploy: zero tbaImpl");
        require(feeBps   <= 500,        "Deploy: feeBps > 500");

        console.log("=== Falafel Phase 1 Deployment ===");
        console.log("Deployer  :", deployer);
        console.log("Treasury  :", treasury);
        console.log("TBA Impl  :", tbaImpl);
        console.log("Fee (bps) :", feeBps);

        // -----------------------------------------------------------------
        // Broadcast
        // -----------------------------------------------------------------
        vm.startBroadcast(deployerKey);

        // 1. Deploy RWA compliance token (18 decimals, deployer as owner)
        RWAComplianceToken rwaToken = new RWAComplianceToken(
            rwaName,
            rwaSymbol,
            18,
            deployer
        );

        // 2. Deploy ERC-8183 agentic commerce escrow
        AgenticCommerce agenticCommerce = new AgenticCommerce(deployer, feeBps);

        // 3. Deploy rat agent NFT registry
        RatAgents ratAgents = new RatAgents(deployer, tbaImpl);

        // 4. Mint all 11 rat NFTs to the treasury
        ratAgents.mintAllRats(treasury, baseMeta);

        // 5. Provision ERC-6551 TBAs for all 11 rats
        ratAgents.provisionTBAs();

        vm.stopBroadcast();

        // -----------------------------------------------------------------
        // Deployment summary
        // -----------------------------------------------------------------
        console.log("");
        console.log("=== Deployed Addresses ===");
        console.log("RWAComplianceToken :", address(rwaToken));
        console.log("AgenticCommerce    :", address(agenticCommerce));
        console.log("RatAgents          :", address(ratAgents));

        console.log("");
        console.log("=== Rat Agent TBAs ===");
        address[11] memory tbas = ratAgents.allRatTBAs();
        for (uint256 i = 0; i < 11; i++) {
            console.log(string(abi.encodePacked("  Rat #", _toString(i + 1), " TBA:")), tbas[i]);
        }

        console.log("");
        console.log("=== Next Steps ===");
        console.log("1. Copy deployed addresses to .env");
        console.log("   AGENTIC_COMMERCE_ADDRESS=", address(agenticCommerce));
        console.log("   RAT_AGENTS_ADDRESS=", address(ratAgents));
        console.log("2. Run: python src/python/falafel_core.py --mode setup");
    }

    // Simple uint-to-string helper for logging
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits--;
            buffer[digits] = bytes1(uint8(48 + (value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}
