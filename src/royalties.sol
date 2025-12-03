// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IRoyalties} from "./interfaces/Iroyalties.sol";

/**
 * @title Royalties
 * @notice EIP-2981 compatible royalty management for Manowar ecosystem
 * @dev Handles royalty calculations and per-token royalty configuration
 */
contract Royalties is IRoyalties {
    // =============================================================================
    // Constants
    // =============================================================================

    uint96 public constant FEE_DENOMINATOR = 10000; // 100% = 10000 basis points

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Default royalty info
    RoyaltyInfo private _defaultRoyalty;

    /// @notice Token-specific royalty overrides
    mapping(uint256 => RoyaltyInfo) private _tokenRoyalties;

    /// @notice Check if token has custom royalty
    mapping(uint256 => bool) private _hasTokenRoyalty;

    /// @notice Admin address
    address private _admin;

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address defaultReceiver, uint96 defaultFeeNumerator) {
        require(defaultReceiver != address(0), "Zero receiver");
        require(defaultFeeNumerator <= FEE_DENOMINATOR, "Fee too high");
        
        _defaultRoyalty = RoyaltyInfo({
            receiver: defaultReceiver,
            feeNumerator: defaultFeeNumerator
        });
        
        _admin = msg.sender;
    }

    // =============================================================================
    // IRoyalties Implementation
    // =============================================================================

    /// @inheritdoc IRoyalties
    function royaltyInfo(
        uint256 tokenId,
        uint256 salePrice
    ) external view returns (address receiver, uint256 royaltyAmount) {
        RoyaltyInfo memory royalty = _hasTokenRoyalty[tokenId] 
            ? _tokenRoyalties[tokenId] 
            : _defaultRoyalty;

        royaltyAmount = (salePrice * royalty.feeNumerator) / FEE_DENOMINATOR;
        receiver = royalty.receiver;
    }

    /// @inheritdoc IRoyalties
    function setTokenRoyalty(uint256 tokenId, address receiver, uint96 feeNumerator) external {
        require(msg.sender == _admin, "Not admin");
        if (receiver == address(0)) revert InvalidReceiver();
        if (feeNumerator > FEE_DENOMINATOR) revert InvalidRoyaltyFee();

        _tokenRoyalties[tokenId] = RoyaltyInfo({
            receiver: receiver,
            feeNumerator: feeNumerator
        });
        _hasTokenRoyalty[tokenId] = true;

        emit RoyaltySet(tokenId, receiver, feeNumerator);
    }

    /// @inheritdoc IRoyalties
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external {
        require(msg.sender == _admin, "Not admin");
        if (receiver == address(0)) revert InvalidReceiver();
        if (feeNumerator > FEE_DENOMINATOR) revert InvalidRoyaltyFee();

        _defaultRoyalty = RoyaltyInfo({
            receiver: receiver,
            feeNumerator: feeNumerator
        });

        emit RoyaltySet(0, receiver, feeNumerator);
    }

    /// @inheritdoc IRoyalties
    function deleteTokenRoyalty(uint256 tokenId) external {
        require(msg.sender == _admin, "Not admin");
        delete _tokenRoyalties[tokenId];
        _hasTokenRoyalty[tokenId] = false;
    }

    /// @inheritdoc IRoyalties
    function getDefaultRoyalty() external view returns (address receiver, uint96 feeNumerator) {
        return (_defaultRoyalty.receiver, _defaultRoyalty.feeNumerator);
    }

    /// @inheritdoc IRoyalties
    function calculateRoyalty(uint256 tokenId, uint256 amount) external view returns (uint256) {
        RoyaltyInfo memory royalty = _hasTokenRoyalty[tokenId] 
            ? _tokenRoyalties[tokenId] 
            : _defaultRoyalty;
        return (amount * royalty.feeNumerator) / FEE_DENOMINATOR;
    }

    // =============================================================================
    // EIP-2981 Support
    // =============================================================================

    /// @notice Check if contract supports EIP-2981
    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return 
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x2a55205a;   // EIP-2981
    }

    // =============================================================================
    // Admin Functions
    // =============================================================================

    function transferAdmin(address newAdmin) external {
        require(msg.sender == _admin, "Not admin");
        require(newAdmin != address(0), "Zero address");
        _admin = newAdmin;
    }

    function getAdmin() external view returns (address) {
        return _admin;
    }
}

