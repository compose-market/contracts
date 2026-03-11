// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAgentFactory} from "./interfaces/Iagentfactory.sol";
import {IERC8004Identity, IERC8004Reputation, IERC8004Validation} from "./interfaces/IERC8004.sol";

/**
 * @title AgentFactory
 * @notice ERC-8004 Identity Registry with Manowar extensions and licensing support
 * @dev Implements ERC-721 for AgentIDs with extended metadata for licensing, cloning, and pricing
 * 
 * Licensing Model:
 * - Each agent has a `licensePrice` - the fee to include it in a Workflow
 * - Each agent has `licenses` - supply cap for how many times it can be licensed (0 = infinite)
 * - When licensed into a Workflow, bi-directional tracking records the relationship
 * - Agent creators retain ownership and receive payment when their agents are licensed
 * 
 * Manowar Extensions:
 * - `licenses`: Supply cap for agent licensing (0 = infinite)
 * - `licensePrice`: Integration fee in USDC (6 decimals)  
 * - `cloneable`: Whether the agent can be cloned
 * - `dnaHash`: Unique identifier from keccak256(skills, chain, model)
 */
contract AgentFactory is IAgentFactory {
    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Total agents minted
    uint256 private _totalAgents;

    /// @notice Next agent ID to mint
    uint256 private _nextAgentId;

    /// @notice Agent data storage
    mapping(uint256 => AgentData) private _agents;

    /// @notice ERC-721 ownership
    mapping(uint256 => address) private _owners;

    /// @notice ERC-721 balances
    mapping(address => uint256) private _balances;

    /// @notice ERC-721 token approvals
    mapping(uint256 => address) private _tokenApprovals;

    /// @notice ERC-721 operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /// @notice DNA hash to agent ID mapping (ensures uniqueness)
    mapping(bytes32 => uint256) private _dnaHashToAgentId;

    /// @notice Reputation: total rating sum per agent
    mapping(uint256 => uint256) private _ratingSum;

    /// @notice Reputation: total review count per agent
    mapping(uint256 => uint256) private _reviewCount;

    /// @notice Validation: valid output count per agent
    mapping(uint256 => uint256) private _validCount;

    /// @notice Validation: total validation count per agent
    mapping(uint256 => uint256) private _totalValidations;

    /// @notice Authorized contracts that can consume licenses
    mapping(address => bool) private _authorizedConsumers;

    /// @notice Contract admin
    address private _admin;

    // =============================================================================
    // License Tracking State
    // =============================================================================

    /// @notice Bi-directional license tracking: agentId => workflowContract => workflowId => licensed
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) private _licensedTo;

    /// @notice License records for each agent
    mapping(uint256 => LicenseRecord[]) private _licenseRecords;

    // =============================================================================
    // ERC-721 Events
    // =============================================================================

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // =============================================================================
    // ERC-8004 Reputation & Validation Events
    // =============================================================================

    event FeedbackRecorded(uint256 indexed agentId, address indexed reviewer, uint8 rating, bytes32 feedbackHash);
    event ValidationRecorded(uint256 indexed agentId, address indexed validator, bytes32 taskHash, bool isValid);

    // =============================================================================
    // Modifiers
    // =============================================================================

    modifier onlyAdmin() {
        if (msg.sender != _admin) revert NotAgentCreator(0, msg.sender);
        _;
    }

    modifier onlyAgentCreator(uint256 agentId) {
        if (_agents[agentId].creator != msg.sender) revert NotAgentCreator(agentId, msg.sender);
        _;
    }

    modifier onlyExistingAgent(uint256 agentId) {
        if (_owners[agentId] == address(0)) revert AgentNotFound(agentId);
        _;
    }

    modifier onlyAuthorizedConsumer() {
        require(_authorizedConsumers[msg.sender] || msg.sender == _admin, "Not authorized");
        _;
    }

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address _adminAddress) {
        require(_adminAddress != address(0), "Zero admin");
        _admin = _adminAddress;
        _nextAgentId = 1; // Start at 1, 0 means "no agent"
    }

    // =============================================================================
    // IAgentFactory Implementation
    // =============================================================================

    /// @inheritdoc IAgentFactory
    function mintAgent(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        bool cloneable,
        string calldata agentCardUri
    ) external returns (uint256 agentId) {
        if (dnaHash == bytes32(0)) revert InvalidDnaHash();
        
        // Ensure DNA hash is unique
        if (_dnaHashToAgentId[dnaHash] != 0) revert InvalidDnaHash();

        agentId = _nextAgentId++;
        _totalAgents++;

        // Store agent data
        _agents[agentId] = AgentData({
            dnaHash: dnaHash,
            licenses: licenses,
            licensesMinted: 0,
            licensePrice: licensePrice,
            creator: msg.sender,
            cloneable: cloneable,
            isClone: false,
            parentAgentId: 0,
            agentCardUri: agentCardUri
        });

        // Mint ERC-721 token
        _mint(msg.sender, agentId);

        // Register DNA hash
        _dnaHashToAgentId[dnaHash] = agentId;

        emit AgentMinted(agentId, msg.sender, dnaHash, licenses, licensePrice, cloneable);
        emit AgentRegistered(agentId, msg.sender, dnaHash, agentCardUri);
    }

    /// @inheritdoc IAgentFactory
    function getAgentData(uint256 agentId) external view onlyExistingAgent(agentId) returns (AgentData memory data) {
        return _agents[agentId];
    }

    /// @inheritdoc IAgentFactory
    function getDnaHash(uint256 agentId) external view onlyExistingAgent(agentId) returns (bytes32 dnaHash) {
        return _agents[agentId].dnaHash;
    }

    /// @inheritdoc IAgentFactory
    function hasAvailableLicenses(uint256 agentId) external view onlyExistingAgent(agentId) returns (bool available) {
        AgentData storage agent = _agents[agentId];
        // licenses == 0 means infinite
        return agent.licenses == 0 || agent.licensesMinted < agent.licenses;
    }

    /// @inheritdoc IAgentFactory
    function consumeLicense(
        uint256 agentId,
        address workflowContract,
        uint256 workflowId
    ) external onlyAuthorizedConsumer onlyExistingAgent(agentId) returns (uint256 licenseNumber) {
        AgentData storage agent = _agents[agentId];
        
        // Check availability (licenses == 0 means infinite)
        if (agent.licenses != 0 && agent.licensesMinted >= agent.licenses) {
            revert NoLicensesAvailable(agentId);
        }

        // Check not already licensed to this Workflow
        if (_licensedTo[agentId][workflowContract][workflowId]) {
            revert AlreadyLicensed(agentId, workflowContract, workflowId);
        }

        licenseNumber = ++agent.licensesMinted;

        // Record the license
        _licensedTo[agentId][workflowContract][workflowId] = true;
        _licenseRecords[agentId].push(LicenseRecord({
            workflowContract: workflowContract,
            workflowId: workflowId,
            licensedAt: block.timestamp
        }));

        emit AgentLicensed(agentId, workflowContract, workflowId, licenseNumber);
    }

    /// @inheritdoc IAgentFactory
    function revokeLicense(
        uint256 agentId,
        address workflowContract,
        uint256 workflowId
    ) external onlyAuthorizedConsumer onlyExistingAgent(agentId) {
        if (!_licensedTo[agentId][workflowContract][workflowId]) {
            revert NotLicensed(agentId, workflowContract, workflowId);
        }

        _licensedTo[agentId][workflowContract][workflowId] = false;
        // Note: We don't remove from _licenseRecords array for gas efficiency
        // The _licensedTo mapping is the source of truth for active licenses

        emit AgentLicenseRevoked(agentId, workflowContract, workflowId);
    }

    /// @inheritdoc IAgentFactory
    function isLicensedTo(
        uint256 agentId,
        address workflowContract,
        uint256 workflowId
    ) external view returns (bool licensed) {
        return _licensedTo[agentId][workflowContract][workflowId];
    }

    /// @inheritdoc IAgentFactory
    function getLicenseRecords(uint256 agentId) external view returns (LicenseRecord[] memory records) {
        return _licenseRecords[agentId];
    }

    /// @inheritdoc IAgentFactory
    function updatePrice(uint256 agentId, uint256 newPrice) 
        external 
        onlyAgentCreator(agentId) 
        onlyExistingAgent(agentId) 
    {
        uint256 oldPrice = _agents[agentId].licensePrice;
        _agents[agentId].licensePrice = newPrice;
        emit AgentPriceUpdated(agentId, oldPrice, newPrice);
    }

    /// @inheritdoc IAgentFactory
    function isAgentClone(uint256 agentId) external view onlyExistingAgent(agentId) returns (bool) {
        return _agents[agentId].isClone;
    }

    /// @inheritdoc IAgentFactory
    function getParentAgent(uint256 agentId) external view onlyExistingAgent(agentId) returns (uint256 parentId) {
        return _agents[agentId].parentAgentId;
    }

    /// @inheritdoc IAgentFactory
    function totalAgents() external view returns (uint256 total) {
        return _totalAgents;
    }

    /// @inheritdoc IAgentFactory
    function agentExists(uint256 agentId) external view override returns (bool exists) {
        return _owners[agentId] != address(0);
    }

    // =============================================================================
    // IERC8004Identity Implementation
    // =============================================================================

    /// @inheritdoc IERC8004Identity
    function registerAgent(string calldata agentCardUri) external returns (uint256 agentId) {
        // Generate a basic DNA hash from sender + timestamp for simple registration
        bytes32 dnaHash = keccak256(abi.encodePacked(msg.sender, block.timestamp, _nextAgentId));
        
        agentId = _nextAgentId++;
        _totalAgents++;

        _agents[agentId] = AgentData({
            dnaHash: dnaHash,
            licenses: 0, // Infinite by default
            licensesMinted: 0,
            licensePrice: 0,
            creator: msg.sender,
            cloneable: false,
            isClone: false,
            parentAgentId: 0,
            agentCardUri: agentCardUri
        });

        _mint(msg.sender, agentId);
        _dnaHashToAgentId[dnaHash] = agentId;

        emit AgentRegistered(agentId, msg.sender, dnaHash, agentCardUri);
    }

    /// @inheritdoc IERC8004Identity
    function getAgentCardUri(uint256 agentId) external view onlyExistingAgent(agentId) returns (string memory uri) {
        return _agents[agentId].agentCardUri;
    }

    /// @inheritdoc IERC8004Identity
    function updateAgentCardUri(uint256 agentId, string calldata newUri) 
        external 
        onlyAgentCreator(agentId) 
        onlyExistingAgent(agentId) 
    {
        _agents[agentId].agentCardUri = newUri;
        emit AgentCardUpdated(agentId, newUri);
    }

    /// @inheritdoc IERC8004Identity
    function getAgentCreator(uint256 agentId) external view onlyExistingAgent(agentId) returns (address creator) {
        return _agents[agentId].creator;
    }

    // =============================================================================
    // IERC8004Reputation Implementation
    // =============================================================================

    /// @notice Record feedback for an agent
    function recordFeedback(uint256 agentId, uint8 rating, bytes32 feedbackHash) 
        external 
        onlyExistingAgent(agentId) 
    {
        require(rating >= 1 && rating <= 5, "Rating must be 1-5");
        
        _ratingSum[agentId] += rating;
        _reviewCount[agentId]++;
        
        emit FeedbackRecorded(agentId, msg.sender, rating, feedbackHash);
    }

    /// @notice Get reputation for an agent
    function getReputation(uint256 agentId) 
        external 
        view 
        onlyExistingAgent(agentId) 
        returns (uint256 rating, uint256 totalReviews) 
    {
        totalReviews = _reviewCount[agentId];
        if (totalReviews == 0) {
            rating = 0;
        } else {
            // Return rating scaled by 100 (e.g., 350 = 3.50 average)
            rating = (_ratingSum[agentId] * 100) / totalReviews;
        }
    }

    // =============================================================================
    // IERC8004Validation Implementation
    // =============================================================================

    /// @notice Record validation result
    function recordValidation(uint256 agentId, bytes32 taskHash, bool isValid) 
        external 
        onlyExistingAgent(agentId) 
    {
        if (isValid) {
            _validCount[agentId]++;
        }
        _totalValidations[agentId]++;
        
        emit ValidationRecorded(agentId, msg.sender, taskHash, isValid);
    }

    /// @notice Get validation stats
    function getValidationStats(uint256 agentId) 
        external 
        view 
        onlyExistingAgent(agentId) 
        returns (uint256 validCount, uint256 totalCount) 
    {
        return (_validCount[agentId], _totalValidations[agentId]);
    }

    // =============================================================================
    // Clone Support Functions (called by Clone contract)
    // =============================================================================

    /// @notice Mint a cloned agent (called by Clone contract)
    function mintClone(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        uint256 parentAgentId,
        address cloner,
        string calldata agentCardUri
    ) external onlyAuthorizedConsumer returns (uint256 agentId) {
        if (dnaHash == bytes32(0)) revert InvalidDnaHash();
        if (_dnaHashToAgentId[dnaHash] != 0) revert InvalidDnaHash();

        agentId = _nextAgentId++;
        _totalAgents++;

        _agents[agentId] = AgentData({
            dnaHash: dnaHash,
            licenses: licenses,
            licensesMinted: 0,
            licensePrice: licensePrice,
            creator: cloner,
            cloneable: false, // Clones cannot be cloned
            isClone: true,
            parentAgentId: parentAgentId,
            agentCardUri: agentCardUri
        });

        _mint(cloner, agentId);
        _dnaHashToAgentId[dnaHash] = agentId;

        emit AgentMinted(agentId, cloner, dnaHash, licenses, licensePrice, false);
        emit AgentRegistered(agentId, cloner, dnaHash, agentCardUri);
    }

    /// @notice Mint a warped agent (called by Warp contract)
    function mintWarped(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        address warper,
        string calldata agentCardUri
    ) external onlyAuthorizedConsumer returns (uint256 agentId) {
        if (dnaHash == bytes32(0)) revert InvalidDnaHash();
        if (_dnaHashToAgentId[dnaHash] != 0) revert InvalidDnaHash();

        agentId = _nextAgentId++;
        _totalAgents++;

        _agents[agentId] = AgentData({
            dnaHash: dnaHash,
            licenses: licenses,
            licensesMinted: 0,
            licensePrice: licensePrice,
            creator: warper,
            cloneable: false, // Warped agents cannot be cloned
            isClone: false,
            parentAgentId: 0,
            agentCardUri: agentCardUri
        });

        _mint(warper, agentId);
        _dnaHashToAgentId[dnaHash] = agentId;

        emit AgentMinted(agentId, warper, dnaHash, licenses, licensePrice, false);
        emit AgentRegistered(agentId, warper, dnaHash, agentCardUri);
    }

    // =============================================================================
    // Admin Functions
    // =============================================================================

    /// @notice Authorize a contract to consume licenses
    function authorizeConsumer(address consumer) external onlyAdmin {
        _authorizedConsumers[consumer] = true;
    }

    /// @notice Revoke consumer authorization
    function revokeConsumer(address consumer) external onlyAdmin {
        _authorizedConsumers[consumer] = false;
    }

    /// @notice Check if address is authorized consumer
    function isAuthorizedConsumer(address consumer) external view returns (bool) {
        return _authorizedConsumers[consumer];
    }

    /// @notice Transfer admin rights
    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Zero address");
        _admin = newAdmin;
    }

    /// @notice Get admin address
    function getAdmin() external view returns (address) {
        return _admin;
    }

    // =============================================================================
    // ERC-721 Implementation
    // =============================================================================

    function name() external pure returns (string memory) {
        return "Manowar Agent";
    }

    function symbol() external pure returns (string memory) {
        return "MWAGENT";
    }

    function tokenURI(uint256 tokenId) external view onlyExistingAgent(tokenId) returns (string memory) {
        return _agents[tokenId].agentCardUri;
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "Zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view onlyExistingAgent(tokenId) returns (address) {
        return _owners[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        address owner = _owners[tokenId];
        require(to != owner, "Approval to current owner");
        require(
            msg.sender == owner || _operatorApprovals[owner][msg.sender],
            "Not owner or approved"
        );
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view onlyExistingAgent(tokenId) returns (address) {
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "Approve to caller");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not approved");
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "Non ERC721Receiver");
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f;   // ERC721Metadata
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "Mint to zero address");
        require(_owners[tokenId] == address(0), "Token exists");

        _balances[to]++;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(_owners[tokenId] == from, "Not owner");
        require(to != address(0), "Transfer to zero");

        // Clear approvals
        delete _tokenApprovals[tokenId];

        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        return (
            spender == owner ||
            _tokenApprovals[tokenId] == spender ||
            _operatorApprovals[owner][spender]
        );
    }

    function _checkOnERC721Received(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) internal returns (bool) {
        if (to.code.length == 0) return true;
        
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }
}

/// @notice ERC721 Receiver interface
interface IERC721Receiver {
    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4);
}
