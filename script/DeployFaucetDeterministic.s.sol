// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {USDCFaucet} from "../src/faucet/USDCFaucet.sol";

/**
 * @title DeployFaucetDeterministic
 * @notice Deploy USDCFaucet to THE SAME ADDRESS on all chains using the Deterministic Deployment Proxy
 *
 * The proxy at 0x4e59b44847b379578588920cA78FbF26c0B4956C is already deployed on most chains.
 * It uses CREATE2 to deploy contracts at deterministic addresses.
 *
 * Usage:
 *   forge script script/DeployFaucetDeterministic.s.sol --rpc-url cronos-testnet --broadcast
 *   forge script script/DeployFaucetDeterministic.s.sol --rpc-url fuji --broadcast
 *   forge script script/DeployFaucetDeterministic.s.sol --rpc-url arb-sepolia --broadcast
 *
 * THE FAUCET WILL BE AT THE SAME ADDRESS ON ALL CHAINS!
 */
contract DeployFaucetDeterministic is Script {

    address constant DETERMINISTIC_PROXY = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
    bytes32 constant FAUCET_SALT = keccak256("compose:usdc-faucet:v1:2026");

    uint256 constant DEFAULT_CLAIM_AMOUNT = 1_000_000;
    uint256 constant DEFAULT_MAX_CLAIMS = 1000;

    function run() external {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        address authorizedCaller = vm.envOr("SERVER_WALLET", 0xA893ceb66ac75DBDe4EBca89671AFE29f5B88359);
        address owner = vm.envOr("FAUCET_OWNER", deployer);

        // Build init code - SAME on all chains (no chain-specific args!)
        bytes memory initCode = abi.encodePacked(
            type(USDCFaucet).creationCode,
            abi.encode(
                owner,
                authorizedCaller,
                DEFAULT_CLAIM_AMOUNT,
                DEFAULT_MAX_CLAIMS
            )
        );

        // Compute deterministic address
        bytes32 bytecodeHash = keccak256(initCode);
        address predictedAddress = computeCreate2Address(DETERMINISTIC_PROXY, FAUCET_SALT, bytecodeHash);

        console.log("=== Deterministic Faucet Deployment ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Authorized Caller:", authorizedCaller);
        console.log("");
        console.log("Deterministic Proxy:", DETERMINISTIC_PROXY);
        console.log("Salt:");
        console.logBytes32(FAUCET_SALT);
        console.log("");
        console.log("PREDICTED FAUCET ADDRESS (SAME ON ALL CHAINS):", predictedAddress);
        console.log("");

        // Check if already deployed
        if (predictedAddress.code.length > 0) {
            console.log("Faucet ALREADY DEPLOYED at:", predictedAddress);
            USDCFaucet existingFaucet = USDCFaucet(predictedAddress);
            console.log("");
            console.log("Status:");
            console.log("  - USDC Address:", existingFaucet.getUSDCAddress());
            console.log("  - Claim Amount:", existingFaucet.claimAmount());
            console.log("  - Max Claims:", existingFaucet.maxClaims());
            console.log("  - Total Claims:", existingFaucet.totalClaims());
            return;
        }

        console.log("Deploying faucet via deterministic proxy...");
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Build calldata: salt (32 bytes) + initCode
        bytes memory callData = abi.encodePacked(FAUCET_SALT, initCode);

        // Call the deterministic proxy
        (bool success, ) = DETERMINISTIC_PROXY.call(callData);
        require(success, "Deployment failed");

        vm.stopBroadcast();

        // Verify deployment
        require(predictedAddress.code.length > 0, "Contract not deployed");

        console.log("=== Deployment Complete ===");
        console.log("Faucet deployed at:", predictedAddress);
        console.log("");
        console.log("This address is THE SAME on ALL chains!");

        USDCFaucet faucet = USDCFaucet(predictedAddress);
        console.log("");
        console.log("Status:");
        console.log("  - USDC Address:", faucet.getUSDCAddress());
        console.log("  - Claim Amount:", faucet.claimAmount());
        console.log("  - Max Claims:", faucet.maxClaims());
        console.log("  - Total Claims:", faucet.totalClaims());
        console.log("");
        console.log("Next: Fund with USDC (1000 USDC for 1000 claims)");
        console.log("Add to .env: FAUCET_ADDRESS=", predictedAddress);
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