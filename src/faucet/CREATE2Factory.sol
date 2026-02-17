// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title CREATE2Factory
 * @notice Factory for deterministic contract deployment using CREATE2
 * @dev Deploys contracts to the same address across different chains
 *
 * CREATE2 address calculation:
 * address = keccak256(0xff ++ factory_address ++ salt ++ keccak256(bytecode))[12:]
 *
 * Same factory + same salt + same bytecode = same address on all chains
 */
contract CREATE2Factory {
    event Deployed(address indexed deployedAddress, address indexed deployer, bytes32 salt);

    /**
     * @notice Deploy a contract using CREATE2
     * @param salt 32-byte salt for deterministic address
     * @param bytecode Contract creation bytecode (MEMORY, not calldata)
     * @return deployedAddress Address of the deployed contract
     */
    function deploy(bytes32 salt, bytes memory bytecode) external returns (address deployedAddress) {
        require(bytecode.length > 0, "Empty bytecode");

        assembly {
            deployedAddress := create2(0, add(bytecode, 0x20), mload(bytecode), salt)

            if iszero(extcodesize(deployedAddress)) {
                revert(0, 0)
            }
        }

        emit Deployed(deployedAddress, msg.sender, salt);
    }

    /**
     * @notice Deploy a contract with ETH value using CREATE2
     * @param value Amount of ETH to send
     * @param salt 32-byte salt
     * @param bytecode Contract creation bytecode
     * @return deployedAddress Address of the deployed contract
     */
    function deployWithValue(
        uint256 value,
        bytes32 salt,
        bytes memory bytecode
    ) external payable returns (address deployedAddress) {
        require(bytecode.length > 0, "Empty bytecode");
        require(address(this).balance >= value, "Insufficient balance");

        assembly {
            deployedAddress := create2(value, add(bytecode, 0x20), mload(bytecode), salt)

            if iszero(extcodesize(deployedAddress)) {
                revert(0, 0)
            }
        }

        emit Deployed(deployedAddress, msg.sender, salt);
    }

    /**
     * @notice Compute the address of a contract to be deployed
     * @param salt 32-byte salt
     * @param bytecodeHash keccak256 hash of the bytecode
     * @return Predicted address
     */
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address) {
        return _computeAddress(salt, bytecodeHash, address(this));
    }

    /**
     * @notice Compute address with different deployer (for verification)
     * @param deployer Deployer address
     * @param salt 32-byte salt
     * @param bytecodeHash keccak256 hash of the bytecode
     * @return Predicted address
     */
    function computeAddressWithDeployer(
        address deployer,
        bytes32 salt,
        bytes32 bytecodeHash
    ) external pure returns (address) {
        return _computeAddress(salt, bytecodeHash, deployer);
    }

    /**
     * @dev Internal function to compute CREATE2 address
     */
    function _computeAddress(
        bytes32 salt,
        bytes32 bytecodeHash,
        address deployer
    ) internal pure returns (address addr) {
        assembly {
            let ptr := mload(0x40)
            mstore(add(ptr, 0x40), bytecodeHash)
            mstore(add(ptr, 0x20), salt)
            mstore(ptr, deployer)
            let start := add(ptr, 0x0b)
            mstore8(start, 0xff)
            addr := and(keccak256(start, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
        }
    }

    receive() external payable {}
}