// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

import {AgentFactory} from "../src/compose/agentfactory.sol";
import {Clone} from "../src/compose/clone.sol";
import {Warp} from "../src/compose/warp.sol";
import {Workflow} from "../src/compose/workflow.sol";
import {RFA} from "../src/compose/rfa.sol";
import {Lease} from "../src/compose/lease.sol";
import {Royalties} from "../src/compose/royalties.sol";
import {Distributor} from "../src/compose/distributor.sol";
import {Utils} from "../src/compose/utils.sol";
import {AgentManager} from "../src/compose/agentmanager.sol";
import {Delegation} from "../src/compose/delegation.sol";

/**
 * @title Compose
 * @notice Deterministic deployment script for the Manowar protocol suite
 *
 * Usage:
 *   forge script Compose --rpc-url fuji --broadcast
 *   forge script Compose --rpc-url arb-sepolia --broadcast
 *   forge script Compose --rpc-url base-sepolia --broadcast
 */
contract Compose is Script {
    address constant DETERMINISTIC_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

    bytes32 constant ROYALTIES_SALT = keccak256("compose:royalties:v1:2026");
    bytes32 constant DISTRIBUTOR_SALT = keccak256("compose:distributor:v1:2026");
    bytes32 constant AGENT_FACTORY_SALT = keccak256("compose:agent-factory:v1:2026");
    bytes32 constant CLONE_SALT = keccak256("compose:clone:v1:2026");
    bytes32 constant WARP_SALT = keccak256("compose:warp:v1:2026");
    bytes32 constant WORKFLOW_SALT = keccak256("compose:workflow:v1:2026");
    bytes32 constant RFA_SALT = keccak256("compose:rfa:v1:2026");
    bytes32 constant LEASE_SALT = keccak256("compose:lease:v1:2026");
    bytes32 constant DELEGATION_SALT = keccak256("compose:delegation:v1:2026");
    bytes32 constant AGENT_MANAGER_SALT = keccak256("compose:agent-manager:v1:2026");
    bytes32 constant UTILS_SALT = keccak256("compose:utils:v1:2026");

    address constant DEFAULT_TREASURY = 0x058271e764154c322F3D3dDC18aF44F7d91B1c80;
    uint96 constant DEFAULT_ROYALTY_FEE = 500;

    AgentFactory public agentFactory;
    Clone public clone;
    Warp public warp;
    Workflow public workflow;
    RFA public rfa;
    Lease public lease;
    Royalties public royalties;
    Distributor public distributor;
    Utils public utils;
    AgentManager public agentManager;
    Delegation public delegation;

    function run() external {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        address treasury = vm.envOr("TREASURY", DEFAULT_TREASURY);
        address protocolAdmin = vm.envOr("PROTOCOL_ADMIN", deployer);

        console.log("=== Deterministic Compose Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Treasury:", treasury);
        console.log("Protocol Admin:", protocolAdmin);
        console.log("Deterministic Proxy:", DETERMINISTIC_PROXY);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        royalties = Royalties(
            _deployDeterministic(
                "Royalties",
                ROYALTIES_SALT,
                abi.encodePacked(
                    type(Royalties).creationCode,
                    abi.encode(treasury, DEFAULT_ROYALTY_FEE, protocolAdmin)
                )
            )
        );

        distributor = Distributor(payable(
            _deployDeterministic(
                "Distributor",
                DISTRIBUTOR_SALT,
                abi.encodePacked(type(Distributor).creationCode, abi.encode(treasury, protocolAdmin))
            )
        ));

        agentFactory = AgentFactory(
            _deployDeterministic(
                "AgentFactory",
                AGENT_FACTORY_SALT,
                abi.encodePacked(type(AgentFactory).creationCode, abi.encode(protocolAdmin))
            )
        );

        clone = Clone(
            _deployDeterministic(
                "Clone",
                CLONE_SALT,
                abi.encodePacked(type(Clone).creationCode, abi.encode(address(agentFactory)))
            )
        );

        warp = Warp(
            _deployDeterministic(
                "Warp",
                WARP_SALT,
                abi.encodePacked(type(Warp).creationCode, abi.encode(address(agentFactory), treasury))
            )
        );

        workflow = Workflow(
            _deployDeterministic(
                "Workflow",
                WORKFLOW_SALT,
                abi.encodePacked(type(Workflow).creationCode, abi.encode(address(agentFactory), protocolAdmin))
            )
        );

        rfa = RFA(
            _deployDeterministic(
                "RFA",
                RFA_SALT,
                abi.encodePacked(type(RFA).creationCode, abi.encode(address(workflow), address(agentFactory), protocolAdmin))
            )
        );

        lease = Lease(
            _deployDeterministic(
                "Lease",
                LEASE_SALT,
                abi.encodePacked(type(Lease).creationCode, abi.encode(address(workflow), protocolAdmin))
            )
        );

        delegation = Delegation(
            _deployDeterministic(
                "Delegation",
                DELEGATION_SALT,
                type(Delegation).creationCode
            )
        );

        agentManager = AgentManager(
            _deployDeterministic(
                "AgentManager",
                AGENT_MANAGER_SALT,
                abi.encodePacked(type(AgentManager).creationCode, abi.encode(protocolAdmin))
            )
        );

        utils = Utils(
            _deployDeterministic(
                "Utils",
                UTILS_SALT,
                abi.encodePacked(
                    type(Utils).creationCode,
                    abi.encode(address(agentManager), address(agentFactory), address(workflow), protocolAdmin)
                )
            )
        );

        console.log("");
        console.log("=== Initializing Ecosystem ===");

        if (!delegation.isInitialized()) {
            delegation.initialize(address(agentManager));
            console.log("Delegation initialized");
        } else {
            console.log("Delegation already initialized");
        }

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
        console.log("AgentManager ecosystem initialized");

        agentFactory.authorizeConsumer(address(clone));
        agentFactory.authorizeConsumer(address(warp));
        agentFactory.authorizeConsumer(address(workflow));
        console.log("AgentFactory consumers authorized");

        workflow.setRFAContract(address(rfa));
        workflow.setLeaseContract(address(lease));
        workflow.setDistributor(address(distributor));
        workflow.setTreasury(treasury);
        console.log("Workflow dependencies configured");

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("AgentFactory:", address(agentFactory));
        console.log("Clone:", address(clone));
        console.log("Warp:", address(warp));
        console.log("Workflow:", address(workflow));
        console.log("RFA:", address(rfa));
        console.log("Lease:", address(lease));
        console.log("Royalties:", address(royalties));
        console.log("Distributor:", address(distributor));
        console.log("Delegation:", address(delegation));
        console.log("AgentManager:", address(agentManager));
        console.log("Utils:", address(utils));
    }

    function _deployDeterministic(
        string memory contractName,
        bytes32 salt,
        bytes memory initCode
    ) internal returns (address predictedAddress) {
        bytes32 bytecodeHash = keccak256(initCode);
        predictedAddress = computeCreate2Address(DETERMINISTIC_PROXY, salt, bytecodeHash);

        console.log("");
        console.log(contractName);
        console.log("  Salt:");
        console.logBytes32(salt);
        console.log("  Predicted:", predictedAddress);

        if (predictedAddress.code.length > 0) {
            console.log("  Status: already deployed");
            return predictedAddress;
        }

        bytes memory callData = abi.encodePacked(salt, initCode);
        (bool success,) = DETERMINISTIC_PROXY.call(callData);
        require(success, "Deterministic deployment failed");
        require(predictedAddress.code.length > 0, "No code at predicted address");
        console.log("  Status: deployed");
    }

    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 bytecodeHash
    ) internal pure returns (address) {
        bytes32 hash = keccak256(abi.encodePacked(hex"ff", deployer, salt, bytecodeHash));
        return address(uint160(uint256(hash)));
    }
}
