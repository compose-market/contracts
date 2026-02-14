// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IManowar} from "./interfaces/Imanowar.sol";
import {IERC7401} from "./interfaces/IERC7401.sol";
import {IAgentFactory} from "./interfaces/Iagentfactory.sol";
import {IDistributor} from "./interfaces/Iroyalties.sol";

/// @notice Minimal IERC20 interface for payment token
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

/// @notice ERC-3009 interface for gasless USDC transfers
/// @dev Allows transfers via off-chain signatures, eliminating approve step
interface IERC3009 {
    function transferWithAuthorization(
        address from,
        address to,
        uint256 value,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
}

/**
 * @title Manowar
 * @notice ERC-7401 Nestable NFT for composing AI agent workflows
 * @dev Allows nesting ERC-8004 agents into workflow NFTs with coordinator support
 * 
 * Key Features:
 * - Nest multiple agents into a single workflow
 * - Optional coordinator agent for orchestration
 * - Leasing support with fee splitting
 * - RFA (Request-For-Agent) integration
 * - x402 pricing for pay-per-use
 */
contract Manowar is IManowar {
    // =============================================================================
    // Constants
    // =============================================================================

    uint8 public constant MAX_LEASE_PERCENT = 20;
    uint8 public constant TREASURY_FEE_PERCENT = 10;

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice Reference to AgentFactory
    IAgentFactory public immutable agentFactory;

    /// @notice USDC payment token
    IERC20 public immutable paymentToken;

    /// @notice Distributor contract for payment splits
    IDistributor public distributor;

    /// @notice Treasury wallet for platform fees
    address public treasury;

    /// @notice Total Manowars minted
    uint256 private _totalManowars;

    /// @notice Next Manowar ID
    uint256 private _nextManowarId;

    /// @notice Manowar data storage
    mapping(uint256 => ManowarData) private _manowars;

    /// @notice ERC-721 ownership
    mapping(uint256 => address) private _owners;

    /// @notice ERC-721 balances
    mapping(address => uint256) private _balances;

    /// @notice ERC-721 token approvals
    mapping(uint256 => address) private _tokenApprovals;

    /// @notice ERC-721 operator approvals
    mapping(address => mapping(address => bool)) private _operatorApprovals;

    /// @notice Nested children: manowarId => Child[]
    mapping(uint256 => Child[]) private _children;

    /// @notice Child index lookup: manowarId => childContract => childId => index+1 (0 means not nested)
    mapping(uint256 => mapping(address => mapping(uint256 => uint256))) private _childIndex;

    /// @notice Pending children proposals
    mapping(uint256 => Child[]) private _pendingChildren;

    /// @notice Parent lookup: childContract => childId => (hasParent, parentContract, parentId)
    mapping(address => mapping(uint256 => ParentInfo)) private _parentInfo;

    /// @notice Manowars by creator
    mapping(address => uint256[]) private _manowarsByCreator;

    /// @notice Complete Manowars (no active RFA)
    uint256[] private _completeManowars;

    /// @notice Manowars with active RFA
    uint256[] private _manowarsWithRFA;

    /// @notice Index in _completeManowars (for removal)
    mapping(uint256 => uint256) private _completeManowarIndex;

    /// @notice Index in _manowarsWithRFA (for removal)
    mapping(uint256 => uint256) private _rfaManowarIndex;

    /// @notice Authorized RFA contract
    address private _rfaContract;

    /// @notice Authorized Lease contract
    address private _leaseContract;

    /// @notice Admin address
    address private _admin;

    // =============================================================================
    // Structs
    // =============================================================================

    struct ParentInfo {
        bool hasParent;
        address parentContract;
        uint256 parentId;
    }

    // =============================================================================
    // Events
    // =============================================================================

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    // =============================================================================
    // Modifiers
    // =============================================================================

    modifier onlyAdmin() {
        require(msg.sender == _admin, "Not admin");
        _;
    }

    modifier onlyOwner(uint256 manowarId) {
        if (_owners[manowarId] != msg.sender) revert NotManowarOwner(manowarId);
        _;
    }

    modifier manowarExists(uint256 manowarId) {
        if (_owners[manowarId] == address(0)) revert ManowarNotFound(manowarId);
        _;
    }

    modifier onlyRFAContract() {
        require(msg.sender == _rfaContract, "Not RFA contract");
        _;
    }

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address _agentFactory, address _paymentToken) {
        require(_agentFactory != address(0), "Zero address");
        require(_paymentToken != address(0), "Zero payment token");
        agentFactory = IAgentFactory(_agentFactory);
        paymentToken = IERC20(_paymentToken);
        _admin = msg.sender;
        _nextManowarId = 1;
    }

    // =============================================================================
    // IManowar Implementation
    // =============================================================================

    /// @inheritdoc IManowar
    function mintManowar(
        MintParams calldata params,
        uint256[] calldata agentIds
    ) external returns (uint256 manowarId) {
        if (params.units == 0) revert InvalidUnits();
        if (params.leaseEnabled && params.leasePercent > MAX_LEASE_PERCENT) {
            revert InvalidLeasePercent();
        }

        manowarId = _nextManowarId++;
        _totalManowars++;

        // Calculate total license price from agents and build creator arrays for distribution
        uint256 totalPrice = 0;
        address[] memory creators = new address[](agentIds.length);
        uint256[] memory prices = new uint256[](agentIds.length);
        
        for (uint256 i = 0; i < agentIds.length; i++) {
            IAgentFactory.AgentData memory agentData = agentFactory.getAgentData(agentIds[i]);
            totalPrice += agentData.licensePrice;
            creators[i] = agentData.creator;
            prices[i] = agentData.licensePrice;
            // Note: License consumption happens in _nestAgent below
        }

        // Collect payment from minter and distribute (10% treasury, 90% to creators)
        if (totalPrice > 0) {
            require(
                paymentToken.transferFrom(msg.sender, address(this), totalPrice),
                "Payment transfer failed"
            );
            
            // Calculate treasury fee (10%)
            uint256 treasuryFee = (totalPrice * TREASURY_FEE_PERCENT) / 100;
            uint256 creatorsTotal = totalPrice - treasuryFee;
            
            // Send treasury fee
            if (treasuryFee > 0 && treasury != address(0)) {
                require(
                    paymentToken.transfer(treasury, treasuryFee),
                    "Treasury payment failed"
                );
            }
            
            // Distribute remaining 90% to agent creators proportionally
            if (creatorsTotal > 0) {
                for (uint256 i = 0; i < agentIds.length; i++) {
                    if (prices[i] > 0) {
                        // Calculate creator's proportional share of the 90%
                        uint256 creatorShare = (prices[i] * creatorsTotal) / totalPrice;
                        require(
                            paymentToken.transfer(creators[i], creatorShare),
                            "Creator payment failed"
                        );
                    }
                }
            }
        }

        // Store Manowar data
        _manowars[manowarId] = ManowarData({
            title: params.title,
            description: params.description,
            banner: params.banner,
            manowarCardUri: params.manowarCardUri,
            totalPrice: totalPrice,
            units: params.units,
            unitsMinted: 0,
            creator: msg.sender,
            leaseEnabled: params.leaseEnabled,
            leaseDuration: params.leaseDuration,
            leasePercent: params.leasePercent,
            hasCoordinator: params.hasCoordinator,
            coordinatorModel: params.coordinatorModel,
            hasActiveRfa: false,
            rfaId: 0
        });

        // Mint the NFT
        _mint(msg.sender, manowarId);

        // Track by creator
        _manowarsByCreator[msg.sender].push(manowarId);

        // Add to complete list (no RFA initially)
        _completeManowarIndex[manowarId] = _completeManowars.length;
        _completeManowars.push(manowarId);

        // Nest the agents
        for (uint256 i = 0; i < agentIds.length; i++) {
            _nestAgent(manowarId, agentIds[i]);
        }

        emit ManowarMinted(manowarId, msg.sender, params.title, 0, params.units);
    }

    /**
     * @notice Mint a Manowar workflow using ERC-3009 gasless authorization
     * @dev Allows minting with a single off-chain signature, no approve step needed
     * @param params Minting parameters (title, description, etc.)
     * @param agentIds Array of agent IDs to nest
     * @param validAfter Unix timestamp after which the transfer authorization is valid
     * @param validBefore Unix timestamp before which the transfer authorization is valid
     * @param authNonce Unique nonce for the transfer authorization
     * @param v ECDSA recovery id
     * @param r ECDSA signature r component
     * @param s ECDSA signature s component
     * @return manowarId The ID of the newly minted Manowar
     */
    function mintManowarWithAuth(
        MintParams calldata params,
        uint256[] calldata agentIds,
        address payer,
        uint256 validAfter,
        uint256 validBefore,
        bytes32 authNonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 manowarId) {
        if (params.units == 0) revert InvalidUnits();
        if (params.leaseEnabled && params.leasePercent > MAX_LEASE_PERCENT) {
            revert InvalidLeasePercent();
        }

        manowarId = _nextManowarId++;
        _totalManowars++;

        // Calculate total license price from agents and build creator arrays
        uint256 totalPrice = 0;
        address[] memory creators = new address[](agentIds.length);
        uint256[] memory prices = new uint256[](agentIds.length);
        
        for (uint256 i = 0; i < agentIds.length; i++) {
            IAgentFactory.AgentData memory agentData = agentFactory.getAgentData(agentIds[i]);
            totalPrice += agentData.licensePrice;
            creators[i] = agentData.creator;
            prices[i] = agentData.licensePrice;
        }

        // Use ERC-3009 transferWithAuthorization for gasless transfer
        if (totalPrice > 0) {
            // Transfer tokens using the signed authorization
            IERC3009(address(paymentToken)).transferWithAuthorization(
                payer,           // from
                address(this),   // to
                totalPrice,      // value
                validAfter,
                validBefore,
                authNonce,
                v, r, s
            );
            
            // Calculate treasury fee (10%)
            uint256 treasuryFee = (totalPrice * TREASURY_FEE_PERCENT) / 100;
            uint256 creatorsTotal = totalPrice - treasuryFee;
            
            // Send treasury fee
            if (treasuryFee > 0 && treasury != address(0)) {
                require(
                    paymentToken.transfer(treasury, treasuryFee),
                    "Treasury payment failed"
                );
            }
            
            // Distribute remaining 90% to agent creators proportionally
            if (creatorsTotal > 0) {
                for (uint256 i = 0; i < agentIds.length; i++) {
                    if (prices[i] > 0) {
                        uint256 creatorShare = (prices[i] * creatorsTotal) / totalPrice;
                        require(
                            paymentToken.transfer(creators[i], creatorShare),
                            "Creator payment failed"
                        );
                    }
                }
            }
        }

        // Store Manowar data
        _manowars[manowarId] = ManowarData({
            title: params.title,
            description: params.description,
            banner: params.banner,
            manowarCardUri: params.manowarCardUri,
            totalPrice: totalPrice,
            units: params.units,
            unitsMinted: 0,
            creator: payer,  // Use payer as creator since they paid
            leaseEnabled: params.leaseEnabled,
            leaseDuration: params.leaseDuration,
            leasePercent: params.leasePercent,
            hasCoordinator: params.hasCoordinator,
            coordinatorModel: params.coordinatorModel,
            hasActiveRfa: false,
            rfaId: 0
        });

        // Mint the NFT to the payer
        _mint(payer, manowarId);

        // Track by creator
        _manowarsByCreator[payer].push(manowarId);

        // Add to complete list (no RFA initially)
        _completeManowarIndex[manowarId] = _completeManowars.length;
        _completeManowars.push(manowarId);

        // Nest the agents
        for (uint256 i = 0; i < agentIds.length; i++) {
            _nestAgent(manowarId, agentIds[i]);
        }

        emit ManowarMinted(manowarId, payer, params.title, 0, params.units);
    }

    /// @inheritdoc IManowar
    function getManowarData(uint256 manowarId) external view manowarExists(manowarId) returns (ManowarData memory) {
        return _manowars[manowarId];
    }

    /// @inheritdoc IManowar
    function addAgent(uint256 manowarId, uint256 agentId) external onlyOwner(manowarId) manowarExists(manowarId) {
        _nestAgent(manowarId, agentId);
        
        // Update total price with license price
        IAgentFactory.AgentData memory agentData = agentFactory.getAgentData(agentId);
        _manowars[manowarId].totalPrice += agentData.licensePrice;
        
        emit AgentAdded(manowarId, agentId);
    }

    /// @inheritdoc IManowar
    function removeAgent(uint256 manowarId, uint256 agentId) external onlyOwner(manowarId) manowarExists(manowarId) {
        address agentFactoryAddr = address(agentFactory);
        uint256 idx = _childIndex[manowarId][agentFactoryAddr][agentId];
        if (idx == 0) revert AgentNotInManowar(manowarId, agentId);

        // Update total price with license price
        IAgentFactory.AgentData memory agentData = agentFactory.getAgentData(agentId);
        _manowars[manowarId].totalPrice -= agentData.licensePrice;

        // Revoke the license in AgentFactory (bi-directional tracking)
        try agentFactory.revokeLicense(agentId, address(this), manowarId) {} catch {}

        // Remove from children array (swap and pop)
        uint256 lastIdx = _children[manowarId].length - 1;
        if (idx - 1 != lastIdx) {
            Child memory lastChild = _children[manowarId][lastIdx];
            _children[manowarId][idx - 1] = lastChild;
            _childIndex[manowarId][lastChild.contractAddress][lastChild.tokenId] = idx;
        }
        _children[manowarId].pop();
        delete _childIndex[manowarId][agentFactoryAddr][agentId];

        // Clear parent info
        delete _parentInfo[agentFactoryAddr][agentId];

        emit AgentRemoved(manowarId, agentId);
        emit ChildUnnested(manowarId, agentId, agentFactoryAddr);
    }

    /// @inheritdoc IManowar
    function getAgents(uint256 manowarId) external view manowarExists(manowarId) returns (uint256[] memory agentIds) {
        Child[] storage children = _children[manowarId];
        agentIds = new uint256[](children.length);
        for (uint256 i = 0; i < children.length; i++) {
            agentIds[i] = children[i].tokenId;
        }
    }

    /// @inheritdoc IManowar
    function getAgentCount(uint256 manowarId) external view manowarExists(manowarId) returns (uint256) {
        return _children[manowarId].length;
    }

    /// @inheritdoc IManowar
    function setCoordinator(
        uint256 manowarId, 
        bool hasCoordinator, 
        string calldata model
    ) external onlyOwner(manowarId) manowarExists(manowarId) {
        _manowars[manowarId].hasCoordinator = hasCoordinator;
        _manowars[manowarId].coordinatorModel = model;
        emit CoordinatorSet(manowarId, hasCoordinator ? 1 : 0, model);
    }

    /// @inheritdoc IManowar
    function updateLeaseSettings(
        uint256 manowarId,
        bool enabled,
        uint256 duration,
        uint8 percent
    ) external onlyOwner(manowarId) manowarExists(manowarId) {
        if (enabled && percent > MAX_LEASE_PERCENT) revert InvalidLeasePercent();
        
        ManowarData storage data = _manowars[manowarId];
        data.leaseEnabled = enabled;
        data.leaseDuration = duration;
        data.leasePercent = percent;
        
        emit LeaseStatusChanged(manowarId, enabled, duration, percent);
    }

    /// @inheritdoc IManowar
    function attachRFA(uint256 manowarId, uint256 rfaId) external onlyRFAContract manowarExists(manowarId) {
        ManowarData storage data = _manowars[manowarId];
        if (data.hasActiveRfa) revert ManowarHasActiveRFA(manowarId);
        
        data.hasActiveRfa = true;
        data.rfaId = rfaId;

        // Move from complete to RFA list
        _removeFromCompleteList(manowarId);
        _rfaManowarIndex[manowarId] = _manowarsWithRFA.length;
        _manowarsWithRFA.push(manowarId);
        
        emit RFAAttached(manowarId, rfaId);
    }

    /// @inheritdoc IManowar
    function resolveRFA(uint256 manowarId) external onlyRFAContract manowarExists(manowarId) {
        ManowarData storage data = _manowars[manowarId];
        
        uint256 resolvedRfaId = data.rfaId;
        data.hasActiveRfa = false;
        data.rfaId = 0;

        // Move from RFA to complete list
        _removeFromRFAList(manowarId);
        _completeManowarIndex[manowarId] = _completeManowars.length;
        _completeManowars.push(manowarId);
        
        emit RFAResolved(manowarId, resolvedRfaId);
    }

    /// @inheritdoc IManowar
    function isComplete(uint256 manowarId) external view manowarExists(manowarId) returns (bool) {
        return !_manowars[manowarId].hasActiveRfa;
    }

    /// @inheritdoc IManowar
    function hasAvailableUnits(uint256 manowarId) external view manowarExists(manowarId) returns (bool) {
        ManowarData storage data = _manowars[manowarId];
        return data.unitsMinted < data.units;
    }

    /// @inheritdoc IManowar
    function consumeUnit(uint256 manowarId, address buyer) 
        external 
        manowarExists(manowarId) 
        returns (uint256 unitNumber) 
    {
        ManowarData storage data = _manowars[manowarId];
        if (data.unitsMinted >= data.units) revert NoUnitsAvailable(manowarId);
        
        unitNumber = ++data.unitsMinted;
        
        // Note: Agents are already licensed at nesting time, not usage time
        // The Manowar's units track how many times the workflow can be used
        // Agent licenses were consumed when they were nested into the Manowar
    }

    /// @inheritdoc IManowar
    function calculateTotalPrice(uint256 manowarId) external view manowarExists(manowarId) returns (uint256) {
        return _manowars[manowarId].totalPrice;
    }

    /// @inheritdoc IManowar
    function getManowarsByCreator(address creator) external view returns (uint256[] memory) {
        return _manowarsByCreator[creator];
    }

    /// @inheritdoc IManowar
    function totalManowars() external view returns (uint256) {
        return _totalManowars;
    }

    /// @inheritdoc IManowar
    function getCompleteManowars() external view returns (uint256[] memory) {
        return _completeManowars;
    }

    /// @inheritdoc IManowar
    function getManowarsWithRFA() external view returns (uint256[] memory) {
        return _manowarsWithRFA;
    }

    /// @inheritdoc IManowar
    function getAgentFactory() external view returns (address) {
        return address(agentFactory);
    }

    /**
     * @notice Get lease-specific info for a Manowar
     * @param manowarId The Manowar ID
     * @return leaseEnabled Whether leasing is enabled
     * @return creator The creator address
     * @return leasePercent The lease percentage
     */
    function getLeaseInfo(uint256 manowarId) external view manowarExists(manowarId) returns (
        bool leaseEnabled,
        address creator,
        uint8 leasePercent
    ) {
        ManowarData storage data = _manowars[manowarId];
        return (data.leaseEnabled, data.creator, data.leasePercent);
    }

    // =============================================================================
    // IERC7401 Implementation
    // =============================================================================

    /// @inheritdoc IERC7401
    function nestChild(
        uint256 parentId,
        address childContract,
        uint256 childId
    ) external onlyOwner(parentId) manowarExists(parentId) {
        require(childContract == address(agentFactory), "Only agents can be nested");
        _nestAgent(parentId, childId);
    }

    /// @inheritdoc IERC7401
    function unnestChild(
        uint256 parentId,
        address childContract,
        uint256 childId,
        address to
    ) external onlyOwner(parentId) manowarExists(parentId) {
        require(childContract == address(agentFactory), "Only agents can be unnested");
        require(to != address(0), "Zero address");
        
        uint256 idx = _childIndex[parentId][childContract][childId];
        if (idx == 0) revert AgentNotInManowar(parentId, childId);

        // Update total price with license price
        IAgentFactory.AgentData memory agentData = agentFactory.getAgentData(childId);
        _manowars[parentId].totalPrice -= agentData.licensePrice;

        // Revoke the license in AgentFactory (bi-directional tracking)
        try agentFactory.revokeLicense(childId, address(this), parentId) {} catch {}

        // Remove from children
        uint256 lastIdx = _children[parentId].length - 1;
        if (idx - 1 != lastIdx) {
            Child memory lastChild = _children[parentId][lastIdx];
            _children[parentId][idx - 1] = lastChild;
            _childIndex[parentId][lastChild.contractAddress][lastChild.tokenId] = idx;
        }
        _children[parentId].pop();
        delete _childIndex[parentId][childContract][childId];
        delete _parentInfo[childContract][childId];

        emit ChildUnnested(parentId, childId, childContract);
    }

    /// @inheritdoc IERC7401
    function childrenOf(uint256 parentId) external view manowarExists(parentId) returns (Child[] memory) {
        return _children[parentId];
    }

    /// @inheritdoc IERC7401
    function childCount(uint256 parentId) external view manowarExists(parentId) returns (uint256) {
        return _children[parentId].length;
    }

    /// @inheritdoc IERC7401
    function parentOf(
        address childContract,
        uint256 childId
    ) external view returns (bool hasParent, address parentContract, uint256 parentId) {
        ParentInfo storage info = _parentInfo[childContract][childId];
        return (info.hasParent, info.parentContract, info.parentId);
    }

    /// @inheritdoc IERC7401
    function proposeChild(uint256 parentId, address childContract, uint256 childId) external {
        // Simplified: directly nest if caller owns the child
        // Full implementation would track proposals
        _pendingChildren[parentId].push(Child(childContract, childId));
        emit ChildProposed(parentId, childId, childContract);
    }

    /// @inheritdoc IERC7401
    function acceptChild(uint256 parentId, address childContract, uint256 childId) external onlyOwner(parentId) {
        // Find and remove from pending
        Child[] storage pending = _pendingChildren[parentId];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i].contractAddress == childContract && pending[i].tokenId == childId) {
                // Remove from pending
                pending[i] = pending[pending.length - 1];
                pending.pop();
                
                // Nest the child
                if (childContract == address(agentFactory)) {
                    _nestAgent(parentId, childId);
                }
                
                emit ChildAccepted(parentId, childId, childContract);
                return;
            }
        }
        revert("Proposal not found");
    }

    /// @inheritdoc IERC7401
    function rejectChild(uint256 parentId, address childContract, uint256 childId) external onlyOwner(parentId) {
        Child[] storage pending = _pendingChildren[parentId];
        for (uint256 i = 0; i < pending.length; i++) {
            if (pending[i].contractAddress == childContract && pending[i].tokenId == childId) {
                pending[i] = pending[pending.length - 1];
                pending.pop();
                return;
            }
        }
    }

    /// @inheritdoc IERC7401
    function pendingChildrenOf(uint256 parentId) external view returns (Child[] memory) {
        return _pendingChildren[parentId];
    }

    // =============================================================================
    // Admin Functions
    // =============================================================================

    function setRFAContract(address rfaContract) external onlyAdmin {
        _rfaContract = rfaContract;
    }

    function setLeaseContract(address leaseContract) external onlyAdmin {
        _leaseContract = leaseContract;
    }

    function setDistributor(address _distributor) external onlyAdmin {
        require(_distributor != address(0), "Zero address");
        distributor = IDistributor(_distributor);
    }

    function setTreasury(address _treasury) external onlyAdmin {
        require(_treasury != address(0), "Zero address");
        treasury = _treasury;
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Zero address");
        _admin = newAdmin;
    }

    function getAdmin() external view returns (address) {
        return _admin;
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    function _nestAgent(uint256 manowarId, uint256 agentId) internal {
        address agentFactoryAddr = address(agentFactory);
        
        // Check not already nested
        require(_childIndex[manowarId][agentFactoryAddr][agentId] == 0, "Already nested");
        
        // Verify agent exists
        require(agentFactory.agentExists(agentId), "Agent not found");
        
        // Consume license in AgentFactory (bi-directional tracking)
        // This records the license relationship and decrements available licenses
        agentFactory.consumeLicense(agentId, address(this), manowarId);
        
        // Add to children
        _children[manowarId].push(Child(agentFactoryAddr, agentId));
        _childIndex[manowarId][agentFactoryAddr][agentId] = _children[manowarId].length;
        
        // Set parent info
        _parentInfo[agentFactoryAddr][agentId] = ParentInfo({
            hasParent: true,
            parentContract: address(this),
            parentId: manowarId
        });
        
        emit ChildNested(manowarId, agentId, agentFactoryAddr);
    }

    function _removeFromCompleteList(uint256 manowarId) internal {
        uint256 idx = _completeManowarIndex[manowarId];
        uint256 lastIdx = _completeManowars.length - 1;
        
        if (idx != lastIdx) {
            uint256 lastManowarId = _completeManowars[lastIdx];
            _completeManowars[idx] = lastManowarId;
            _completeManowarIndex[lastManowarId] = idx;
        }
        
        _completeManowars.pop();
        delete _completeManowarIndex[manowarId];
    }

    function _removeFromRFAList(uint256 manowarId) internal {
        uint256 idx = _rfaManowarIndex[manowarId];
        uint256 lastIdx = _manowarsWithRFA.length - 1;
        
        if (idx != lastIdx) {
            uint256 lastManowarId = _manowarsWithRFA[lastIdx];
            _manowarsWithRFA[idx] = lastManowarId;
            _rfaManowarIndex[lastManowarId] = idx;
        }
        
        _manowarsWithRFA.pop();
        delete _rfaManowarIndex[manowarId];
    }

    // =============================================================================
    // ERC-721 Implementation
    // =============================================================================

    function name() external pure returns (string memory) {
        return "Manowar Workflow";
    }

    function symbol() external pure returns (string memory) {
        return "MANOWAR";
    }

    function tokenURI(uint256 tokenId) external view manowarExists(tokenId) returns (string memory) {
        // Return manowarCardUri - full metadata containing nested agentCards
        return _manowars[tokenId].manowarCardUri;
    }

    function balanceOf(address owner) external view returns (uint256) {
        require(owner != address(0), "Zero address");
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) external view manowarExists(tokenId) returns (address) {
        return _owners[tokenId];
    }

    function approve(address to, uint256 tokenId) external {
        address owner = _owners[tokenId];
        require(to != owner, "Approval to owner");
        require(msg.sender == owner || _operatorApprovals[owner][msg.sender], "Not authorized");
        _tokenApprovals[tokenId] = to;
        emit Approval(owner, to, tokenId);
    }

    function getApproved(uint256 tokenId) external view manowarExists(tokenId) returns (address) {
        return _tokenApprovals[tokenId];
    }

    function setApprovalForAll(address operator, bool approved) external {
        require(operator != msg.sender, "Self approval");
        _operatorApprovals[msg.sender][operator] = approved;
        emit ApprovalForAll(msg.sender, operator, approved);
    }

    function isApprovedForAll(address owner, address operator) external view returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    function transferFrom(address from, address to, uint256 tokenId) external {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
    }

    function safeTransferFrom(address from, address to, uint256 tokenId) external {
        safeTransferFrom(from, to, tokenId, "");
    }

    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) public {
        require(_isApprovedOrOwner(msg.sender, tokenId), "Not authorized");
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, data), "Non receiver");
    }

    function supportsInterface(bytes4 interfaceId) external pure returns (bool) {
        return
            interfaceId == 0x01ffc9a7 || // ERC165
            interfaceId == 0x80ac58cd || // ERC721
            interfaceId == 0x5b5e139f;   // ERC721Metadata
    }

    function _mint(address to, uint256 tokenId) internal {
        require(to != address(0), "Zero address");
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(address(0), to, tokenId);
    }

    function _transfer(address from, address to, uint256 tokenId) internal {
        require(_owners[tokenId] == from, "Not owner");
        require(to != address(0), "Zero address");
        delete _tokenApprovals[tokenId];
        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        return spender == owner || _tokenApprovals[tokenId] == spender || _operatorApprovals[owner][spender];
    }

    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory data) internal returns (bool) {
        if (to.code.length == 0) return true;
        try IERC721Receiver(to).onERC721Received(msg.sender, from, tokenId, data) returns (bytes4 retval) {
            return retval == IERC721Receiver.onERC721Received.selector;
        } catch {
            return false;
        }
    }
}

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

