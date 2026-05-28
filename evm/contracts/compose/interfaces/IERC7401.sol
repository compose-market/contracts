// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IERC7401
 * @notice ERC-7401 Nestable NFT interface
 * @dev Allows NFTs to own other NFTs in a parent-child hierarchy
 */
interface IERC7401 {
    /// @notice Emitted when a child NFT is nested into a parent
    event ChildNested(
        uint256 indexed parentId,
        uint256 indexed childId,
        address childContract
    );

    /// @notice Emitted when a child NFT is removed from a parent
    event ChildUnnested(
        uint256 indexed parentId,
        uint256 indexed childId,
        address childContract
    );

    /// @notice Emitted when a child transfer is proposed
    event ChildProposed(
        uint256 indexed parentId,
        uint256 indexed childId,
        address childContract
    );

    /// @notice Emitted when a child transfer proposal is accepted
    event ChildAccepted(
        uint256 indexed parentId,
        uint256 indexed childId,
        address childContract
    );

    /**
     * @notice Struct representing a child NFT
     * @param contractAddress The contract address of the child NFT
     * @param tokenId The token ID of the child NFT
     */
    struct Child {
        address contractAddress;
        uint256 tokenId;
    }

    /**
     * @notice Add a child NFT to a parent token
     * @dev The child must be owned by this contract or approved for transfer
     * @param parentId The parent token ID
     * @param childContract The contract address of the child NFT
     * @param childId The token ID of the child NFT
     */
    function nestChild(
        uint256 parentId,
        address childContract,
        uint256 childId
    ) external;

    /**
     * @notice Remove a child NFT from a parent token
     * @dev Transfers the child back to the parent token's owner
     * @param parentId The parent token ID
     * @param childContract The contract address of the child NFT
     * @param childId The token ID of the child NFT
     * @param to The address to receive the unnested child
     */
    function unnestChild(
        uint256 parentId,
        address childContract,
        uint256 childId,
        address to
    ) external;

    /**
     * @notice Get all children of a parent token
     * @param parentId The parent token ID
     * @return children Array of Child structs
     */
    function childrenOf(uint256 parentId) external view returns (Child[] memory children);

    /**
     * @notice Get the number of children for a parent token
     * @param parentId The parent token ID
     * @return count The number of nested children
     */
    function childCount(uint256 parentId) external view returns (uint256 count);

    /**
     * @notice Check if a token has a parent
     * @param childContract The contract address of the potential child
     * @param childId The token ID of the potential child
     * @return hasParent True if the token is nested
     * @return parentContract The parent contract (if nested)
     * @return parentId The parent token ID (if nested)
     */
    function parentOf(
        address childContract,
        uint256 childId
    ) external view returns (bool hasParent, address parentContract, uint256 parentId);

    /**
     * @notice Propose a child transfer to this token
     * @dev Used when the child is not yet owned by this contract
     * @param parentId The parent token ID to nest into
     * @param childContract The contract address of the child NFT
     * @param childId The token ID of the child NFT
     */
    function proposeChild(
        uint256 parentId,
        address childContract,
        uint256 childId
    ) external;

    /**
     * @notice Accept a pending child transfer proposal
     * @param parentId The parent token ID
     * @param childContract The contract address of the child NFT
     * @param childId The token ID of the child NFT
     */
    function acceptChild(
        uint256 parentId,
        address childContract,
        uint256 childId
    ) external;

    /**
     * @notice Reject a pending child transfer proposal
     * @param parentId The parent token ID
     * @param childContract The contract address of the child NFT
     * @param childId The token ID of the child NFT
     */
    function rejectChild(
        uint256 parentId,
        address childContract,
        uint256 childId
    ) external;

    /**
     * @notice Get pending child proposals for a parent
     * @param parentId The parent token ID
     * @return pending Array of pending Child structs
     */
    function pendingChildrenOf(uint256 parentId) external view returns (Child[] memory pending);
}

