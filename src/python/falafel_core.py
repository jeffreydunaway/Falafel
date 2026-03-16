#!/usr/bin/env python3
"""
falafel_core.py — Phase 1 Python Orchestrator for the Falafel AI Company.

Connects to Avalanche Fuji C-Chain, creates and funds the first ERC-8183
agentic-commerce job, and provisions 11 persistent Aleph Cloud VMs (one
per Rat Agent).

CLI:
    python falafel_core.py --mode [setup|status|job-only|aleph-only]

Modes:
    setup       Full Phase 1: create ERC-8183 job + provision all Aleph VMs
    status      Read chain state + .rat_state.json and print summary table
    job-only    Only create and fund the first ERC-8183 job
    aleph-only  Only provision Aleph Cloud VMs
"""

import argparse
import asyncio
import json
import os
import time
from pathlib import Path

from dotenv import load_dotenv
from eth_account import Account
from web3 import Web3
from web3.middleware import ExtraDataToPOAMiddleware

# ---------------------------------------------------------------------------
# Load .env
# ---------------------------------------------------------------------------
load_dotenv()

# ---------------------------------------------------------------------------
# Rat definitions — 11 AI employees of Falafel
# ---------------------------------------------------------------------------
RAT_DEFS = [
    {"id": 1,  "name": "Compliance Rat",    "role": "KYC/AML and whitelist management"},
    {"id": 2,  "name": "Yield Rat",         "role": "Trader Joe LP + Aave yield"},
    {"id": 3,  "name": "RWA Issuance Rat",  "role": "Real-world asset tokenization"},
    {"id": 4,  "name": "Invoice Rat",       "role": "Invoice financing workflows"},
    {"id": 5,  "name": "Securities Rat",    "role": "Securities tokenization compliance"},
    {"id": 6,  "name": "DevOps Rat",        "role": "GCP VM and deployment management"},
    {"id": 7,  "name": "Frontend Rat",      "role": "falafel.work dashboard updates"},
    {"id": 8,  "name": "Orchestrator Rat",  "role": "Rat team ERC-8183 coordination"},
    {"id": 9,  "name": "Analytics Rat",     "role": "On-chain metrics and reporting"},
    {"id": 10, "name": "Revenue Rat",       "role": "Revenue split tracking and claims"},
    {"id": 11, "name": "Research Rat",      "role": "DeFi/RWA trend research"},
]

# ---------------------------------------------------------------------------
# Minimal ABIs
# ---------------------------------------------------------------------------
AGENTIC_COMMERCE_ABI = [
    {
        "name": "createJob",
        "type": "function",
        "stateMutability": "nonpayable",
        "inputs": [
            {"name": "worker_",      "type": "address"},
            {"name": "evaluator_",   "type": "address"},
            {"name": "deadline_",    "type": "uint256"},
            {"name": "metadataURI_", "type": "string"},
        ],
        "outputs": [{"name": "jobId", "type": "uint256"}],
    },
    {
        "name": "fundJob",
        "type": "function",
        "stateMutability": "payable",
        "inputs": [{"name": "jobId", "type": "uint256"}],
        "outputs": [],
    },
    {
        "name": "getJob",
        "type": "function",
        "stateMutability": "view",
        "inputs": [{"name": "jobId", "type": "uint256"}],
        "outputs": [
            {
                "name": "",
                "type": "tuple",
                "components": [
                    {"name": "id",              "type": "uint256"},
                    {"name": "client",          "type": "address"},
                    {"name": "worker",          "type": "address"},
                    {"name": "evaluator",       "type": "address"},
                    {"name": "payment",         "type": "uint256"},
                    {"name": "deadline",        "type": "uint256"},
                    {"name": "state",           "type": "uint8"},
                    {"name": "deliverableHash", "type": "bytes32"},
                    {"name": "metadataURI",     "type": "string"},
                    {"name": "workerWon",       "type": "bool"},
                ],
            }
        ],
    },
    {
        "name": "nextJobId",
        "type": "function",
        "stateMutability": "view",
        "inputs": [],
        "outputs": [{"name": "", "type": "uint256"}],
    },
]

JOB_STATE_NAMES = {0: "Open", 1: "Funded", 2: "Submitted", 3: "Terminal"}

# ---------------------------------------------------------------------------
# State file
# ---------------------------------------------------------------------------
STATE_FILE = Path(".rat_state.json")


def load_state() -> dict:
    """Load persisted state from .rat_state.json; return empty structure if absent."""
    if STATE_FILE.exists():
        with STATE_FILE.open() as f:
            return json.load(f)
    return {"jobs": {}, "rat_vms": {}}


def save_state(state: dict) -> None:
    """Persist state to .rat_state.json."""
    with STATE_FILE.open("w") as f:
        json.dump(state, f, indent=2)
    print(f"[state] Saved to {STATE_FILE}")


# ---------------------------------------------------------------------------
# Web3 helpers
# ---------------------------------------------------------------------------

def build_w3(rpc_url: str) -> Web3:
    """Create and configure a Web3 instance for Avalanche (POA middleware)."""
    w3 = Web3(Web3.HTTPProvider(rpc_url))
    # Inject POA middleware at layer 0 — required for Avalanche C-Chain
    w3.middleware_onion.inject(ExtraDataToPOAMiddleware, layer=0)
    if not w3.is_connected():
        raise RuntimeError(f"Cannot connect to RPC: {rpc_url}")
    print(f"[web3] Connected to {rpc_url} (chainId={w3.eth.chain_id})")
    return w3


def send_tx(w3: Web3, acct: Account, tx: dict) -> dict:
    """Sign, broadcast, and wait for a transaction. Raises on failure."""
    tx["nonce"] = w3.eth.get_transaction_count(acct.address)
    if "gas" not in tx:
        tx["gas"] = w3.eth.estimate_gas({**tx, "from": acct.address})

    signed = acct.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.raw_transaction)
    print(f"[tx] Sent {tx_hash.hex()} — waiting for receipt…")
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=120)
    if receipt.status != 1:
        raise RuntimeError(f"Transaction failed: {tx_hash.hex()}")
    print(f"[tx] Confirmed in block {receipt.blockNumber}")
    return receipt


# ---------------------------------------------------------------------------
# ERC-8183 job creation
# ---------------------------------------------------------------------------

def create_and_fund_job(w3: Web3, acct: Account, state: dict) -> dict:
    """Create and fund the first ERC-8183 job; persist result to state."""
    ac_address   = os.environ["AGENTIC_COMMERCE_ADDRESS"]
    worker       = os.environ["WORKER_ADDRESS"]
    evaluator    = os.environ.get("EVALUATOR_ADDRESS", "") or ""
    payment_avax = float(os.environ["FIRST_JOB_PAYMENT_AVAX"])
    deadline_hrs = int(os.environ["FIRST_JOB_DEADLINE_HOURS"])
    meta_uri     = os.environ["FIRST_JOB_METADATA_URI"]

    # Normalize evaluator — empty string becomes zero address
    evaluator_addr = Web3.to_checksum_address(evaluator) if evaluator else "0x0000000000000000000000000000000000000000"
    worker_addr    = Web3.to_checksum_address(worker)
    ac_addr        = Web3.to_checksum_address(ac_address)

    deadline_unix = int(time.time()) + deadline_hrs * 3600

    contract = w3.eth.contract(address=ac_addr, abi=AGENTIC_COMMERCE_ABI)

    # Step 1: createJob
    print(f"[job] Creating job: worker={worker_addr}, deadline in {deadline_hrs}h")
    create_tx = contract.functions.createJob(
        worker_addr,
        evaluator_addr,
        deadline_unix,
        meta_uri,
    ).build_transaction({"from": acct.address, "chainId": w3.eth.chain_id})
    send_tx(w3, acct, create_tx)

    # Derive jobId from nextJobId (created job is nextJobId - 1)
    job_id = contract.functions.nextJobId().call() - 1
    print(f"[job] Created jobId={job_id}")

    # Step 2: fundJob
    payment_wei = w3.to_wei(payment_avax, "ether")
    print(f"[job] Funding job {job_id} with {payment_avax} AVAX ({payment_wei} wei)")
    fund_tx = contract.functions.fundJob(job_id).build_transaction(
        {"from": acct.address, "chainId": w3.eth.chain_id, "value": payment_wei}
    )
    send_tx(w3, acct, fund_tx)

    # Step 3: Verify state
    job_data = contract.functions.getJob(job_id).call()
    job_state = job_data[6]  # state field (index 6)
    if job_state != 1:
        raise RuntimeError(f"Expected job state Funded(1), got {job_state}")
    print(f"[job] Job {job_id} is now in state: {JOB_STATE_NAMES.get(job_state, job_state)}")

    # Persist
    state["jobs"][str(job_id)] = {
        "id": job_id,
        "state": JOB_STATE_NAMES.get(job_state, str(job_state)),
        "worker": worker,
        "payment_avax": payment_avax,
        "deadline": deadline_unix,
        "vm_hash": None,
    }
    save_state(state)
    return state["jobs"][str(job_id)]


# ---------------------------------------------------------------------------
# Aleph Cloud VM provisioning
# ---------------------------------------------------------------------------

async def provision_aleph_vms(state: dict) -> None:
    """Provision 11 persistent Aleph Cloud VMs, one per Rat Agent."""
    try:
        from aleph.sdk.client import AuthenticatedAlephHttpClient
        from aleph.sdk.chains.ethereum import get_fallback_account as get_aleph_account
        from aleph.sdk.types import StorageEnum
    except ImportError:
        print("[aleph] aleph-sdk-python not installed — skipping VM provisioning.")
        print("        Install with: pip install aleph-sdk-python")
        return

    aleph_pk   = os.environ["ALEPH_PRIVATE_KEY"]
    api_url    = os.environ.get("ALEPH_API_URL", "https://api2.aleph.im")
    runtime_h  = os.environ["ALEPH_RUNTIME_HASH"]

    # Strip leading "0x" if present
    pk_bytes = bytes.fromhex(aleph_pk.lstrip("0x"))
    aleph_account = get_aleph_account(private_key=pk_bytes)

    print(f"[aleph] Provisioning {len(RAT_DEFS)} Rat Agent VMs via {api_url}")
    async with AuthenticatedAlephHttpClient(account=aleph_account, api_server=api_url) as client:
        for rat in RAT_DEFS:
            rat_id = rat["id"]
            rat_key = str(rat_id)

            # Skip if already provisioned
            if rat_key in state.get("rat_vms", {}) and state["rat_vms"][rat_key].get("vm_hash"):
                print(f"[aleph] Rat #{rat_id} already provisioned — skipping")
                continue

            print(f"[aleph] Provisioning Rat #{rat_id}: {rat['name']}")
            msg, _status = await client.create_post(
                post_type="INSTANCE",
                post_content={
                    "address": aleph_account.get_address(),
                    "time": time.time(),
                    "allow_amend": True,
                    "metadata": {
                        "name": f"falafel-rat-{rat_id}",
                        "description": f"Falafel Rat Agent #{rat_id}: {rat['name']}",
                        "tags": ["falafel", f"rat-{rat_id}"],
                    },
                    "environment": {
                        "reproducible": False,
                        "internet": True,
                        "aleph_api": True,
                        "variables": {
                            "RAT_ID":   str(rat_id),
                            "RAT_NAME": rat["name"],
                            "RAT_ROLE": rat["role"],
                            "AGENTIC_COMMERCE_ADDRESS": os.getenv("AGENTIC_COMMERCE_ADDRESS", ""),
                            "RAT_AGENTS_ADDRESS":       os.getenv("RAT_AGENTS_ADDRESS", ""),
                        },
                    },
                    "resources": {"vcpus": 1, "memory": 2048, "seconds": 0},
                    "payment": {"chain": "AVAX", "type": "hold"},
                    "volumes": [
                        {
                            "mount": "/data",
                            "size_mib": 2048,
                            "is_read_only": False,
                            "persistence": "host",
                        }
                    ],
                    "runtime": {"ref": runtime_h, "use_latest": True},
                },
                channel="FALAFEL",
                storage_engine=StorageEnum.storage,
                sync=True,
            )

            vm_hash = msg.item_hash
            print(f"[aleph] Rat #{rat_id} provisioned — vm_hash={vm_hash}")

            if "rat_vms" not in state:
                state["rat_vms"] = {}
            state["rat_vms"][rat_key] = {
                "rat_id": rat_id,
                "rat_name": rat["name"],
                "vm_hash": vm_hash,
                "status": "provisioned",
            }
            save_state(state)


# ---------------------------------------------------------------------------
# Status display
# ---------------------------------------------------------------------------

def print_status(w3: Web3, state: dict) -> None:
    """Print a human-readable summary of on-chain and Aleph state."""
    print("\n=== Falafel Phase 1 Status ===")
    print(f"Chain ID : {w3.eth.chain_id}")
    print(f"Block    : {w3.eth.block_number}")

    print("\n--- Jobs ---")
    if not state.get("jobs"):
        print("  (none)")
    for jid, job in state.get("jobs", {}).items():
        print(f"  Job #{jid}: state={job.get('state')} worker={job.get('worker')} "
              f"payment={job.get('payment_avax')} AVAX")

    print("\n--- Rat Agent VMs ---")
    if not state.get("rat_vms"):
        print("  (none provisioned)")
    for rid, vm in state.get("rat_vms", {}).items():
        print(f"  Rat #{rid} ({vm.get('rat_name')}): status={vm.get('status')} "
              f"vm_hash={vm.get('vm_hash')}")


# ---------------------------------------------------------------------------
# Main entry point
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Falafel Phase 1 Orchestrator")
    parser.add_argument(
        "--mode",
        choices=["setup", "status", "job-only", "aleph-only"],
        default="status",
        help="Operation mode",
    )
    args = parser.parse_args()

    state = load_state()

    # Connect to Avalanche Fuji
    rpc_url = os.environ.get("FUJI_RPC_URL", "https://api.avax-test.network/ext/bc/C/rpc")
    w3 = build_w3(rpc_url)

    deployer_pk = os.environ.get("DEPLOYER_PRIVATE_KEY", "")
    acct = Account.from_key(deployer_pk) if deployer_pk else None

    if args.mode == "status":
        print_status(w3, state)

    elif args.mode == "job-only":
        if not acct:
            raise RuntimeError("DEPLOYER_PRIVATE_KEY not set")
        create_and_fund_job(w3, acct, state)

    elif args.mode == "aleph-only":
        asyncio.run(provision_aleph_vms(state))

    elif args.mode == "setup":
        if not acct:
            raise RuntimeError("DEPLOYER_PRIVATE_KEY not set")
        create_and_fund_job(w3, acct, state)
        asyncio.run(provision_aleph_vms(state))
        print_status(w3, state)


if __name__ == "__main__":
    main()
