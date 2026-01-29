// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import "@thirdweb-dev/contracts/prebuilts/account/non-upgradeable/AccountFactory.sol";
import "@thirdweb-dev/contracts/prebuilts/account/interface/IEntrypoint.sol";

/**
 * @title DeployAccountFactory
 * @notice Deploy ThirdWeb's AccountFactory to target chain
 * 
 * This deploys ThirdWeb's official AccountFactory which creates
 * Smart Accounts compatible with ThirdWeb's cross-chain infrastructure.
 * 
 * Usage:
 *   forge script script/DeployAccountFactory.s.sol --rpc-url cronos-testnet --broadcast
 * 
 * EntryPoint v0.7 addresses:
 * - Universal (all chains): 0x0000000071727De22E5E9d8BAf0edAc6f37da032
 * 
 * ThirdWeb Default Factory v0.7: 0x4be0ddfebca9a5a4a617dee4dece99e7c862dceb
 */
contract DeployAccountFactory is Script {
    
    // ERC-4337 v0.7 EntryPoint (deployed on all chains including Cronos Testnet)
    address constant ENTRYPOINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== ThirdWeb AccountFactory Deployment (v0.7) ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("EntryPoint v0.7:", ENTRYPOINT_V07);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy ThirdWeb AccountFactory
        // Constructor: AccountFactory(address _defaultAdmin, IEntryPoint _entrypoint)
        AccountFactory factory = new AccountFactory(
            deployer,                       // Default admin
            IEntryPoint(ENTRYPOINT_V07)     // EntryPoint v0.7
        );
        
        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("");
        console.log("AccountFactory:", address(factory));
        console.log("Account Implementation:", factory.accountImplementation());
        console.log("EntryPoint:", factory.entrypoint());
        console.log("");
        console.log("To get a user's Smart Account address:");
        console.log("  factory.getAddress(signerAddress, bytes(''))");
        console.log("");
        console.log("Add this factory address to your frontend config!");
    }
}
