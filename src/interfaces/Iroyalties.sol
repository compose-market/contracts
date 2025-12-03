// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title IRoyalties
 * @notice Interface for EIP-2981 royalty distribution
 * @dev Handles royalty calculations and distributions for agents and Manowars
 */
interface IRoyalties {
    /// @notice Emitted when royalty info is set
    event RoyaltySet(uint256 indexed tokenId, address indexed receiver, uint96 feeNumerator);

    /// @notice Emitted when royalties are distributed
    event RoyaltiesDistributed(
        uint256 indexed tokenId,
        uint256 totalAmount,
        address[] receivers,
        uint256[] amounts
    );

    error InvalidRoyaltyFee();
    error InvalidReceiver();
    error TokenNotFound(uint256 tokenId);

    /**
     * @notice Royalty recipient data
     * @param receiver Address to receive royalties
     * @param feeNumerator Fee numerator (basis points, max 10000 = 100%)
     */
    struct RoyaltyInfo {
        address receiver;
        uint96 feeNumerator;
    }

    /**
     * @notice EIP-2981: Get royalty info for a token sale
     * @param tokenId The token ID
     * @param salePrice The sale price
     * @return receiver The royalty recipient
     * @return royaltyAmount The royalty amount
     */
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view returns (address receiver, uint256 royaltyAmount);

    /**
     * @notice Set royalty info for a token
     * @param tokenId The token ID
     * @param receiver The royalty recipient
     * @param feeNumerator Fee in basis points (e.g., 500 = 5%)
     */
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external;

    /**
     * @notice Set default royalty for all tokens
     * @param receiver The default royalty recipient
     * @param feeNumerator Fee in basis points
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external;

    /**
     * @notice Delete royalty info for a token (uses default)
     * @param tokenId The token ID
     */
    function deleteTokenRoyalty(uint256 tokenId) external;

    /**
     * @notice Get default royalty info
     * @return receiver The default royalty recipient
     * @return feeNumerator The default fee numerator
     */
    function getDefaultRoyalty() external view returns (address receiver, uint96 feeNumerator);

    /**
     * @notice Calculate royalty for an amount
     * @param tokenId The token ID
     * @param amount The amount to calculate royalty on
     * @return royalty The royalty amount
     */
    function calculateRoyalty(uint256 tokenId, uint256 amount) external view returns (uint256 royalty);

    /**
     * @notice Fee denominator (10000 = 100%)
     */
    function FEE_DENOMINATOR() external pure returns (uint96);
}

/**
 * @title IDistributor
 * @notice Interface for fee distribution logic
 * @dev Handles splitting payments between multiple recipients
 */
interface IDistributor {
    /// @notice Emitted when fees are distributed
    event FeesDistributed(
        bytes32 indexed distributionId,
        uint256 totalAmount,
        address[] recipients,
        uint256[] amounts
    );

    error InvalidRecipients();
    error InvalidShares();
    error SharesMismatch();
    error TransferFailed(address recipient);
    error ZeroAmount();

    /**
     * @notice Distribution recipient with share
     * @param recipient Address to receive payment
     * @param share Share in basis points (total must equal 10000)
     */
    struct Recipient {
        address recipient;
        uint256 share;
    }

    /**
     * @notice Distribute an amount to multiple recipients
     * @param recipients Array of Recipient structs
     * @param totalAmount Total amount to distribute
     * @param token ERC20 token address (address(0) for native)
     * @return distributionId Unique ID for this distribution
     */
    function distribute(
        Recipient[] calldata recipients,
        uint256 totalAmount,
        address token
    ) external payable returns (bytes32 distributionId);

    /**
     * @notice Calculate distribution amounts
     * @param recipients Array of Recipient structs
     * @param totalAmount Total amount to distribute
     * @return amounts Array of amounts for each recipient
     */
    function calculateDistribution(
        Recipient[] calldata recipients,
        uint256 totalAmount
    ) external pure returns (uint256[] memory amounts);

    /**
     * @notice Validate recipients and shares
     * @param recipients Array of Recipient structs
     * @return valid True if valid
     */
    function validateRecipients(Recipient[] calldata recipients) external pure returns (bool valid);

    /**
     * @notice Get the treasury address
     * @return treasury The treasury wallet
     */
    function getTreasury() external view returns (address treasury);

    /**
     * @notice Basis points denominator (10000 = 100%)
     */
    function BASIS_POINTS() external pure returns (uint256);
}

