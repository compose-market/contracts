// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {USDCDispenser} from "../src/dispenser/USDCDispenser.sol";

/**
 * @title DeployDispenser
 * @notice Deploy USDCDispenser to THE SAME ADDRESS on all chains using the Deterministic Deployment Proxy
 *
 * The proxy at 0x4e59b44847b379578588920cA78FbF26c0B4956C is already deployed on most chains.
 * It uses CREATE2 to deploy contracts at deterministic addresses.
 *
 * Usage:
 *   forge script script/DeployDispenser.s.sol --rpc-url cronos-testnet --broadcast
 *   forge script script/DeployDispenser.s.sol --rpc-url fuji --broadcast
 *   forge script script/DeployDispenser.s.sol --rpc-url arb-sepolia --broadcast
 *
 * THE DISPENSER WILL BE AT THE SAME ADDRESS ON ALL CHAINS!
 */
contract DeployDispenser is Script {

    address constant DETERMINISTIC_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 constant DISPENSER_SALT = keccak256("compose:usdc-dispenser:v1:2026");

    uint256 constant DEFAULT_CLAIM_AMOUNT = 1_000_000;
    uint256 constant DEFAULT_MAX_CLAIMS = 1000;

    function run() external {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        address authorizedCaller = vm.envOr("SERVER_WALLET", 0xA893ceb66ac75DBDe4EBca89671AFE29f5B88359);
        address owner = vm.envOr("DISPENSER_OWNER", deployer);

        // Build init code - SAME on all chains (no chain-specific args!)
        bytes memory initCode = abi.encodePacked(
            type(USDCDispenser).creationCode,
            abi.encode(
                owner,
                authorizedCaller,
                DEFAULT_CLAIM_AMOUNT,
                DEFAULT_MAX_CLAIMS
            )
        );

        // Compute deterministic address
        bytes32 bytecodeHash = keccak256(initCode);
        address predictedAddress = computeCreate2Address(DETERMINISTIC_PROXY, DISPENSER_SALT, bytecodeHash);

        console.log("=== Deterministic Dispenser Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Authorized Caller:", authorizedCaller);
        console.log("");
        console.log("Deterministic Proxy:", DETERMINISTIC_PROXY);
        console.log("Salt:");
        console.logBytes32(DISPENSER_SALT);
        console.log("");
        console.log("PREDICTED DISPENSER ADDRESS (SAME ON ALL CHAINS):", predictedAddress);
        console.log("");

        // Check if already deployed
        if (predictedAddress.code.length > 0) {
            console.log("Dispenser ALREADY DEPLOYED at:", predictedAddress);
            USDCDispenser existingDispenser = USDCDispenser(predictedAddress);
            console.log("");
            console.log("Status:");
            console.log("  - USDC Address:", existingDispenser.getUSDCAddress());
            console.log("  - Claim Amount:", existingDispenser.claimAmount());
            console.log("  - Max Claims:", existingDispenser.maxClaims());
            console.log("  - Total Claims:", existingDispenser.totalClaims());
            return;
        }

        console.log("Deploying dispenser via deterministic proxy...");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Build calldata: salt (32 bytes) + initCode
        bytes memory callData = abi.encodePacked(DISPENSER_SALT, initCode);

        // Call the deterministic proxy
        (bool success, ) = DETERMINISTIC_PROXY.call(callData);
        require(success, "Deployment failed");

        vm.stopBroadcast();

        // Verify deployment
        require(predictedAddress.code.length > 0, "Contract not deployed");

        console.log("=== Deployment Complete ===");
        console.log("Dispenser deployed at:", predictedAddress);
        console.log("");
        console.log("This address is THE SAME on ALL chains!");

        USDCDispenser dispenser = USDCDispenser(predictedAddress);
        console.log("");
        console.log("Status:");
        console.log("  - USDC Address:", dispenser.getUSDCAddress());
        console.log("  - Claim Amount:", dispenser.claimAmount());
        console.log("  - Max Claims:", dispenser.maxClaims());
        console.log("  - Total Claims:", dispenser.totalClaims());
        console.log("");
        console.log("Next: Fund with USDC (1000 USDC for 1000 claims)");
        console.log("Add to .env: DISPENSER_ADDRESS=", predictedAddress);
    }

    function computeCreate2Address(
        address deployer,
        bytes32 salt,
        bytes32 bytecodeHash
    ) internal pure returns (address) {
        bytes32 hash = keccak256(
            abi.encodePacked(hex"ff", deployer, salt, bytecodeHash)
        );
        return address(uint160(uint256(hash)));
    }
}