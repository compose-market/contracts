// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Paymaster, IEntryPointV07} from "../src/cronosAA/Paymaster.sol";

/**
 * @title DeployPaymaster
 * @notice Deploy Paymaster to target chain for gasless transactions
 * 
 * Usage:
 *   forge script script/DeployPaymaster.s.sol --rpc-url cronos-testnet --broadcast
 * 
 * Environment Variables:
 *   DEPLOYER_KEY - Private key of deployer (pays gas)
 *   SERVER_WALLET - Address that signs paymaster approvals (can be different)
 *   PAYMASTER_DEPOSIT - Optional: Amount of native token to deposit (in wei)
 * 
 * EntryPoint v0.7 address (universal):
 * - All chains: 0x0000000071727De22E5E9d8BAf0edAc6f37da032
 */
contract DeployPaymaster is Script {
    
    // ERC-4337 v0.7 EntryPoint (deployed on all chains including Cronos Testnet)
    address constant ENTRYPOINT_V07 = 0x0000000071727De22E5E9d8BAf0edAc6f37da032;

    function run() external {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        address deployer = vm.addr(deployerPrivateKey);
        
        // Server wallet that will sign paymaster approvals
        // Can be same as deployer or different
        address serverWallet = vm.envOr("SERVER_WALLET", deployer);
        
        // Optional: Initial deposit to fund paymaster
        uint256 depositAmount = vm.envOr("PAYMASTER_DEPOSIT", uint256(0));
        
        console.log("=== Paymaster Deployment (v0.7) ===");
        console.log("Deployer:", deployer);
        console.log("Verifying Signer (SERVER_WALLET):", serverWallet);
        console.log("Chain ID:", block.chainid);
        console.log("EntryPoint v0.7:", ENTRYPOINT_V07);
        console.log("Initial Deposit:", depositAmount, "wei");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Paymaster
        Paymaster paymaster = new Paymaster(
            IEntryPointV07(ENTRYPOINT_V07),
            serverWallet
        );
        
        // Fund paymaster if deposit amount specified
        if (depositAmount > 0) {
            console.log("Depositing", depositAmount, "wei to EntryPoint...");
            paymaster.deposit{value: depositAmount}();
        }
        
        vm.stopBroadcast();

        console.log("=== Deployment Complete ===");
        console.log("");
        console.log("Paymaster:", address(paymaster));
        console.log("Verifying Signer:", paymaster.verifyingSigner());
        console.log("Current Deposit:", paymaster.getDeposit());
        console.log("");
        console.log("Next steps:");
        console.log("1. Fund the paymaster with native token:");
        console.log("   cast send", address(paymaster), "--value 1ether --rpc-url cronos-testnet");
        console.log("");
        console.log("2. Add to .env files:");
        console.log("   VITE_CRONOSTEST_PAYMASTER=", address(paymaster));
        console.log("   PAYMASTER_ADDRESS=", address(paymaster));
    }
}
