// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

// Import all contracts
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

/**
 * @title ComposeBNB
 * @notice Legacy manual deployment script for the Manowar Protocol on BNB Testnet
 * 
 * Deploy order:
 * 1. Royalties + Distributor (no dependencies)
 * 2. AgentFactory (ERC-8004 Registry)
 * 3. Clone, Warp (depends on AgentFactory)
 * 4. Workflow (depends on AgentFactory)
 * 5. RFA (depends on Workflow, AgentFactory)
 * 6. Lease (depends on Workflow)
 * 7. Delegation (references Clone, Warp, Lease)
 * 8. AgentManager (links all contracts)
 * 9. Utils (helper utilities)
 * 
 * Network: BNB Testnet (Chain ID: 97)
 * @dev Current protocol payment-token resolution is chain-gated in Workflow/RFA/Lease.
 * Keep this script BNB-labeled; use compose.s.sol for supported EVM deployments.
 */
contract ComposeBNB is Script {
    // =============================================================================
    // Configuration
    // =============================================================================

    uint256 constant BNB_TESTNET_CHAIN_ID = 97;
    
    // Treasury wallet (from .env)
    address constant TREASURY = 0x058271e764154c322F3D3dDC18aF44F7d91B1c80;
    
    // Default royalty: 5% (500 basis points)
    uint96 constant DEFAULT_ROYALTY_FEE = 500;

    // =============================================================================
    // Deployed Addresses (filled during deployment)
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

    // =============================================================================
    // Main Deployment Function
    // =============================================================================

    function run() external {
        // Get deployer private key from environment (hex string)
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== Manowar Protocol Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Network: BNB Testnet (97)");
        console.log("Chain ID:", block.chainid);
        console.log("Treasury:", TREASURY);
        console.log("");
        require(block.chainid == BNB_TESTNET_CHAIN_ID, "ComposeBNB: BNB testnet only");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy support contracts (no dependencies)
        console.log("Step 1: Deploying support contracts...");
        royalties = new Royalties(TREASURY, DEFAULT_ROYALTY_FEE, deployer);
        console.log("  Royalties:", address(royalties));
        
        distributor = new Distributor(TREASURY, deployer);
        console.log("  Distributor:", address(distributor));

        // Step 2: Deploy AgentFactory (ERC-8004 Identity Registry)
        console.log("");
        console.log("Step 2: Deploying AgentFactory...");
        agentFactory = new AgentFactory(deployer);
        console.log("  AgentFactory:", address(agentFactory));

        // Step 3: Deploy Clone and Warp
        console.log("");
        console.log("Step 3: Deploying Clone and Warp...");
        clone = new Clone(address(agentFactory));
        console.log("  Clone:", address(clone));
        
        warp = new Warp(address(agentFactory), TREASURY);
        console.log("  Warp:", address(warp));

        // Step 4: Deploy Workflow (ERC-7401)
        console.log("");
        console.log("Step 4: Deploying Workflow...");
        workflow = new Workflow(address(agentFactory), deployer);
        console.log("  Workflow:", address(workflow));

        // Step 5: Deploy RFA
        console.log("");
        console.log("Step 5: Deploying RFA...");
        rfa = new RFA(address(workflow), address(agentFactory), deployer);
        console.log("  RFA:", address(rfa));

        // Step 6: Deploy Lease
        console.log("");
        console.log("Step 6: Deploying Lease...");
        lease = new Lease(address(workflow), deployer);
        console.log("  Lease:", address(lease));

        console.log("");
        console.log("Step 6b: Deploying ERC8004 Reputation and Validation...");
        reputation = new Reputation(address(agentFactory));
        console.log("  Reputation:", address(reputation));
        validation = new Validation(address(agentFactory));
        console.log("  Validation:", address(validation));

        // Step 7: Deploy Delegation
        console.log("");
        console.log("Step 7: Deploying Delegation...");
        delegation = new Delegation();
        console.log("  Delegation:", address(delegation));

        // Step 8: Deploy AgentManager
        console.log("");
        console.log("Step 8: Deploying AgentManager...");
        agentManager = new AgentManager(deployer);
        console.log("  AgentManager:", address(agentManager));

        // Step 9: Deploy Utils helper
        console.log("");
        console.log("Step 9: Deploying Utils helper...");
        utils = new Utils(address(agentManager), address(agentFactory), address(workflow));
        console.log("  Utils:", address(utils));

        // Step 10: Initialize and link contracts
        console.log("");
        console.log("Step 10: Initializing ecosystem...");
        
        // Initialize Delegation
        delegation.initialize(address(agentManager));
        console.log("  Delegation initialized");

        // Initialize AgentManager with all contracts
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
        console.log("  AgentManager ecosystem initialized");

        // Authorize contracts in AgentFactory
        agentFactory.authorizeConsumer(address(clone));
        agentFactory.authorizeConsumer(address(warp));
        agentFactory.authorizeConsumer(address(workflow));
        console.log("  AgentFactory consumers authorized");

        // Set RFA contract in Workflow
        workflow.setRFAContract(address(rfa));
        workflow.setLeaseContract(address(lease));
        workflow.setDistributor(address(distributor));
        workflow.setTreasury(TREASURY);
        console.log("  Workflow RFA/Lease/Distributor/Treasury contracts set");

        vm.stopBroadcast();

        // Print deployment summary
        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("");
        console.log("Contract Addresses:");
        console.log("-------------------");
        console.log("AgentFactory:", address(agentFactory));
        console.log("Clone:", address(clone));
        console.log("Warp:", address(warp));
        console.log("Workflow:", address(workflow));
        console.log("RFA:", address(rfa));
        console.log("Lease:", address(lease));
        console.log("Reputation:", address(reputation));
        console.log("Validation:", address(validation));
        console.log("Royalties:", address(royalties));
        console.log("Distributor:", address(distributor));
        console.log("Delegation:", address(delegation));
        console.log("AgentManager:", address(agentManager));
        console.log("Utils:", address(utils));
        console.log("");
        console.log("Save these addresses for frontend integration!");
    }

    // =============================================================================
    // Individual Deployment Functions (for testing/upgrades)
    // =============================================================================

    function deployAgentFactory() external returns (address) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.addr(deployerPrivateKey);
        agentFactory = new AgentFactory(deployer);
        vm.stopBroadcast();
        return address(agentFactory);
    }

    function deployWorkflow(address _agentFactory, address _admin) external returns (address) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        workflow = new Workflow(_agentFactory, _admin);
        vm.stopBroadcast();
        return address(workflow);
    }

    function deployRFA(address _workflow, address _agentFactory) external returns (address) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        address deployer = vm.addr(deployerPrivateKey);
        vm.startBroadcast(deployerPrivateKey);
        rfa = new RFA(_workflow, _agentFactory, deployer);
        vm.stopBroadcast();
        return address(rfa);
    }

    function deployUtilsPatch(
        address _agentManager,
        address _agentFactory,
        address _workflow
    ) external returns (address) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        utils = new Utils(_agentManager, _agentFactory, _workflow);
        vm.stopBroadcast();
        return address(utils);
    }
}
