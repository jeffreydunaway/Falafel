// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// AgenticCommerceTest — Foundry tests for the ERC-8183 AgenticCommerce contract.
// Covers full job lifecycle, dispute resolution, expiry, fees, and access control.

import {Test, console} from "forge-std/Test.sol";
import {AgenticCommerce} from "../src/contracts/AgenticCommerce.sol";

contract AgenticCommerceTest is Test {
    AgenticCommerce ac;

    address owner     = address(0x1);
    address client    = address(0x2);
    address worker    = address(0x3);
    address evaluator = address(0x4);
    address stranger  = address(0x5);

    uint256 constant FEE_BPS  = 250; // 2.5%
    uint256 constant PAYMENT  = 1 ether;
    uint256 deadline;

    function setUp() public {
        vm.prank(owner);
        ac = new AgenticCommerce(owner, FEE_BPS);
        deadline = block.timestamp + 1 days;

        // Fund test addresses
        vm.deal(client, 10 ether);
        vm.deal(worker, 1 ether);
    }

    // -------------------------------------------------------------------------
    // Helpers
    // -------------------------------------------------------------------------

    function _createJob(address eval_) internal returns (uint256) {
        vm.prank(client);
        return ac.createJob(worker, eval_, deadline, "ipfs://job-spec");
    }

    function _createAndFundJob(address eval_) internal returns (uint256 jobId) {
        jobId = _createJob(eval_);
        vm.prank(client);
        ac.fundJob{value: PAYMENT}(jobId);
    }

    // -------------------------------------------------------------------------
    // createJob
    // -------------------------------------------------------------------------

    function test_CreateJob() public {
        uint256 jobId = _createJob(address(0));
        assertEq(jobId, 1);
        AgenticCommerce.Job memory job = ac.getJob(jobId);
        assertEq(job.client, client);
        assertEq(job.worker, worker);
        assertEq(uint8(job.state), uint8(AgenticCommerce.JobState.Open));
    }

    function test_CreateJob_RevertZeroWorker() public {
        vm.prank(client);
        vm.expectRevert(bytes("AC: zero worker"));
        ac.createJob(address(0), address(0), deadline, "uri");
    }

    function test_CreateJob_RevertWorkerEqualsClient() public {
        vm.prank(client);
        vm.expectRevert(bytes("AC: worker == client"));
        ac.createJob(client, address(0), deadline, "uri");
    }

    function test_CreateJob_RevertPastDeadline() public {
        vm.prank(client);
        vm.expectRevert(bytes("AC: deadline in past"));
        ac.createJob(worker, address(0), block.timestamp - 1, "uri");
    }

    // -------------------------------------------------------------------------
    // fundJob
    // -------------------------------------------------------------------------

    function test_FundJob() public {
        uint256 jobId = _createJob(address(0));
        vm.prank(client);
        ac.fundJob{value: PAYMENT}(jobId);
        AgenticCommerce.Job memory job = ac.getJob(jobId);
        assertEq(job.payment, PAYMENT);
        assertEq(uint8(job.state), uint8(AgenticCommerce.JobState.Funded));
    }

    function test_FundJob_RevertNotClient() public {
        uint256 jobId = _createJob(address(0));
        vm.prank(stranger);
        vm.deal(stranger, 1 ether);
        vm.expectRevert(bytes("AC: not client"));
        ac.fundJob{value: PAYMENT}(jobId);
    }

    function test_FundJob_RevertZeroValue() public {
        uint256 jobId = _createJob(address(0));
        vm.prank(client);
        vm.expectRevert(bytes("AC: zero payment"));
        ac.fundJob{value: 0}(jobId);
    }

    // -------------------------------------------------------------------------
    // submitWork
    // -------------------------------------------------------------------------

    function test_SubmitWork() public {
        uint256 jobId = _createAndFundJob(evaluator);
        bytes32 hash = keccak256("deliverable-cid");
        vm.prank(worker);
        ac.submitWork(jobId, hash);
        AgenticCommerce.Job memory job = ac.getJob(jobId);
        assertEq(job.deliverableHash, hash);
        assertEq(uint8(job.state), uint8(AgenticCommerce.JobState.Submitted));
    }

    function test_SubmitWork_AutoApproveNoEvaluator() public {
        uint256 jobId = _createAndFundJob(address(0));
        bytes32 hash = keccak256("deliverable");
        vm.prank(worker);
        ac.submitWork(jobId, hash);
        // With no evaluator, job should go Terminal immediately
        AgenticCommerce.Job memory job = ac.getJob(jobId);
        assertEq(uint8(job.state), uint8(AgenticCommerce.JobState.Terminal));
        assertTrue(job.workerWon);
    }

    function test_SubmitWork_RevertNotWorker() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(stranger);
        vm.expectRevert(bytes("AC: not worker"));
        ac.submitWork(jobId, keccak256("x"));
    }

    function test_SubmitWork_RevertZeroHash() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(worker);
        vm.expectRevert(bytes("AC: zero hash"));
        ac.submitWork(jobId, bytes32(0));
    }

    // -------------------------------------------------------------------------
    // approveJob
    // -------------------------------------------------------------------------

    function test_ApproveJob() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(worker);
        ac.submitWork(jobId, keccak256("del"));
        uint256 workerBalBefore = worker.balance;
        vm.prank(client);
        ac.approveJob(jobId);

        AgenticCommerce.Job memory job = ac.getJob(jobId);
        assertEq(uint8(job.state), uint8(AgenticCommerce.JobState.Terminal));
        assertTrue(job.workerWon);
        // Worker should have received payment minus fee
        uint256 fee = (PAYMENT * FEE_BPS) / 10_000;
        assertEq(worker.balance, workerBalBefore + PAYMENT - fee);
    }

    function test_ApproveJob_RevertNotClient() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(worker);
        ac.submitWork(jobId, keccak256("del"));
        vm.prank(stranger);
        vm.expectRevert(bytes("AC: not client"));
        ac.approveJob(jobId);
    }

    // -------------------------------------------------------------------------
    // disputeJob
    // -------------------------------------------------------------------------

    function test_DisputeJob() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(worker);
        ac.submitWork(jobId, keccak256("del"));
        vm.prank(client);
        ac.disputeJob(jobId);
        // State remains Submitted
        assertEq(uint8(ac.getJobState(jobId)), uint8(AgenticCommerce.JobState.Submitted));
    }

    function test_DisputeJob_RevertNotSubmitted() public {
        // Job is Funded but not Submitted — disputeJob should revert with "AC: not submitted"
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(client);
        vm.expectRevert(bytes("AC: not submitted"));
        ac.disputeJob(jobId);
    }

    function test_DisputeJob_RevertNoEvaluator() public {
        // A job with no evaluator in Submitted state is impossible via normal flow
        // (submitWork auto-approves it). Test that disputeJob requires Submitted state.
        uint256 jobId = _createAndFundJob(address(0));
        // Still in Funded state — calling disputeJob should revert before checking evaluator
        vm.prank(client);
        vm.expectRevert(bytes("AC: not submitted"));
        ac.disputeJob(jobId);
    }

    // -------------------------------------------------------------------------
    // resolveDispute
    // -------------------------------------------------------------------------

    function test_ResolveDispute_WorkerWins() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(worker);
        ac.submitWork(jobId, keccak256("del"));
        uint256 workerBalBefore = worker.balance;
        vm.prank(evaluator);
        ac.resolveDispute(jobId, true);
        AgenticCommerce.Job memory job = ac.getJob(jobId);
        assertTrue(job.workerWon);
        assertEq(uint8(job.state), uint8(AgenticCommerce.JobState.Terminal));
        uint256 fee = (PAYMENT * FEE_BPS) / 10_000;
        assertEq(worker.balance, workerBalBefore + PAYMENT - fee);
    }

    function test_ResolveDispute_ClientWins() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(worker);
        ac.submitWork(jobId, keccak256("del"));
        uint256 clientBalBefore = client.balance;
        vm.prank(evaluator);
        ac.resolveDispute(jobId, false);
        AgenticCommerce.Job memory job = ac.getJob(jobId);
        assertFalse(job.workerWon);
        assertEq(client.balance, clientBalBefore + PAYMENT);
    }

    function test_ResolveDispute_RevertNotEvaluator() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.prank(worker);
        ac.submitWork(jobId, keccak256("del"));
        vm.prank(stranger);
        vm.expectRevert(bytes("AC: not evaluator"));
        ac.resolveDispute(jobId, true);
    }

    // -------------------------------------------------------------------------
    // expireJob
    // -------------------------------------------------------------------------

    function test_ExpireJob() public {
        uint256 jobId = _createAndFundJob(evaluator);
        uint256 clientBalBefore = client.balance;
        vm.warp(deadline + 1);
        ac.expireJob(jobId);
        AgenticCommerce.Job memory job = ac.getJob(jobId);
        assertFalse(job.workerWon);
        assertEq(uint8(job.state), uint8(AgenticCommerce.JobState.Terminal));
        assertEq(client.balance, clientBalBefore + PAYMENT);
    }

    function test_ExpireJob_RevertNotExpired() public {
        uint256 jobId = _createAndFundJob(evaluator);
        vm.expectRevert(bytes("AC: not expired"));
        ac.expireJob(jobId);
    }

    // -------------------------------------------------------------------------
    // Fee management
    // -------------------------------------------------------------------------

    function test_SetFeeBps() public {
        vm.prank(owner);
        ac.setFeeBps(100);
        assertEq(ac.feeBps(), 100);
    }

    function test_SetFeeBps_RevertTooHigh() public {
        vm.prank(owner);
        vm.expectRevert(bytes("AC: fee too high"));
        ac.setFeeBps(501);
    }

    function test_WithdrawFees() public {
        // Complete a job to accumulate fees
        uint256 jobId = _createAndFundJob(address(0));
        vm.prank(worker);
        ac.submitWork(jobId, keccak256("del"));
        // Fees should now be accumulated
        uint256 ownerBalBefore = owner.balance;
        uint256 accFees = ac.accumulatedFees();
        assertTrue(accFees > 0, "no fees accumulated");
        vm.prank(owner);
        ac.withdrawFees();
        assertEq(owner.balance, ownerBalBefore + accFees);
        assertEq(ac.accumulatedFees(), 0);
    }

    // -------------------------------------------------------------------------
    // nextJobId
    // -------------------------------------------------------------------------

    function test_NextJobId_StartsAt1() public view {
        assertEq(ac.nextJobId(), 1);
    }

    function test_NextJobId_Increments() public {
        _createJob(address(0));
        assertEq(ac.nextJobId(), 2);
        _createJob(address(0));
        assertEq(ac.nextJobId(), 3);
    }

    // -------------------------------------------------------------------------
    // Receive fallback
    // -------------------------------------------------------------------------

    function test_Receive_AccumulatesFees() public {
        uint256 before = ac.accumulatedFees();
        (bool ok,) = address(ac).call{value: 0.5 ether}("");
        assertTrue(ok);
        assertEq(ac.accumulatedFees(), before + 0.5 ether);
    }
}
