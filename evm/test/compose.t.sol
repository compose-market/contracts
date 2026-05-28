// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";

// Import contracts
import {AgentFactory} from "../contracts/compose/agentfactory.sol";
import {Clone} from "../contracts/compose/clone.sol";
import {Warp} from "../contracts/compose/warp.sol";
import {Workflow} from "../contracts/compose/workflow.sol";
import {RFA} from "../contracts/compose/rfa.sol";
import {Lease} from "../contracts/compose/lease.sol";
import {Reputation} from "../contracts/compose/reputation.sol";
import {Validation} from "../contracts/compose/validation.sol";
import {Royalties} from "../contracts/compose/royalties.sol";
import {Distributor} from "../contracts/compose/distributor.sol";
import {Utils} from "../contracts/compose/utils.sol";
import {AgentManager} from "../contracts/compose/agentmanager.sol";
import {Delegation} from "../contracts/compose/delegation.sol";
import {IWorkflow} from "../contracts/compose/interfaces/Iworkflow.sol";
import {IClone} from "../contracts/compose/interfaces/Iclone.sol";
import {IDistributor} from "../contracts/compose/interfaces/Iroyalties.sol";

/**
 * @title ComposeTest
 * @notice Comprehensive tests for the Workflow Protocol
 * @dev Tests ALL public/external functions in ALL contracts
 */
contract ComposeTest is Test {
    uint256 internal constant SUPPORTED_CHAIN_ID = 43113;
    address internal constant SUPPORTED_USDC = 0x5425890298aed601595a70AB815c96711a31Bc65;
    address internal constant AVALANCHE_USDC = 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E;

    // =============================================================================
    // Test Contracts
    // =============================================================================

    AgentFactory public agentFactory;
    Clone public clone;
    Warp public warp;
    Workflow public workflow;
    RFA public rfa;
    Lease public lease;
    Reputation public reputation;
    Validation public validation;
    Royalties public royalties;
    Distributor public distributor;
    Utils public utils;
    AgentManager public agentManager;
    Delegation public delegation;
    MockERC20 public usdc;

    // =============================================================================
    // Test Addresses
    // =============================================================================

    address public treasury = address(0x1234);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public charlie = address(0xC4A11E);

    // =============================================================================
    // Setup
    // =============================================================================

    function setUp() public {
        vm.chainId(SUPPORTED_CHAIN_ID);

        // Bind mock USDC code to the chain-mapped USDC address used by compose contracts.
        MockERC20 usdcImpl = new MockERC20("USD Coin", "USDC", 6);
        vm.etch(SUPPORTED_USDC, address(usdcImpl).code);
        usdc = MockERC20(SUPPORTED_USDC);
        
        // Mint USDC to test users
        usdc.mint(alice, 1_000_000 * 10**6); // 1M USDC
        usdc.mint(bob, 1_000_000 * 10**6);
        usdc.mint(charlie, 1_000_000 * 10**6);

        // Deploy support contracts
        royalties = new Royalties(treasury, 500, address(this)); // 5% default royalty
        distributor = new Distributor(treasury, address(this));

        // Deploy AgentFactory
        agentFactory = new AgentFactory(address(this));

        // Deploy Clone and Warp
        clone = new Clone(address(agentFactory));
        warp = new Warp(address(agentFactory), treasury);

        // Deploy Workflow (with chain-aware USDC payment token)
        workflow = new Workflow(address(agentFactory), address(this));

        // Deploy RFA and Lease
        rfa = new RFA(address(workflow), address(agentFactory), address(this));
        lease = new Lease(address(workflow), address(this));
        reputation = new Reputation(address(agentFactory));
        validation = new Validation(address(agentFactory));

        // Deploy Delegation and AgentManager
        delegation = new Delegation();
        agentManager = new AgentManager(address(this));

        // Deploy Utils
        utils = new Utils(address(agentManager), address(agentFactory), address(workflow));

        // Initialize
        delegation.initialize(address(agentManager));
        agentManager.initializeEcosystem(
            address(delegation),
            address(agentFactory),
            address(workflow),
            address(clone),
            address(warp),
            address(lease),
            address(rfa),
            address(royalties),
            address(distributor)
        );

        // Authorize consumers
        agentFactory.authorizeConsumer(address(clone));
        agentFactory.authorizeConsumer(address(warp));
        agentFactory.authorizeConsumer(address(workflow));

        // Set RFA contract in Workflow
        workflow.setRFAContract(address(rfa));
        workflow.setLeaseContract(address(lease));
        workflow.setDistributor(address(distributor));
        workflow.setTreasury(treasury);
    }

    // =============================================================================
    // AgentFactory Tests - ALL Functions
    // =============================================================================

    function test_AgentFactory_MintAgent() public {
        bytes32 dnaHash = keccak256(abi.encodePacked("skill1", uint256(43113), "asi1-mini"));
        
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(
            dnaHash,
            100, // units
            1000000, // price: 1 USDC
            true, // cloneable
            "ipfs://QmTest"
        );

        assertEq(agentId, 1);
        assertEq(agentFactory.totalAgents(), 1);
        
        // Check agent data
        AgentFactory.AgentData memory data = agentFactory.getAgentData(agentId);
        assertEq(data.dnaHash, dnaHash);
        assertEq(data.licenses, 100);
        assertEq(data.licensePrice, 1000000);
        assertEq(data.creator, alice);
        assertTrue(data.cloneable);
        assertFalse(data.isClone);
    }

    function test_AgentFactory_RegisterAgent() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.register("ipfs://simple");
        
        assertEq(agentId, 1);
        string memory uri = agentFactory.agentURI(agentId);
        assertEq(uri, "ipfs://simple");
        assertTrue(abi.decode(agentFactory.getMetadata(agentId, "x402"), (bool)));
        assertEq(agentFactory.getAgentWallet(agentId), alice);
    }

    function test_AgentFactory_UpdateAgentCardUri() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.register("ipfs://old");
        
        vm.prank(alice);
        agentFactory.setAgentURI(agentId, "ipfs://new");
        
        assertEq(agentFactory.agentURI(agentId), "ipfs://new");
    }

    function test_AgentFactory_AgentWalletReservedAndResetOnTransfer() public {
        uint256 walletPrivateKey = 0xBEEF;
        address wallet = vm.addr(walletPrivateKey);

        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("wallet"), 0, 1000000, false, "ipfs://test");
        assertEq(agentFactory.getAgentWallet(agentId), alice);

        bytes32 digest = agentFactory.agentWalletMessageHash(agentId, wallet);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(walletPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(alice);
        agentFactory.setAgentWallet(agentId, wallet, signature);
        assertEq(agentFactory.getAgentWallet(agentId), wallet);
        assertEq(abi.decode(agentFactory.getMetadata(agentId, "agentWallet"), (address)), wallet);

        vm.prank(alice);
        vm.expectRevert();
        agentFactory.setMetadata(agentId, "agentWallet", abi.encode(charlie));

        vm.prank(alice);
        agentFactory.transferFrom(alice, bob, agentId);
        assertEq(agentFactory.getAgentWallet(agentId), address(0));
        assertEq(agentFactory.getMetadata(agentId, "agentWallet").length, 0);
    }

    function test_AgentFactory_UpdatePrice() public {
        bytes32 dnaHash = keccak256("agent1");
        
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(dnaHash, 0, 1000000, false, "ipfs://test");

        vm.prank(alice);
        agentFactory.updatePrice(agentId, 2000000);

        AgentFactory.AgentData memory data = agentFactory.getAgentData(agentId);
        assertEq(data.licensePrice, 2000000);
    }

    function test_AgentFactory_GetDnaHash() public {
        bytes32 dnaHash = keccak256("unique");
        
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(dnaHash, 100, 1000000, false, "ipfs://test");
        
        assertEq(agentFactory.getDnaHash(agentId), dnaHash);
    }

    function test_AgentFactory_HasAvailableLicenses() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("test"), 2, 1000000, false, "ipfs://test");
        
        assertTrue(agentFactory.hasAvailableLicenses(agentId));
    }

    function test_AgentFactory_ConsumeLicense() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("consume"), 2, 1000000, false, "ipfs://test");
        
        // Workflow contract is authorized
        vm.prank(address(workflow));
        uint256 license1 = agentFactory.consumeLicense(agentId, address(workflow), 1);
        assertEq(license1, 1);
        
        vm.prank(address(workflow));
        uint256 license2 = agentFactory.consumeLicense(agentId, address(workflow), 2);
        assertEq(license2, 2);
    }

    function test_AgentFactory_IsAgentClone() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("notclone"), 100, 1000000, false, "ipfs://test");
        
        assertFalse(agentFactory.isAgentClone(agentId));
    }

    function test_AgentFactory_GetParentAgent() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("noparent"), 100, 1000000, false, "ipfs://test");
        
        assertEq(agentFactory.getParentAgent(agentId), 0);
    }

    function test_AgentFactory_AgentExists() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("exists"), 100, 1000000, false, "ipfs://test");
        
        assertTrue(agentFactory.agentExists(agentId));
        assertFalse(agentFactory.agentExists(999));
    }

    function test_AgentFactory_GetAgentCreator() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("creator"), 100, 1000000, false, "ipfs://test");
        
        assertEq(agentFactory.getAgentCreator(agentId), alice);
    }

    function test_Reputation_AnchorsNativeFeedback() public {
        bytes32 dnaHash = keccak256("agent1");
        
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(dnaHash, 0, 1000000, false, "ipfs://test");

        vm.prank(bob);
        reputation.giveFeedback(
            agentId,
            50,
            1,
            "quality",
            "agent",
            "/agent/1/stream",
            "ipfs://feedback/bob",
            keccak256("great")
        );
        
        vm.prank(charlie);
        reputation.giveFeedback(
            agentId,
            40,
            1,
            "quality",
            "agent",
            "/agent/1/stream",
            "ipfs://feedback/charlie",
            keccak256("good")
        );

        address[] memory clients = new address[](2);
        clients[0] = bob;
        clients[1] = charlie;

        (uint64 count, int128 summaryValue, uint8 summaryDecimals) =
            reputation.getSummary(agentId, clients, "quality", "agent");
        assertEq(count, 2);
        assertEq(summaryValue, 45);
        assertEq(summaryDecimals, 1);

        (
            address[] memory returnedClients,
            uint64[] memory indexes,
            int128[] memory values,
            ,
            string[] memory tag1s,
            string[] memory tag2s,
            bool[] memory revoked
        ) = reputation.readAllFeedback(agentId, clients, "quality", "agent", false);
        assertEq(returnedClients.length, 2);
        assertEq(returnedClients[0], bob);
        assertEq(indexes[0], 1);
        assertEq(values[0], 50);
        assertEq(tag1s[0], "quality");
        assertEq(tag2s[0], "agent");
        assertFalse(revoked[0]);
    }

    function test_Validation_RequestAndResponse() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("validate"), 0, 1000000, false, "ipfs://test");

        vm.prank(bob);
        uint256 requestId = validation.requestValidation(agentId, "a2a-run", keccak256("task1"), "ipfs://validation-request");
        
        vm.prank(charlie);
        uint256 responseId = validation.respondValidation(requestId, true, keccak256("proof"), "ipfs://validation-proof");

        Validation.ValidationRequest memory request = validation.getValidationRequest(requestId);
        assertEq(request.agentId, agentId);
        assertEq(request.requester, bob);

        Validation.ValidationResponse memory response = validation.getValidationResponse(responseId);
        assertEq(response.requestId, requestId);
        assertEq(response.validator, charlie);
        assertTrue(response.valid);

        uint256[] memory requests = validation.getAgentValidationRequests(agentId);
        assertEq(requests.length, 1);
        assertEq(requests[0], requestId);

        uint256[] memory responses = validation.getValidationResponses(requestId);
        assertEq(responses.length, 1);
        assertEq(responses[0], responseId);
    }

    function test_AgentFactory_AuthorizeConsumer() public {
        address newConsumer = address(0x9999);
        
        agentFactory.authorizeConsumer(newConsumer);
        assertTrue(agentFactory.isAuthorizedConsumer(newConsumer));
        
        agentFactory.revokeConsumer(newConsumer);
        assertFalse(agentFactory.isAuthorizedConsumer(newConsumer));
    }

    function test_AgentFactory_TransferAdmin() public {
        address newAdmin = address(0x8888);
        
        agentFactory.transferAdmin(newAdmin);
        assertEq(agentFactory.getAdmin(), newAdmin);
    }

    function test_AgentFactory_ERC721Functions() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("erc721"), 100, 1000000, false, "ipfs://test");

        assertEq(agentFactory.name(), "Manowar Agent");
        assertEq(agentFactory.symbol(), "MWAGENT");
        assertEq(agentFactory.tokenURI(agentId), "ipfs://test");
        assertEq(agentFactory.balanceOf(alice), 1);
        assertEq(agentFactory.ownerOf(agentId), alice);
        
        // Approve and transfer
        vm.prank(alice);
        agentFactory.approve(bob, agentId);
        assertEq(agentFactory.getApproved(agentId), bob);
        
        vm.prank(bob);
        agentFactory.transferFrom(alice, bob, agentId);
        assertEq(agentFactory.ownerOf(agentId), bob);
        
        // Operator approval
        vm.prank(bob);
        agentFactory.setApprovalForAll(charlie, true);
        assertTrue(agentFactory.isApprovedForAll(bob, charlie));
        
        assertTrue(agentFactory.supportsInterface(0x80ac58cd)); // ERC721
    }

    // =============================================================================
    // Clone Tests - ALL Functions
    // =============================================================================

    function test_Clone_CloneAgent() public {
        bytes32 dnaHash = keccak256("original");
        
        vm.prank(alice);
        uint256 originalId = agentFactory.mintAgent(dnaHash, 100, 1000000, true, "ipfs://original");

        IClone.CloneParams memory params = IClone.CloneParams({
            chainId: 1,
            licensePrice: 500000,
            model: "gpt-4",
            licenses: 50
        });

        vm.prank(bob);
        uint256 cloneId = clone.cloneAgent(originalId, params, "ipfs://clone");

        assertTrue(clone.canClone(originalId));
        assertFalse(clone.canClone(cloneId));
        assertEq(clone.getCloneCount(originalId), 1);
        
        uint256[] memory clones = clone.getClonesOf(originalId);
        assertEq(clones.length, 1);
        assertEq(clones[0], cloneId);
    }

    function test_Clone_CanClone() public {
        vm.prank(alice);
        uint256 cloneable = agentFactory.mintAgent(keccak256("cloneable"), 100, 1000000, true, "ipfs://test");
        
        vm.prank(alice);
        uint256 notCloneable = agentFactory.mintAgent(keccak256("notcloneable"), 100, 1000000, false, "ipfs://test");

        assertTrue(clone.canClone(cloneable));
        assertFalse(clone.canClone(notCloneable));
        assertFalse(clone.canClone(999)); // Non-existent
    }

    function test_Clone_TotalClones() public {
        vm.prank(alice);
        uint256 originalId = agentFactory.mintAgent(keccak256("orig"), 100, 1000000, true, "ipfs://test");

        IClone.CloneParams memory params = IClone.CloneParams({
            chainId: 1, licensePrice: 500000, model: "m", licenses: 50
        });

        vm.prank(bob);
        clone.cloneAgent(originalId, params, "ipfs://c1");
        
        assertEq(clone.totalClones(), 1);
    }

    function test_Clone_GetAgentFactory() public {
        assertEq(clone.getAgentFactory(), address(agentFactory));
    }

    function test_Clone_CannotCloneNonCloneable() public {
        vm.prank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("nc"), 100, 1000000, false, "ipfs://test");

        IClone.CloneParams memory params = IClone.CloneParams({
            chainId: 1, licensePrice: 500000, model: "gpt-4", licenses: 50
        });

        vm.prank(bob);
        vm.expectRevert();
        clone.cloneAgent(agentId, params, "ipfs://clone");
    }

    // =============================================================================
    // Warp Tests - ALL Functions
    // =============================================================================

    function test_Warp_WarpAgent() public {
        bytes32 externalHash = keccak256("external-agent");
        
        vm.prank(bob);
        uint256 warpedId = warp.warpAgent(
            externalHash,
            alice,
            100,
            1000000,
            "ipfs://warped"
        );

        assertTrue(warp.isWarped(warpedId));
        
        Warp.WarpedAgentData memory data = warp.getWarpedData(warpedId);
        assertEq(data.originalCreator, alice);
        assertEq(data.warper, bob);
        assertEq(data.originalAgentHash, externalHash);
    }

    function test_Warp_RoyaltySplit_CreatorKnown() public {
        vm.prank(bob);
        uint256 warpedId = warp.warpAgent(keccak256("ext1"), alice, 100, 1000000, "ipfs://test");

        (uint256 creatorShare, uint256 treasuryShare, uint256 warperShare) = 
            warp.calculateRoyaltySplit(warpedId, 1000);

        assertEq(creatorShare, 100);
        assertEq(treasuryShare, 100);
        assertEq(warperShare, 800);
    }

    function test_Warp_RoyaltySplit_CreatorUnknown() public {
        vm.prank(bob);
        uint256 warpedId = warp.warpAgent(keccak256("ext2"), address(0), 100, 1000000, "ipfs://test");

        (uint256 creatorShare, uint256 treasuryShare, uint256 warperShare) = 
            warp.calculateRoyaltySplit(warpedId, 1000);

        assertEq(creatorShare, 0);
        assertEq(treasuryShare, 200);
        assertEq(warperShare, 800);
    }

    function test_Warp_DistributeRoyalty() public {
        vm.prank(bob);
        uint256 warpedId = warp.warpAgent(keccak256("ext3"), address(0), 100, 1000000, "ipfs://test");

        warp.distributeRoyalty(warpedId, 1000);
        
        Warp.WarpedAgentData memory data = warp.getWarpedData(warpedId);
        assertEq(data.accumulatedRoyalties, 100); // 10% of 1000
    }

    function test_Warp_TransferUnclaimedRoyalties() public {
        vm.prank(bob);
        uint256 warpedId = warp.warpAgent(keccak256("ext4"), address(0), 100, 1000000, "ipfs://test");

        warp.distributeRoyalty(warpedId, 1000);

        vm.prank(treasury);
        warp.transferUnclaimedRoyalties(warpedId, alice);

        Warp.WarpedAgentData memory data = warp.getWarpedData(warpedId);
        assertEq(data.originalCreator, alice);
        assertTrue(data.royaltiesClaimed);
    }

    function test_Warp_GetRoyaltyPercentages() public {
        (uint8 creator, uint8 treas, uint8 warper) = warp.getRoyaltyPercentages();
        assertEq(creator, 10);
        assertEq(treas, 10);
        assertEq(warper, 80);
    }

    function test_Warp_GetTreasury() public {
        assertEq(warp.getTreasury(), treasury);
    }

    function test_Warp_TotalWarped() public {
        vm.prank(bob);
        warp.warpAgent(keccak256("w1"), alice, 100, 1000000, "ipfs://test");
        
        assertEq(warp.totalWarped(), 1);
    }

    function test_Warp_GetWarpedAgentId() public {
        bytes32 hash = keccak256("w2");
        vm.prank(bob);
        uint256 warpedId = warp.warpAgent(hash, alice, 100, 1000000, "ipfs://test");
        
        assertEq(warp.getWarpedAgentId(hash), warpedId);
    }

    function test_Warp_IsExternalWarped() public {
        bytes32 hash = keccak256("w3");
        assertFalse(warp.isExternalWarped(hash));
        
        vm.prank(bob);
        warp.warpAgent(hash, alice, 100, 1000000, "ipfs://test");
        
        assertTrue(warp.isExternalWarped(hash));
    }

    function test_Warp_GetAgentFactory() public {
        assertEq(warp.getAgentFactory(), address(agentFactory));
    }

    // =============================================================================
    // Workflow (ERC-7401) Tests - ALL Functions
    // =============================================================================

    function test_Workflow_MintWorkflow() public {
        vm.startPrank(alice);
        uint256 agent1 = agentFactory.mintAgent(keccak256("ma1"), 100, 500000, false, "ipfs://1");
        uint256 agent2 = agentFactory.mintAgent(keccak256("ma2"), 100, 300000, false, "ipfs://2");
        vm.stopPrank();

        uint256[] memory agentIds = new uint256[](2);
        agentIds[0] = agent1;
        agentIds[1] = agent2;

        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test Workflow",
            description: "A test workflow",
            banner: "ipfs://banner",
            workflowCardUri: "",
            units: 50,
            leaseEnabled: true,
            leaseDuration: 30,
            leasePercent: 15,
            hasCoordinator: false,
            coordinatorModel: ""
        });

        // Bob mints the workflow (needs to approve USDC for agent prices)
        uint256 totalPrice = 500000 + 300000; // agent1 + agent2 prices
        vm.startPrank(bob);
        usdc.approve(address(workflow), totalPrice);
        uint256 workflowId = workflow.mintWorkflow(params, agentIds);
        vm.stopPrank();

        assertEq(workflowId, 1);
        assertEq(workflow.totalWorkflows(), 1);
        
        IWorkflow.WorkflowData memory data = workflow.getWorkflowData(workflowId);
        assertEq(data.title, "Test Workflow");
        assertEq(data.totalPrice, 800000);
        assertEq(data.workflowCardUri, "");  // workflowCardUri set in params

        uint256[] memory agents = workflow.getAgents(workflowId);
        assertEq(agents.length, 2);
        
        // Verify alice (agent creator) received payment
        // Note: distributor splits payments, so check sum went through
    }

    function test_Workflow_AddRemoveAgent() public {
        vm.startPrank(alice);
        uint256 agentId = agentFactory.mintAgent(keccak256("addrem"), 100, 500000, false, "ipfs://1");

        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        workflow.addAgent(workflowId, agentId);
        assertEq(workflow.getAgentCount(workflowId), 1);

        workflow.removeAgent(workflowId, agentId);
        assertEq(workflow.getAgentCount(workflowId), 0);
        
        vm.stopPrank();
    }

    function test_Workflow_SetCoordinator() public {
        vm.startPrank(alice);
        uint256 coordAgent = agentFactory.mintAgent(keccak256("coord"), 100, 500000, false, "ipfs://1");

        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        workflow.setCoordinator(workflowId, true, "gpt-4");

        IWorkflow.WorkflowData memory data = workflow.getWorkflowData(workflowId);
        assertTrue(data.hasCoordinator);
        assertEq(data.coordinatorModel, "gpt-4");
        
        vm.stopPrank();
    }

    function test_Workflow_UpdateLeaseSettings() public {
        vm.startPrank(alice);
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        workflow.updateLeaseSettings(workflowId, true, 60, 15);

        IWorkflow.WorkflowData memory data = workflow.getWorkflowData(workflowId);
        assertTrue(data.leaseEnabled);
        assertEq(data.leaseDuration, 60);
        assertEq(data.leasePercent, 15);
        
        vm.stopPrank();
    }

    function test_Workflow_IsComplete() public {
        vm.startPrank(alice);
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        assertTrue(workflow.isComplete(workflowId));
        vm.stopPrank();
    }

    function test_Workflow_HasAvailableUnits() public {
        vm.startPrank(alice);
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        assertTrue(workflow.hasAvailableUnits(workflowId));
        vm.stopPrank();
    }

    function test_Workflow_ConsumeUnit() public {
        vm.startPrank(alice);
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        uint256 unit = workflow.consumeUnit(workflowId, bob);
        assertEq(unit, 1);
    }

    function test_Workflow_CalculateTotalPrice() public {
        vm.startPrank(alice);
        uint256 agent1 = agentFactory.mintAgent(keccak256("tp1"), 100, 500000, false, "ipfs://1");
        vm.stopPrank();

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agent1;

        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        // Bob mints the workflow - needs to approve USDC for agent price
        vm.startPrank(bob);
        usdc.approve(address(workflow), 500000);
        uint256 workflowId = workflow.mintWorkflow(params, agentIds);
        vm.stopPrank();

        assertEq(workflow.calculateTotalPrice(workflowId), 500000); // totalPrice only (x402Price removed) // 500000 + 100000
    }

    function test_Workflow_GetWorkflowsByCreator() public {
        vm.startPrank(alice);
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        workflow.mintWorkflow(params, empty);
        workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        uint256[] memory workflows = workflow.getWorkflowsByCreator(alice);
        assertEq(workflows.length, 2);
    }

    function test_Workflow_GetCompleteWorkflows() public {
        vm.startPrank(alice);
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        uint256[] memory complete = workflow.getCompleteWorkflows();
        assertEq(complete.length, 1);
    }

    function test_Workflow_GetWorkflowsWithRFA() public {
        uint256[] memory withRFA = workflow.getWorkflowsWithRFA();
        assertEq(withRFA.length, 0);
    }

    function test_Workflow_GetAgentFactory() public {
        assertEq(workflow.getAgentFactory(), address(agentFactory));
    }

    function test_Workflow_MaxLeasePercent() public {
        assertEq(workflow.MAX_LEASE_PERCENT(), 20);
    }

    function test_USDCResolution_AcrossSupportedChains() public {
        _assertUSDCResolutionForChain(43113, SUPPORTED_USDC);
        _assertUSDCResolutionForChain(43114, AVALANCHE_USDC);
    }

    function test_Workflow_UnsupportedChainReverts() public {
        uint256 unsupportedChainId = 777777;
        vm.chainId(unsupportedChainId);

        AgentFactory localFactory = new AgentFactory(address(this));
        vm.expectRevert(abi.encodeWithSelector(Workflow.UnsupportedChain.selector, unsupportedChainId));
        new Workflow(address(localFactory), address(this));
    }

    function test_Workflow_ERC7401_ChildrenOf() public {
        vm.startPrank(alice);
        uint256 agent1 = agentFactory.mintAgent(keccak256("c1"), 100, 500000, false, "ipfs://1");
        vm.stopPrank();

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agent1;

        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        // Bob mints the workflow - needs to approve USDC for agent price
        vm.startPrank(bob);
        usdc.approve(address(workflow), 500000);
        uint256 workflowId = workflow.mintWorkflow(params, agentIds);
        vm.stopPrank();

        IWorkflow.Child[] memory children = workflow.childrenOf(workflowId);
        assertEq(children.length, 1);
    }

    function test_Workflow_ERC7401_ChildCount() public {
        vm.startPrank(alice);
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        assertEq(workflow.childCount(workflowId), 0);
    }

    function test_Workflow_ERC7401_ParentOf() public {
        vm.startPrank(alice);
        uint256 agent1 = agentFactory.mintAgent(keccak256("p1"), 100, 500000, false, "ipfs://1");
        vm.stopPrank();

        uint256[] memory agentIds = new uint256[](1);
        agentIds[0] = agent1;

        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        // Bob mints the workflow - needs to approve USDC for agent price
        vm.startPrank(bob);
        usdc.approve(address(workflow), 500000);
        uint256 workflowId = workflow.mintWorkflow(params, agentIds);
        vm.stopPrank();

        (bool hasParent, address parentContract, uint256 parentId) = workflow.parentOf(address(agentFactory), agent1);
        assertTrue(hasParent);
        assertEq(parentContract, address(workflow));
        assertEq(parentId, workflowId);
    }

    // =============================================================================
    // RFA Tests - ALL Functions
    // =============================================================================

    function test_RFA_CreateAndAccept() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);

        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("data-analysis");
        
        uint256 rfaId = rfa.createRFA(
            workflowId, "Need Data Analyst",
            "Need an agent for data analysis",
            skills, 1000000
        );
        vm.stopPrank();

        assertFalse(workflow.isComplete(workflowId));
        assertEq(rfa.totalEscrowed(), 1000000);

        vm.startPrank(bob);
        uint256 agentId = agentFactory.mintAgent(keccak256("analyst"), 100, 500000, false, "ipfs://analyst");
        rfa.submitAgent(rfaId, agentId);
        vm.stopPrank();

        uint256 bobBalanceBefore = usdc.balanceOf(bob);
        
        vm.prank(alice);
        rfa.acceptAgent(rfaId, agentId);

        assertEq(usdc.balanceOf(bob), bobBalanceBefore + 1000000);
        assertEq(rfa.totalEscrowed(), 0);
        assertTrue(workflow.isComplete(workflowId));
    }

    function test_RFA_Cancel() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);
        
        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("skill");
        
        uint256 rfaId = rfa.createRFA(workflowId, "Title", "Desc", skills, 1000000);

        uint256 balanceBefore = usdc.balanceOf(alice);

        rfa.cancelRFA(rfaId);

        assertEq(usdc.balanceOf(alice), balanceBefore + 1000000);
        assertEq(rfa.totalEscrowed(), 0);

        vm.stopPrank();
    }

    function test_RFA_GetRFAData() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);
        
        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("skill");
        
        uint256 rfaId = rfa.createRFA(workflowId, "Title", "Desc", skills, 1000000);
        vm.stopPrank();

        RFA.RFARequest memory data = rfa.getRFAData(rfaId);
        assertEq(data.workflowId, workflowId);
        assertEq(data.title, "Title");
        assertEq(data.offerAmount, 1000000);
        assertEq(data.publisher, alice);
    }

    function test_RFA_GetSubmissions() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);
        
        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("skill");
        
        uint256 rfaId = rfa.createRFA(workflowId, "Title", "Desc", skills, 1000000);
        vm.stopPrank();

        vm.prank(bob);
        uint256 agentId = agentFactory.mintAgent(keccak256("sub1"), 100, 500000, false, "ipfs://test");
        
        vm.prank(bob);
        rfa.submitAgent(rfaId, agentId);

        RFA.Submission[] memory subs = rfa.getSubmissions(rfaId);
        assertEq(subs.length, 1);
        assertEq(subs[0].agentId, agentId);
    }

    function test_RFA_GetRFAStatus() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);
        
        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("skill");
        
        uint256 rfaId = rfa.createRFA(workflowId, "Title", "Desc", skills, 1000000);
        vm.stopPrank();

        assertEq(uint256(rfa.getRFAStatus(rfaId)), 1); // 1 = Open
    }

    function test_RFA_GetOpenRFAs() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);
        
        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("skill");
        
        rfa.createRFA(workflowId, "Title", "Desc", skills, 1000000);
        vm.stopPrank();

        uint256[] memory openRFAs = rfa.getOpenRFAs();
        assertEq(openRFAs.length, 1);
    }

    function test_RFA_GetRFAsForWorkflow() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);
        
        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("skill");
        
        rfa.createRFA(workflowId, "Title", "Desc", skills, 1000000);
        vm.stopPrank();

        uint256[] memory rfas = rfa.getRFAsForWorkflow(workflowId);
        assertEq(rfas.length, 1);
    }

    function test_RFA_GetRFAsByPublisher() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);
        
        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("skill");
        
        rfa.createRFA(workflowId, "Title", "Desc", skills, 1000000);
        vm.stopPrank();

        uint256[] memory rfas = rfa.getRFAsByPublisher(alice);
        assertEq(rfas.length, 1);
    }

    function test_RFA_TotalRFAs() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: false,
            leaseDuration: 0, leasePercent: 0,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);

        usdc.approve(address(rfa), 1000000);
        
        bytes32[] memory skills = new bytes32[](1);
        skills[0] = keccak256("skill");
        
        rfa.createRFA(workflowId, "Title", "Desc", skills, 1000000);
        vm.stopPrank();

        assertEq(rfa.totalRFAs(), 1);
    }

    function test_RFA_GetUSDC() public {
        assertEq(rfa.getUSDC(), address(usdc));
    }

    function test_RFA_UnsupportedChainReverts() public {
        uint256 unsupportedChainId = 777777;
        vm.chainId(unsupportedChainId);

        AgentFactory localFactory = new AgentFactory(address(this));
        vm.expectRevert(abi.encodeWithSelector(RFA.UnsupportedChain.selector, unsupportedChainId));
        new RFA(address(0x1234), address(localFactory), address(this));
    }

    // =============================================================================
    // Lease Tests - ALL Functions
    // =============================================================================

    function test_Lease_CreateLease() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Leasable Workflow",
            description: "Test",
            banner: "",
            workflowCardUri: "",
            units: 10,
            leaseEnabled: true,
            leaseDuration: 30,
            leasePercent: 15,
            hasCoordinator: false,
            coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        vm.prank(bob);
        uint256 leaseId = lease.createLease(workflowId, 30);

        assertTrue(lease.isLeased(workflowId));
        assertEq(lease.getActiveLeaseFor(workflowId), leaseId);

        Lease.LeaseData memory data = lease.getLeaseData(leaseId);
        assertEq(data.workflowId, workflowId);
        assertEq(data.leaser, bob);
        assertEq(data.creatorPercent, 15);
    }

    function test_Lease_TerminateLease() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: true,
            leaseDuration: 30, leasePercent: 15,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        vm.prank(bob);
        uint256 leaseId = lease.createLease(workflowId, 30);

        vm.prank(bob);
        lease.terminateLease(leaseId);

        assertFalse(lease.isLeased(workflowId));
    }

    function test_Lease_CalculateFeeSplit() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: true,
            leaseDuration: 30, leasePercent: 20,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        vm.prank(bob);
        uint256 leaseId = lease.createLease(workflowId, 30);

        (uint256 creatorShare, uint256 leaserShare) = lease.calculateFeeSplit(leaseId, 1000);
        assertEq(creatorShare, 200);
        assertEq(leaserShare, 800);
    }

    function test_Lease_GetLeaseStatus() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: true,
            leaseDuration: 30, leasePercent: 15,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        vm.prank(bob);
        uint256 leaseId = lease.createLease(workflowId, 30);

        assertEq(uint256(lease.getLeaseStatus(leaseId)), 1); // 1 = Active
    }

    function test_Lease_GetLeasesFor() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: true,
            leaseDuration: 30, leasePercent: 15,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        vm.prank(bob);
        lease.createLease(workflowId, 30);

        uint256[] memory leases = lease.getLeasesFor(bob);
        assertEq(leases.length, 1);
    }

    function test_Lease_TotalLeases() public {
        vm.startPrank(alice);
        
        IWorkflow.MintParams memory params = IWorkflow.MintParams({
            title: "Test", description: "Test", banner: "",
            workflowCardUri: "",
            units: 10, leaseEnabled: true,
            leaseDuration: 30, leasePercent: 15,
            hasCoordinator: false, coordinatorModel: ""
        });

        uint256[] memory empty = new uint256[](0);
        uint256 workflowId = workflow.mintWorkflow(params, empty);
        vm.stopPrank();

        vm.prank(bob);
        lease.createLease(workflowId, 30);

        assertEq(lease.totalLeases(), 1);
    }

    function test_Lease_MaxLeasePercent() public {
        assertEq(lease.MAX_LEASE_PERCENT(), 20);
    }

    function test_Lease_GetUSDC() public {
        assertEq(lease.getUSDC(), address(usdc));
    }

    function test_Lease_UnsupportedChainReverts() public {
        uint256 unsupportedChainId = 777777;
        vm.chainId(unsupportedChainId);

        vm.expectRevert(abi.encodeWithSelector(Lease.UnsupportedChain.selector, unsupportedChainId));
        new Lease(address(0x1234), address(this));
    }

    function _assertUSDCResolutionForChain(uint256 chainId, address expectedUSDC) internal {
        vm.chainId(chainId);

        AgentFactory localFactory = new AgentFactory(address(this));
        Workflow localWorkflow = new Workflow(address(localFactory), address(this));
        RFA localRfa = new RFA(address(localWorkflow), address(localFactory), address(this));
        Lease localLease = new Lease(address(localWorkflow), address(this));

        assertEq(address(localWorkflow.paymentToken()), expectedUSDC);
        assertEq(localRfa.getUSDC(), expectedUSDC);
        assertEq(localLease.getUSDC(), expectedUSDC);
    }

    // =============================================================================
    // Royalties Tests - ALL Functions
    // =============================================================================

    function test_Royalties_RoyaltyInfo() public {
        (address receiver, uint256 amount) = royalties.royaltyInfo(1, 10000);
        
        assertEq(receiver, treasury);
        assertEq(amount, 500); // 5% of 10000
    }

    function test_Royalties_SetTokenRoyalty() public {
        royalties.setTokenRoyalty(42, bob, 1000); // 10%
        
        (address receiver, uint256 amount) = royalties.royaltyInfo(42, 10000);
        
        assertEq(receiver, bob);
        assertEq(amount, 1000);
    }

    function test_Royalties_SetDefaultRoyalty() public {
        royalties.setDefaultRoyalty(bob, 1000);
        
        (address receiver, uint96 feeNumerator) = royalties.getDefaultRoyalty();
        assertEq(receiver, bob);
        assertEq(feeNumerator, 1000);
    }

    function test_Royalties_DeleteTokenRoyalty() public {
        royalties.setTokenRoyalty(42, bob, 1000);
        royalties.deleteTokenRoyalty(42);
        
        (address receiver, uint256 amount) = royalties.royaltyInfo(42, 10000);
        assertEq(receiver, treasury); // Back to default
    }

    function test_Royalties_GetDefaultRoyalty() public {
        (address receiver, uint96 feeNumerator) = royalties.getDefaultRoyalty();
        assertEq(receiver, treasury);
        assertEq(feeNumerator, 500);
    }

    function test_Royalties_CalculateRoyalty() public {
        uint256 royalty = royalties.calculateRoyalty(1, 10000);
        assertEq(royalty, 500);
    }

    function test_Royalties_SupportsInterface() public {
        assertTrue(royalties.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(royalties.supportsInterface(0x2a55205a)); // EIP-2981
    }

    function test_Royalties_FeeDenominator() public {
        assertEq(royalties.FEE_DENOMINATOR(), 10000);
    }

    function test_Royalties_TransferAdmin() public {
        royalties.transferAdmin(bob);
        assertEq(royalties.getAdmin(), bob);
    }

    // =============================================================================
    // Distributor Tests - ALL Functions
    // =============================================================================

    function test_Distributor_Distribute() public {
        vm.deal(charlie, 10 ether);
        
        IDistributor.Recipient[] memory recipients = new IDistributor.Recipient[](3);
        recipients[0] = IDistributor.Recipient(alice, 1000);
        recipients[1] = IDistributor.Recipient(treasury, 1000);
        recipients[2] = IDistributor.Recipient(bob, 8000);

        uint256 aliceBalanceBefore = alice.balance;
        uint256 bobBalanceBefore = bob.balance;

        vm.prank(charlie);
        distributor.distribute{value: 1 ether}(recipients, 1 ether, address(0));

        assertEq(alice.balance, aliceBalanceBefore + 0.1 ether);
        assertEq(bob.balance, bobBalanceBefore + 0.8 ether);
    }

    function test_Distributor_CalculateDistribution() public {
        IDistributor.Recipient[] memory recipients = new IDistributor.Recipient[](2);
        recipients[0] = IDistributor.Recipient(alice, 3000);
        recipients[1] = IDistributor.Recipient(bob, 7000);

        uint256[] memory amounts = distributor.calculateDistribution(recipients, 1000);
        assertEq(amounts[0], 300);
        assertEq(amounts[1], 700);
    }

    function test_Distributor_ValidateRecipients() public {
        IDistributor.Recipient[] memory valid = new IDistributor.Recipient[](2);
        valid[0] = IDistributor.Recipient(alice, 5000);
        valid[1] = IDistributor.Recipient(bob, 5000);

        assertTrue(distributor.validateRecipients(valid));

        IDistributor.Recipient[] memory invalid = new IDistributor.Recipient[](2);
        invalid[0] = IDistributor.Recipient(alice, 3000);
        invalid[1] = IDistributor.Recipient(bob, 3000);

        assertFalse(distributor.validateRecipients(invalid));
    }

    function test_Distributor_DistributeWarpRoyalties() public {
        vm.deal(charlie, 10 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(charlie);
        distributor.distributeWarpRoyalties{value: 1 ether}(alice, bob, 1 ether, address(0));

        assertEq(alice.balance, aliceBalanceBefore + 0.1 ether);
    }

    function test_Distributor_DistributeLeaseFees() public {
        vm.deal(charlie, 10 ether);

        uint256 aliceBalanceBefore = alice.balance;

        vm.prank(charlie);
        distributor.distributeLeaseFeeds{value: 1 ether}(alice, bob, 20, 1 ether, address(0));

        assertEq(alice.balance, aliceBalanceBefore + 0.2 ether);
    }

    function test_Distributor_GetTreasury() public {
        assertEq(distributor.getTreasury(), treasury);
    }

    function test_Distributor_BasisPoints() public {
        assertEq(distributor.BASIS_POINTS(), 10000);
    }

    function test_Distributor_TransferAdmin() public {
        distributor.transferAdmin(bob);
        assertEq(distributor.getAdmin(), bob);
    }

    // =============================================================================
    // AgentManager Tests - ALL Functions
    // =============================================================================

    function test_AgentManager_GetDelegation() public {
        assertEq(agentManager.getDelegation(), address(delegation));
    }

    function test_AgentManager_GetContract() public {
        assertEq(agentManager.getContract(keccak256("AGENT_FACTORY")), address(agentFactory));
    }

    function test_AgentManager_GetAdmin() public {
        assertEq(agentManager.getAdmin(), address(this));
    }

    function test_AgentManager_TransferAdmin() public {
        agentManager.transferAdmin(bob);
        assertEq(agentManager.getAdmin(), bob);
    }

    function test_AgentManager_Pause() public {
        agentManager.pause();
        assertTrue(agentManager.isPaused());
        
        agentManager.unpause();
        assertFalse(agentManager.isPaused());
    }

    function test_AgentManager_GetAgentFactory() public {
        assertEq(agentManager.getAgentFactory(), address(agentFactory));
    }

    function test_AgentManager_GetWorkflow() public {
        assertEq(agentManager.getWorkflow(), address(workflow));
    }

    function test_AgentManager_GetRFA() public {
        assertEq(agentManager.getRFA(), address(rfa));
    }

    function test_AgentManager_GetAllContracts() public {
        (
            address af, address m, address c, address w,
            address l, address r, address roy, address dist
        ) = agentManager.getAllContracts();

        assertEq(af, address(agentFactory));
        assertEq(m, address(workflow));
        assertEq(c, address(clone));
        assertEq(w, address(warp));
        assertEq(l, address(lease));
        assertEq(r, address(rfa));
        assertEq(roy, address(royalties));
        assertEq(dist, address(distributor));
    }

    // =============================================================================
    // Delegation Tests - ALL Functions
    // =============================================================================

    function test_Delegation_GetManager() public {
        assertEq(delegation.getManager(), address(agentManager));
    }

    function test_Delegation_IsInitialized() public {
        assertTrue(delegation.isInitialized());
    }

    function test_Delegation_GetModule() public {
        assertEq(delegation.getModule(keccak256("MODULE_CLONE")), address(clone));
        assertEq(delegation.getModule(keccak256("MODULE_WARP")), address(warp));
        assertEq(delegation.getModule(keccak256("MODULE_LEASE")), address(lease));
    }

    // =============================================================================
    // Utils Tests - ALL Functions
    // =============================================================================

    function test_Utils_Constants() public {
        assertEq(utils.USDC_DECIMALS(), 6);
        assertEq(utils.BASE_PRICE_PER_TOKEN(), 1);
        assertEq(utils.MAX_TOKENS_PER_CALL(), 100000);
    }

    function test_Utils_SetContracts() public {
        utils.setContracts(address(0x1), address(0x2), address(0x3));
        
        assertEq(utils.agentManager(), address(0x1));
        assertEq(utils.agentFactory(), address(0x2));
        assertEq(utils.workflowContract(), address(0x3));
    }

    function test_Utils_TransferAdmin() public {
        utils.transferAdmin(bob);
        assertEq(utils.getAdmin(), bob);
    }

    // =============================================================================
    // Integration Test
    // =============================================================================

    function test_Integration_FullWorkflow() public {
        // 1. Alice creates agents
        vm.startPrank(alice);
        uint256 agent1 = agentFactory.mintAgent(keccak256("a1"), 100, 500000, true, "ipfs://1");
        uint256 agent2 = agentFactory.mintAgent(keccak256("a2"), 100, 300000, false, "ipfs://2");
        vm.stopPrank();

        // 2. Bob clones agent1
        IClone.CloneParams memory cloneParams = IClone.CloneParams({
            chainId: 1, licensePrice: 400000, model: "clone-model", licenses: 50
        });

        vm.prank(bob);
        uint256 clonedAgent = clone.cloneAgent(agent1, cloneParams, "ipfs://clone");

        // 3. Charlie warps an external agent
        vm.prank(charlie);
        uint256 warpedAgent = warp.warpAgent(
            keccak256("external"), address(0), 100, 200000, "ipfs://warped"
        );

        // 4. Alice creates a Workflow workflow
        uint256[] memory agents = new uint256[](3);
        agents[0] = agent2;
        agents[1] = clonedAgent;
        agents[2] = warpedAgent;

        IWorkflow.MintParams memory workflowParams = IWorkflow.MintParams({
            title: "Multi-Agent Workflow",
            description: "Combines multiple agents",
            banner: "ipfs://banner",
            workflowCardUri: "",
            units: 25,
            leaseEnabled: true,
            leaseDuration: 60,
            leasePercent: 10,
            hasCoordinator: true,
            coordinatorModel: "asi1-agentic"
        });

        // Alice needs to approve USDC for the total price of agents (300000 + 400000 + 200000 = 900000)
        vm.startPrank(alice);
        usdc.approve(address(workflow), 900000);
        uint256 workflowId = workflow.mintWorkflow(workflowParams, agents);
        vm.stopPrank();

        // 5. Verify Workflow
        IWorkflow.WorkflowData memory data = workflow.getWorkflowData(workflowId);
        assertEq(data.title, "Multi-Agent Workflow");
        assertEq(data.totalPrice, 900000);
        assertEq(workflow.getAgentCount(workflowId), 3);
        assertTrue(workflow.isComplete(workflowId));

        // 6. Bob leases the workflow
        vm.prank(bob);
        uint256 leaseId = lease.createLease(workflowId, 30);

        assertTrue(lease.isLeased(workflowId));

        console.log("Integration test passed!");
    }
}

// =============================================================================
// Mock ERC20 for Testing
// =============================================================================

contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;
    
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
