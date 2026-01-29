// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

// Import all contracts
import {AgentFactory} from "../src/compose/agentfactory.sol";
import {Clone} from "../src/compose/clone.sol";
import {Warp} from "../src/compose/warp.sol";
import {Manowar} from "../src/compose/manowar.sol";
import {RFA} from "../src/compose/rfa.sol";
import {Lease} from "../src/compose/lease.sol";
import {Royalties} from "../src/compose/royalties.sol";
import {Distributor} from "../src/compose/distributor.sol";
import {Utils} from "../src/compose/utils.sol";
import {AgentManager} from "../src/compose/agentmanager.sol";
import {Delegation} from "../src/compose/delegation.sol";

/**
 * @title Compose
 * @notice Deployment script for the Manowar Protocol
 * 
 * Deploy order:
 * 1. Royalties + Distributor (no dependencies)
 * 2. AgentFactory (ERC-8004 Registry)
 * 3. Clone, Warp (depends on AgentFactory)
 * 4. Manowar (depends on AgentFactory)
 * 5. RFA (depends on Manowar, AgentFactory)
 * 6. Lease (depends on Manowar)
 * 7. Delegation (references Clone, Warp, Lease)
 * 8. AgentManager (links all contracts)
 * 9. Utils (helper utilities)
 * 
 * Supported Networks:
 * - Cronos Testnet (Chain ID: 338)
 * - Avalanche Fuji (Chain ID: 43113)
 */
contract Compose is Script {
    // =============================================================================
    // Configuration
    // =============================================================================

    // -------------------------------------------------------------------------
    // Cronos Testnet - Chain ID: 338
    // -------------------------------------------------------------------------
    address constant USDC_CRONOS_TESTNET = 0xc01efAaF7C5C61bEbFAeb358E1161b537b8bC0e0; // devUSDC.e
    
    // -------------------------------------------------------------------------
    // Avalanche Fuji - Chain ID: 43113
    // -------------------------------------------------------------------------
    address constant USDC_FUJI = 0x5425890298aed601595a70AB815c96711a31Bc65;
    
    // -------------------------------------------------------------------------
    // Shared Configuration
    // -------------------------------------------------------------------------
    
    // Treasury wallet (from .env)
    address constant TREASURY = 0x058271e764154c322F3D3dDC18aF44F7d91B1c80;
    
    // Default royalty: 5% (500 basis points)
    uint96 constant DEFAULT_ROYALTY_FEE = 500;
    
    // Active USDC address - change based on target network
    // For Cronos Testnet deployment, use: USDC_CRONOS_TESTNET
    // For Avalanche Fuji deployment, use: USDC_FUJI
    address constant ACTIVE_USDC = USDC_CRONOS_TESTNET;

    // =============================================================================
    // Deployed Addresses (filled during deployment)
    // =============================================================================

    AgentFactory public agentFactory;
    Clone public clone;
    Warp public warp;
    Manowar public manowar;
    RFA public rfa;
    Lease public lease;
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
        console.log("Network: Chain ID from RPC config");
        console.log("USDC:", ACTIVE_USDC);
        console.log("Treasury:", TREASURY);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy support contracts (no dependencies)
        console.log("Step 1: Deploying support contracts...");
        royalties = new Royalties(TREASURY, DEFAULT_ROYALTY_FEE);
        console.log("  Royalties:", address(royalties));
        
        distributor = new Distributor(TREASURY);
        console.log("  Distributor:", address(distributor));

        // Step 2: Deploy AgentFactory (ERC-8004 Identity Registry)
        console.log("");
        console.log("Step 2: Deploying AgentFactory...");
        agentFactory = new AgentFactory();
        console.log("  AgentFactory:", address(agentFactory));

        // Step 3: Deploy Clone and Warp
        console.log("");
        console.log("Step 3: Deploying Clone and Warp...");
        clone = new Clone(address(agentFactory));
        console.log("  Clone:", address(clone));
        
        warp = new Warp(address(agentFactory), TREASURY);
        console.log("  Warp:", address(warp));

        // Step 4: Deploy Manowar (ERC-7401)
        console.log("");
        console.log("Step 4: Deploying Manowar...");
        manowar = new Manowar(address(agentFactory), ACTIVE_USDC);
        console.log("  Manowar:", address(manowar));

        // Step 5: Deploy RFA
        console.log("");
        console.log("Step 5: Deploying RFA...");
        rfa = new RFA(ACTIVE_USDC, address(manowar), address(agentFactory));
        console.log("  RFA:", address(rfa));

        // Step 6: Deploy Lease
        console.log("");
        console.log("Step 6: Deploying Lease...");
        lease = new Lease(ACTIVE_USDC, address(manowar));
        console.log("  Lease:", address(lease));

        // Step 7: Deploy Delegation
        console.log("");
        console.log("Step 7: Deploying Delegation...");
        delegation = new Delegation();
        console.log("  Delegation:", address(delegation));

        // Step 8: Deploy AgentManager
        console.log("");
        console.log("Step 8: Deploying AgentManager...");
        agentManager = new AgentManager();
        console.log("  AgentManager:", address(agentManager));

        // Step 9: Deploy Utils helper
        console.log("");
        console.log("Step 9: Deploying Utils helper...");
        utils = new Utils(address(agentManager), address(agentFactory), address(manowar));
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
            address(manowar),
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
        agentFactory.authorizeConsumer(address(manowar));
        console.log("  AgentFactory consumers authorized");

        // Set RFA contract in Manowar
        manowar.setRFAContract(address(rfa));
        manowar.setLeaseContract(address(lease));
        manowar.setDistributor(address(distributor));
        manowar.setTreasury(TREASURY);
        console.log("  Manowar RFA/Lease/Distributor/Treasury contracts set");

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
        console.log("Manowar:", address(manowar));
        console.log("RFA:", address(rfa));
        console.log("Lease:", address(lease));
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
        agentFactory = new AgentFactory();
        vm.stopBroadcast();
        return address(agentFactory);
    }

    function deployManowar(address _agentFactory, address _paymentToken) external returns (address) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        manowar = new Manowar(_agentFactory, _paymentToken);
        vm.stopBroadcast();
        return address(manowar);
    }

    function deployRFA(address _manowar, address _agentFactory) external returns (address) {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        vm.startBroadcast(deployerPrivateKey);
        rfa = new RFA(ACTIVE_USDC, _manowar, _agentFactory);
        vm.stopBroadcast();
        return address(rfa);
    }
}
