// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {USDCFaucet} from "../src/faucet/USDCFaucet.sol";
import {CREATE2Factory} from "../src/faucet/CREATE2Factory.sol";

/**
 * @title DeployFaucet
 * @notice Deploy USDCFaucet to target chain with deterministic address using CREATE2
 *
 * Usage:
 *   forge script script/DeployFaucet.s.sol --rpc-url cronos-testnet --broadcast
 *   forge script script/DeployFaucet.s.sol --rpc-url fuji --broadcast
 *   forge script script/DeployFaucet.s.sol --rpc-url arb-sepolia --broadcast
 *
 * THE FAUCET WILL HAVE THE SAME ADDRESS ON ALL CHAINS because:
 * 1. CREATE2Factory is deployed first at deterministic address (same deployer nonce)
 * 2. Same salt is used for faucet deployment
 * 3. Same bytecode with same constructor args
 *
 * Environment Variables:
 *   DEPLOYER_KEY - Private key of deployer
 *   SERVER_WALLET - Address authorized to call claimUSDC (our Lambda backend)
 *   FAUCET_OWNER - Owner address (defaults to deployer)
 */
contract DeployFaucet is Script {

    bytes32 constant FAUCET_SALT = keccak256("compose:usdc-faucet:v1:2026");

    uint256 constant DEFAULT_CLAIM_AMOUNT = 1_000_000;
    uint256 constant DEFAULT_MAX_CLAIMS = 1000;

    mapping(uint256 chainId => address) usdcAddresses;

    CREATE2Factory public factory;
    USDCFaucet public faucet;

    function setUp() public {
        usdcAddresses[338] = 0xc01efAaF7C5C61bEbFAeb358E1161b537b8bC0e0;
        usdcAddresses[43113] = 0x5425890298aed601595a70AB815c96711a31Bc65;
        usdcAddresses[421614] = 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;
    }

    function run() external {
        uint256 deployerPrivateKey = uint256(vm.envBytes32("DEPLOYER_KEY"));
        address deployer = vm.addr(deployerPrivateKey);

        address authorizedCaller = vm.envOr("SERVER_WALLET", 0xA893ceb66ac75DBDe4EBca89671AFE29f5B88359);
        address owner = vm.envOr("FAUCET_OWNER", deployer);

        address usdcAddress = usdcAddresses[block.chainid];
        require(usdcAddress != address(0), "Unsupported chain");

        console.log("=== USDCFaucet Deployment (CREATE2) ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("Owner:", owner);
        console.log("Authorized Caller:", authorizedCaller);
        console.log("USDC Token:", usdcAddress);
        console.log("Claim Amount:", DEFAULT_CLAIM_AMOUNT, "(1 USDC)");
        console.log("Max Claims:", DEFAULT_MAX_CLAIMS);
        console.log("Salt:");
        console.logBytes32(FAUCET_SALT);
        console.log("");

        vm.startBroadcast(deployerPrivateKey);

        // Step 1: Deploy CREATE2Factory
        // On first chain, deployer nonce = 0, factory at deterministic address
        // On subsequent chains, we need to ensure same nonce (use fresh deployer or check existing)
        factory = new CREATE2Factory();
        console.log("CREATE2Factory deployed at:", address(factory));

        // Step 2: Build init code (creationCode + constructor args)
        bytes memory initCode = abi.encodePacked(
            type(USDCFaucet).creationCode,
            abi.encode(
                usdcAddress,
                owner,
                authorizedCaller,
                DEFAULT_CLAIM_AMOUNT,
                DEFAULT_MAX_CLAIMS
            )
        );

        // Step 3: Compute predicted address
        bytes32 bytecodeHash = keccak256(initCode);
        address predictedAddress = factory.computeAddress(FAUCET_SALT, bytecodeHash);
        console.log("Predicted Faucet Address:", predictedAddress);

        // Step 4: Check if already deployed
        if (predictedAddress.code.length > 0) {
            console.log("Faucet already deployed at:", predictedAddress);
            faucet = USDCFaucet(predictedAddress);
        } else {
            // Step 5: Deploy via CREATE2
            console.log("Deploying faucet via CREATE2...");
            address deployedAddress = factory.deploy(FAUCET_SALT, initCode);
            console.log("Deployed to:", deployedAddress);
            faucet = USDCFaucet(deployedAddress);
        }

        vm.stopBroadcast();

        console.log("");
        console.log("=== Deployment Complete ===");
        console.log("Chain ID:", block.chainid);
        console.log("Faucet Address:", address(faucet));
        console.log("");
        console.log("Status:");
        console.log("  - Claim Amount:", faucet.claimAmount());
        console.log("  - Max Claims:", faucet.maxClaims());
        console.log("  - Total Claims:", faucet.totalClaims());
        console.log("  - USDC Balance:", IERC20(usdcAddress).balanceOf(address(faucet)));
        console.log("");
        console.log("Next: Fund with USDC (1000 USDC):");
        console.log("  cast send", usdcAddress, "'transfer(address,uint256)'", address(faucet), "1000000000000");
        console.log("");
        console.log("Add to .env:");
        console.log("  FAUCET_ADDRESS=", address(faucet));
    }
}

interface IERC20 {
    function balanceOf(address account) external view returns (uint256);
}