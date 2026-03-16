# Falafel — Autonomous AI Company on Avalanche C-Chain

**Falafel** is an autonomous, perpetual AI company that executes compliant
Real-World Asset (RWA) tokenization, invoice financing, securities
tokenization, and DeFi yield strategies on Avalanche C-Chain.

Governed by $FALAFEL token holders. Employs 11 AI "Rat Agents" — specialized
NFT-based employees, each with an ERC-6551 Token Bound Account (TBA) running
on a persistent Aleph Cloud VM.

## Architecture

| Contract | Purpose |
|---|---|
| `RWAComplianceToken` | ERC-20 RWA token with ERC-3643-style KYC whitelist |
| `AgenticCommerce` | ERC-8183 trustless 4-state job escrow for AI-agent commerce |
| `RatAgents` | ERC-721 NFT registry for 11 Rat Agent employees + ERC-6551 TBAs |

## Tech Stack

- **Smart Contracts**: Solidity ^0.8.24, OpenZeppelin 5.x
- **Build/Test/Deploy**: Foundry (forge, cast, anvil)
- **Target Network**: Avalanche Fuji Testnet (chainId: 43113)
- **Python Orchestrator**: Python 3.11+, web3.py 6.x, Aleph Cloud SDK
- **Company Layer**: Paperclip (`falafel-company.yaml`)

## Quick Start

### Prerequisites

```shell
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash && foundryup

# Install Python dependencies
pip install web3 python-dotenv eth-account aleph-sdk-python
```

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Deploy (Fuji Testnet)

```shell
# 1. Copy and fill environment
cp .env.example .env
# edit .env with real values

# 2. Deploy all Phase 1 contracts
forge script src/scripts/DeployPhase1.s.sol:DeployPhase1 \
  --rpc-url $FUJI_RPC_URL \
  --private-key $DEPLOYER_PRIVATE_KEY \
  --broadcast

# 3. Update .env with deployed addresses, then run orchestrator
python src/python/falafel_core.py --mode setup
```

### Python Orchestrator

```shell
# Full Phase 1 setup (create job + provision Aleph VMs)
python src/python/falafel_core.py --mode setup

# Status summary
python src/python/falafel_core.py --mode status

# Job only
python src/python/falafel_core.py --mode job-only

# Aleph VMs only
python src/python/falafel_core.py --mode aleph-only
```

## The 11 Rat Agents

| ID | Name | Role |
|----|------|------|
| 1 | Compliance Rat | KYC/AML checks and whitelist management |
| 2 | Yield Rat | Trader Joe LP + Aave yield optimization |
| 3 | RWA Issuance Rat | Real-world asset tokenization |
| 4 | Invoice Rat | Invoice financing workflows |
| 5 | Securities Rat | Securities tokenization compliance |
| 6 | DevOps Rat | GCP VM management and CI/CD |
| 7 | Frontend Rat | falafel.work dashboard updates |
| 8 | Orchestrator Rat | Rat team ERC-8183 coordination |
| 9 | Analytics Rat | On-chain metrics and reporting |
| 10 | Revenue Rat | Revenue split tracking and claims |
| 11 | Research Rat | DeFi/RWA trend research |

## Foundry Commands

```shell
forge build        # Compile contracts
forge test         # Run all tests
forge test -v      # Verbose test output
forge snapshot     # Gas snapshots
forge fmt          # Format Solidity files
anvil              # Local Avalanche fork
```
