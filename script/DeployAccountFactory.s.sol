// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";

/**
 * @title DeployAccountFactory
 * @notice Deploy ThirdWeb's AccountFactory v0.7 at universal address using CREATE2
 * 
 * This uses Arachnid's CREATE2 deployer (0x4e59b44847b379578588920cA78FbF26c0B4956C)
 * to deploy the AccountFactory at the same address as on other chains:
 * 0x4bE0ddfebcA9A5A4a617dee4DeCe99E7c862dceb
 * 
 * The salt and init code were extracted from the original deployment tx on Ethereum:
 * https://eth.blockscout.com/tx/0x164f1c6a8ad1b42b3bd30ec2f6352f41c9079fc549e2a2a54bf11fa3ee0641a2
 * 
 * Usage:
 *   forge script script/DeployAccountFactory.s.sol --rpc-url cronos-testnet --broadcast
 */
contract DeployAccountFactory is Script {
    
    // Arachnid's CREATE2 Deployer - exists on most EVM chains including Cronos Testnet
    address constant CREATE2_DEPLOYER = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    
    // The salt used in the original ThirdWeb deployment
    bytes32 constant SALT = 0x70f12235750810d18f16836d54f510d6db0dab4fde7da4c9666cbdfaf6af0118;
    
    // Expected address after deployment (ThirdWeb's universal AccountFactory v0.7)
    address constant EXPECTED_ADDRESS = 0x4bE0ddfebcA9A5A4a617dee4DeCe99E7c862dceb;
    
    // ERC-4337 v0.7 EntryPoint (embedded in init code)
    address constant ENTRYPOINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_KEY");
        address deployer = vm.addr(deployerKey);
        
        console.log("=== ThirdWeb AccountFactory v0.7 CREATE2 Deployment ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("CREATE2 Deployer:", CREATE2_DEPLOYER);
        console.log("Salt:", vm.toString(SALT));
        console.log("Expected Address:", EXPECTED_ADDRESS);
        console.log("");
        
        // Check if already deployed
        uint256 codeSize;
        assembly {
            codeSize := extcodesize(0x4bE0ddfebcA9A5A4a617dee4DeCe99E7c862dceb)
        }
        
        if (codeSize > 0) {
            console.log("ALREADY DEPLOYED! Factory exists at:", EXPECTED_ADDRESS);
            console.log("Code size:", codeSize, "bytes");
            return;
        }
        
        console.log("Factory not deployed. Deploying via CREATE2...");
        
        // Load init code from file (extracted from Ethereum mainnet tx)
        string memory initCodePath = "script/account_factory_init_code.txt";
        string memory initCodeHex = vm.readFile(initCodePath);
        bytes memory initCode = vm.parseBytes(initCodeHex);
        
        console.log("Init code size:", initCode.length, "bytes");
        
        // Prepare calldata: salt (32 bytes) + init code
        bytes memory callData = abi.encodePacked(SALT, initCode);
        
        vm.startBroadcast(deployerKey);
        
        // Call the CREATE2 deployer
        (bool success, ) = CREATE2_DEPLOYER.call(callData);
        require(success, "CREATE2 deployment failed");
        
        vm.stopBroadcast();
        
        // Verify deployment
        assembly {
            codeSize := extcodesize(0x4bE0ddfebcA9A5A4a617dee4DeCe99E7c862dceb)
        }
        require(codeSize > 0, "Deployment failed: no code at expected address");
        
        console.log("");
        console.log("=== Deployment Successful! ===");
        console.log("AccountFactory:", EXPECTED_ADDRESS);
        console.log("EntryPoint:", ENTRYPOINT_V07);
        console.log("Code size:", codeSize, "bytes");
        console.log("");
        console.log("This is the universal ThirdWeb factory address!");
        console.log("Smart Accounts created with this factory will have");
        console.log("the same address on all chains using this factory.");
    }
}
