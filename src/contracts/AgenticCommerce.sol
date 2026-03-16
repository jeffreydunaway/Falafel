// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// AgenticCommerce — Full implementation of ERC-8183 Agentic Commerce Protocol.
// A trustless 4-state job escrow system for AI-agent-to-agent commerce.
// Deployed on Avalanche C-Chain (EVM-compatible port of the Ethereum EIP).
//
// State machine: Open(0) → Funded(1) → Submitted(2) → Terminal(3)
//
// OZ 5.x: inherits ReentrancyGuard + Ownable(initialOwner_).

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract AgenticCommerce is ReentrancyGuard, Ownable {
    // -------------------------------------------------------------------------
    // Types
    // -------------------------------------------------------------------------

    enum JobState {
        Open,      // 0 — created, no funds locked
        Funded,    // 1 — client deposited AVAX
        Submitted, // 2 — worker submitted deliverable; awaiting approval
        Terminal   // 3 — finalized; payment released or refunded; immutable
    }

    struct Job {
        uint256 id;
        address client;
        address worker;
        address evaluator;      // Optional arbitrator; address(0) = auto-approve
        uint256 payment;        // AVAX (wei) locked in escrow
        uint256 deadline;       // Unix timestamp
        JobState state;
        bytes32 deliverableHash; // keccak256 of deliverable (e.g. IPFS CID)
        string metadataURI;     // IPFS URI with job specification
        bool workerWon;         // Terminal: true = worker paid, false = client refunded
    }

    // -------------------------------------------------------------------------
    // Events (ERC-8183 standard)
    // -------------------------------------------------------------------------

    event JobCreated(
        uint256 indexed jobId,
        address indexed client,
        address indexed worker,
        address evaluator,
        uint256 deadline,
        string metadataURI
    );
    event JobFunded(uint256 indexed jobId, address indexed client, uint256 amount);
    event WorkSubmitted(uint256 indexed jobId, address indexed worker, bytes32 deliverableHash);
    event JobApproved(uint256 indexed jobId, address indexed worker, uint256 payout);
    event JobRefunded(uint256 indexed jobId, address indexed client, uint256 refund);
    event DisputeOpened(uint256 indexed jobId, address indexed client);
    event DisputeResolved(uint256 indexed jobId, address indexed evaluator, bool workerWins);
    event JobExpired(uint256 indexed jobId, address indexed triggeredBy);

    // -------------------------------------------------------------------------
    // Storage
    // -------------------------------------------------------------------------

    uint256 private _nextJobId;          // starts at 1; 0 is sentinel for "no job"
    mapping(uint256 => Job) private _jobs;

    uint256 public feeBps;               // Protocol fee in basis points (e.g. 250 = 2.5%)
    uint256 public accumulatedFees;      // Fees available for owner withdrawal
    uint256 public constant MAX_FEE_BPS = 500; // Hard cap: 5%

    // -------------------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------------------

    constructor(address initialOwner_, uint256 feeBps_) Ownable(initialOwner_) {
        require(initialOwner_ != address(0), "AC: zero owner");
        require(feeBps_ <= MAX_FEE_BPS, "AC: fee too high");
        _nextJobId = 1;
        feeBps = feeBps_;
    }

    // -------------------------------------------------------------------------
    // CLIENT functions
    // -------------------------------------------------------------------------

    /// @notice Create a new job. Returns the assigned jobId.
    function createJob(
        address worker_,
        address evaluator_,
        uint256 deadline_,
        string calldata metadataURI_
    ) external returns (uint256 jobId) {
        require(worker_ != address(0), "AC: zero worker");
        require(worker_ != msg.sender, "AC: worker == client");
        require(deadline_ > block.timestamp, "AC: deadline in past");

        jobId = _nextJobId++;
        _jobs[jobId] = Job({
            id: jobId,
            client: msg.sender,
            worker: worker_,
            evaluator: evaluator_,
            payment: 0,
            deadline: deadline_,
            state: JobState.Open,
            deliverableHash: bytes32(0),
            metadataURI: metadataURI_,
            workerWon: false
        });

        emit JobCreated(jobId, msg.sender, worker_, evaluator_, deadline_, metadataURI_);
    }

    /// @notice Fund a job with AVAX. Caller must be the job's client.
    function fundJob(uint256 jobId) external payable nonReentrant {
        Job storage job = _jobs[jobId];
        require(job.client == msg.sender, "AC: not client");
        require(job.state == JobState.Open, "AC: not open");
        require(msg.value > 0, "AC: zero payment");
        require(block.timestamp < job.deadline, "AC: expired");

        job.payment = msg.value;
        job.state = JobState.Funded;

        emit JobFunded(jobId, msg.sender, msg.value);
    }

    /// @notice Client approves submitted work; releases payout to worker.
    function approveJob(uint256 jobId) external nonReentrant {
        Job storage job = _jobs[jobId];
        require(job.client == msg.sender, "AC: not client");
        require(job.state == JobState.Submitted, "AC: not submitted");

        _releasePayout(jobId);
    }

    /// @notice Client opens a dispute. Requires an evaluator to have been set.
    function disputeJob(uint256 jobId) external {
        Job storage job = _jobs[jobId];
        require(job.client == msg.sender, "AC: not client");
        require(job.state == JobState.Submitted, "AC: not submitted");
        require(job.evaluator != address(0), "AC: no evaluator");

        // State stays Submitted; evaluator must call resolveDispute
        emit DisputeOpened(jobId, msg.sender);
    }

    // -------------------------------------------------------------------------
    // WORKER functions
    // -------------------------------------------------------------------------

    /// @notice Worker submits deliverable hash. If no evaluator, auto-approves.
    function submitWork(uint256 jobId, bytes32 deliverableHash_) external {
        Job storage job = _jobs[jobId];
        require(job.worker == msg.sender, "AC: not worker");
        require(job.state == JobState.Funded, "AC: not funded");
        require(deliverableHash_ != bytes32(0), "AC: zero hash");

        job.deliverableHash = deliverableHash_;
        job.state = JobState.Submitted;

        emit WorkSubmitted(jobId, msg.sender, deliverableHash_);

        // Auto-approve if no evaluator assigned
        if (job.evaluator == address(0)) {
            _releasePayout(jobId);
        }
    }

    // -------------------------------------------------------------------------
    // EVALUATOR functions
    // -------------------------------------------------------------------------

    /// @notice Evaluator resolves a dispute.
    function resolveDispute(uint256 jobId, bool workerWins_) external nonReentrant {
        Job storage job = _jobs[jobId];
        require(job.evaluator == msg.sender, "AC: not evaluator");
        require(job.state == JobState.Submitted, "AC: not submitted");

        emit DisputeResolved(jobId, msg.sender, workerWins_);

        if (workerWins_) {
            _releasePayout(jobId);
        } else {
            _refundClient(jobId);
        }
    }

    // -------------------------------------------------------------------------
    // ANYONE — expiry after deadline
    // -------------------------------------------------------------------------

    /// @notice Expire a funded job that has passed its deadline; refunds client.
    function expireJob(uint256 jobId) external nonReentrant {
        Job storage job = _jobs[jobId];
        require(job.state == JobState.Funded, "AC: not funded");
        require(block.timestamp >= job.deadline, "AC: not expired");

        emit JobExpired(jobId, msg.sender);

        // Full refund on expiry — no protocol fee deducted
        _refundClient(jobId);
    }

    // -------------------------------------------------------------------------
    // OWNER functions
    // -------------------------------------------------------------------------

    function setFeeBps(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= MAX_FEE_BPS, "AC: fee too high");
        feeBps = newFeeBps;
    }

    function withdrawFees() external onlyOwner nonReentrant {
        uint256 amount = accumulatedFees;
        require(amount > 0, "AC: no fees");
        accumulatedFees = 0;
        (bool ok,) = payable(owner()).call{value: amount}("");
        require(ok, "AC: fee transfer failed");
    }

    // -------------------------------------------------------------------------
    // VIEW functions
    // -------------------------------------------------------------------------

    function getJob(uint256 jobId) external view returns (Job memory) {
        return _jobs[jobId];
    }

    function getJobState(uint256 jobId) external view returns (JobState) {
        return _jobs[jobId].state;
    }

    /// @notice Returns the next job ID that will be assigned.
    function nextJobId() external view returns (uint256) {
        return _nextJobId;
    }

    // -------------------------------------------------------------------------
    // Receive — direct AVAX deposits accumulate as protocol fees
    // -------------------------------------------------------------------------

    receive() external payable {
        accumulatedFees += msg.value;
    }

    // -------------------------------------------------------------------------
    // Internal helpers
    // -------------------------------------------------------------------------

    /// @dev Release payment minus protocol fee to the worker. Marks job Terminal.
    function _releasePayout(uint256 jobId) internal {
        Job storage job = _jobs[jobId];
        uint256 payment = job.payment;
        address worker = job.worker;

        uint256 fee = (payment * feeBps) / 10_000;
        uint256 payout = payment - fee;

        accumulatedFees += fee;
        job.payment = 0;
        job.state = JobState.Terminal;
        job.workerWon = true;

        emit JobApproved(jobId, worker, payout);

        (bool ok,) = payable(worker).call{value: payout}("");
        require(ok, "AC: worker transfer failed");
    }

    /// @dev Refund full escrow amount to the client. Marks job Terminal.
    function _refundClient(uint256 jobId) internal {
        Job storage job = _jobs[jobId];
        uint256 refund = job.payment;
        address client = job.client;

        job.payment = 0;
        job.state = JobState.Terminal;
        job.workerWon = false;

        emit JobRefunded(jobId, client, refund);

        (bool ok,) = payable(client).call{value: refund}("");
        require(ok, "AC: client refund failed");
    }
}
