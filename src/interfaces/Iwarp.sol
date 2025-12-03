// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IWarp
 * @notice Interface for warping external agents into the Manowar ecosystem
 * @dev Handles royalty distribution: 10% original creator, 10% treasury, 80% warper
 */
interface IWarp {
    /// @notice Emitted when an external agent is warped
    event AgentWarped(
        uint256 indexed warpedAgentId,
        address indexed warper,
        address originalCreator,
        bytes32 originalAgentHash
    );

    /// @notice Emitted when treasury transfers unclaimed royalties to verified creator
    event RoyaltiesTransferred(
        uint256 indexed warpedAgentId,
        address indexed originalCreator,
        uint256 amount
    );

    error InvalidExternalAgent();
    error NotTreasury();
    error RoyaltyExpired(uint256 warpedAgentId);
    error RoyaltiesAlreadyClaimed(uint256 warpedAgentId);
    error ZeroAddress();

    /**
     * @notice Warped agent data
     * @param originalCreator Original creator address (0x0 if unknown)
     * @param warper Address that performed the warp
     * @param originalAgentHash Hash identifying the external agent
     * @param royaltyExpiryDate Timestamp when unclaimed royalties can no longer be transferred
     * @param royaltiesClaimed Whether original creator royalties have been claimed
     * @param accumulatedRoyalties Total royalties accumulated for original creator
     */
    struct WarpedAgentData {
        address originalCreator;
        address warper;
        bytes32 originalAgentHash;
        uint256 royaltyExpiryDate;
        bool royaltiesClaimed;
        uint256 accumulatedRoyalties;
    }

    /**
     * @notice Warp an external agent into the Manowar ecosystem
     * @param originalAgentHash Hash identifying the external agent (e.g., from ERC-8004 or A2A)
     * @param originalCreator Original creator address (0x0 if unknown)
     * @param units Supply cap for the warped agent
     * @param price Integration price in USDC (6 decimals)
     * @param agentCardUri IPFS URI to the Agent Card JSON
     * @return warpedAgentId The newly created agent's ID
     */
    function warpAgent(
        bytes32 originalAgentHash,
        address originalCreator,
        uint256 units,
        uint256 price,
        string calldata agentCardUri
    ) external returns (uint256 warpedAgentId);

    /**
     * @notice Get warped agent data
     * @param warpedAgentId The warped agent's ID
     * @return data The WarpedAgentData struct
     */
    function getWarpedData(uint256 warpedAgentId) external view returns (WarpedAgentData memory data);

    /**
     * @notice Check if an agent is warped
     * @param agentId The agent's unique identifier
     * @return isWarped True if the agent was created via warp
     */
    function isWarped(uint256 agentId) external view returns (bool isWarped);

    /**
     * @notice Calculate royalty split for a given amount
     * @param warpedAgentId The warped agent's ID
     * @param totalAmount Total payment amount
     * @return creatorShare Amount for original creator (10% or 0 if unknown)
     * @return treasuryShare Amount for treasury (10% or 20% if creator unknown)
     * @return warperShare Amount for warper (80%)
     */
    function calculateRoyaltySplit(
        uint256 warpedAgentId,
        uint256 totalAmount
    ) external view returns (uint256 creatorShare, uint256 treasuryShare, uint256 warperShare);

    /**
     * @notice Record a royalty payment and distribute
     * @param warpedAgentId The warped agent's ID
     * @param amount Total payment amount to distribute
     */
    function distributeRoyalty(uint256 warpedAgentId, uint256 amount) external;

    /**
     * @notice Transfer unclaimed royalties to verified original creator (treasury only)
     * @dev Can only be called by treasury within 1 year of warp
     * @param warpedAgentId The warped agent's ID
     * @param verifiedCreator The verified original creator address
     */
    function transferUnclaimedRoyalties(uint256 warpedAgentId, address verifiedCreator) external;

    /**
     * @notice Get the treasury address
     * @return treasury The treasury wallet address
     */
    function getTreasury() external view returns (address treasury);

    /**
     * @notice Get royalty percentages
     * @return creatorPercent Percentage for original creator (10)
     * @return treasuryPercent Percentage for treasury (10)
     * @return warperPercent Percentage for warper (80)
     */
    function getRoyaltyPercentages() external pure returns (
        uint8 creatorPercent,
        uint8 treasuryPercent,
        uint8 warperPercent
    );
}

