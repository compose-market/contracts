// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ILease} from "./interfaces/Ilease.sol";

/**
 * @title Lease
 * @notice Contract for leasing Workflows
 * @dev Handles fee splitting between creator and leaser during lease period
 * 
 * Fee Split:
 * - Creator receives leasePercent (max 20%) of usage fees
 * - Leaser receives remaining (100 - leasePercent)%
 */
contract Lease is ILease {
    error UnsupportedChain(uint256 chainId);

    // =============================================================================
    // Constants
    // =============================================================================

    uint8 public constant MAX_LEASE_PERCENT = 20;

    // =============================================================================
    // State Variables
    // =============================================================================

    /// @notice USDC token contract
    IERC20 public immutable usdc;

    /// @notice Workflow contract reference
    address public workflowContract;

    /// @notice Total leases created
    uint256 private _totalLeases;

    /// @notice Next lease ID
    uint256 private _nextLeaseId;

    /// @notice Lease data storage
    mapping(uint256 => LeaseData) private _leases;

    /// @notice Active lease for each Workflow: workflowId => leaseId (0 if none)
    mapping(uint256 => uint256) private _activeLeases;

    /// @notice Leases by leaser address
    mapping(address => uint256[]) private _leasesByLeaser;

    /// @notice Admin address
    address private _admin;

    // =============================================================================
    // Constructor
    // =============================================================================

    constructor(address _workflowContract, address _adminAddress) {
        require(_workflowContract != address(0), "Zero Workflow address");
        require(_adminAddress != address(0), "Zero admin");

        address usdcAddress = _getUSDCAddress(block.chainid);
        if (usdcAddress == address(0)) {
            revert UnsupportedChain(block.chainid);
        }
        
        usdc = IERC20(usdcAddress);
        workflowContract = _workflowContract;
        _admin = _adminAddress;
        _nextLeaseId = 1;
    }

    function _getUSDCAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 43113) return 0x5425890298aed601595a70AB815c96711a31Bc65; // Avalanche Fuji
        if (chainId == 43114) return 0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E; // Avalanche C-Chain
        return address(0);
    }

    // =============================================================================
    // ILease Implementation
    // =============================================================================

    /// @inheritdoc ILease
    function createLease(uint256 workflowId, uint256 duration) external returns (uint256 leaseId) {
        if (duration == 0) revert InvalidLeaseDuration();
        if (_activeLeases[workflowId] != 0) revert LeaseAlreadyExists(workflowId);

        // Get Workflow data to verify leasing is enabled
        (bool leasable, address creator, uint8 creatorPercent) = _getWorkflowLeaseInfo(workflowId);
        if (!leasable) revert WorkflowNotLeasable(workflowId);
        if (creatorPercent > MAX_LEASE_PERCENT) revert InvalidLeasePercent();

        leaseId = _nextLeaseId++;
        _totalLeases++;

        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + (duration * 1 days);

        // Store lease data
        _leases[leaseId] = LeaseData({
            workflowId: workflowId,
            leaser: msg.sender,
            creator: creator,
            startTime: startTime,
            endTime: endTime,
            creatorPercent: creatorPercent,
            status: LeaseStatus.Active
        });

        // Set as active lease
        _activeLeases[workflowId] = leaseId;

        // Track by leaser
        _leasesByLeaser[msg.sender].push(leaseId);

        emit LeaseCreated(leaseId, workflowId, msg.sender, duration, creatorPercent);
    }

    /// @inheritdoc ILease
    function terminateLease(uint256 leaseId) external {
        LeaseData storage lease = _leases[leaseId];
        
        if (lease.status != LeaseStatus.Active) revert LeaseNotActive(leaseId);
        if (lease.leaser != msg.sender && lease.creator != msg.sender) {
            revert NotLeaser(leaseId);
        }

        lease.status = LeaseStatus.Terminated;
        
        // Clear active lease
        delete _activeLeases[lease.workflowId];

        emit LeaseTerminated(leaseId, lease.workflowId);
    }

    /// @inheritdoc ILease
    function getLeaseData(uint256 leaseId) external view returns (LeaseData memory) {
        if (_leases[leaseId].leaser == address(0)) revert LeaseNotFound(leaseId);
        return _leases[leaseId];
    }

    /// @inheritdoc ILease
    function getActiveLeaseFor(uint256 workflowId) external view returns (uint256) {
        uint256 leaseId = _activeLeases[workflowId];
        if (leaseId != 0) {
            LeaseData storage lease = _leases[leaseId];
            // Check if expired
            if (block.timestamp > lease.endTime) {
                return 0;
            }
        }
        return leaseId;
    }

    /// @inheritdoc ILease
    function isLeased(uint256 workflowId) external view returns (bool) {
        uint256 leaseId = _activeLeases[workflowId];
        if (leaseId == 0) return false;
        
        LeaseData storage lease = _leases[leaseId];
        return lease.status == LeaseStatus.Active && block.timestamp <= lease.endTime;
    }

    /// @inheritdoc ILease
    function calculateFeeSplit(
        uint256 leaseId,
        uint256 totalAmount
    ) external view returns (uint256 creatorShare, uint256 leaserShare) {
        LeaseData storage lease = _leases[leaseId];
        if (lease.leaser == address(0)) revert LeaseNotFound(leaseId);
        
        creatorShare = (totalAmount * lease.creatorPercent) / 100;
        leaserShare = totalAmount - creatorShare;
    }

    /// @inheritdoc ILease
    function distributeFees(uint256 leaseId, uint256 amount) external {
        LeaseData storage lease = _leases[leaseId];
        
        if (lease.status != LeaseStatus.Active) revert LeaseNotActive(leaseId);
        if (block.timestamp > lease.endTime) revert LeaseExpired(leaseId);

        uint256 creatorShare = (amount * lease.creatorPercent) / 100;
        uint256 leaserShare = amount - creatorShare;

        // Transfer fees
        if (creatorShare > 0) {
            bool success = usdc.transferFrom(msg.sender, lease.creator, creatorShare);
            require(success, "Creator transfer failed");
        }
        
        if (leaserShare > 0) {
            bool success = usdc.transferFrom(msg.sender, lease.leaser, leaserShare);
            require(success, "Leaser transfer failed");
        }

        emit LeaseFeesDistributed(leaseId, amount, creatorShare, leaserShare);
    }

    /// @inheritdoc ILease
    function getLeaseStatus(uint256 leaseId) external view returns (LeaseStatus) {
        LeaseData storage lease = _leases[leaseId];
        
        if (lease.leaser == address(0)) return LeaseStatus.None;
        if (lease.status == LeaseStatus.Terminated) return LeaseStatus.Terminated;
        if (block.timestamp > lease.endTime) return LeaseStatus.Expired;
        
        return lease.status;
    }

    /// @inheritdoc ILease
    function getLeasesFor(address leaser) external view returns (uint256[] memory) {
        return _leasesByLeaser[leaser];
    }

    // =============================================================================
    // Internal Functions
    // =============================================================================

    function _getWorkflowLeaseInfo(uint256 workflowId) internal view returns (
        bool leasable,
        address creator,
        uint8 creatorPercent
    ) {
        // Call Workflow.getLeaseInfo(workflowId) which returns (bool, address, uint8)
        (bool success, bytes memory data) = workflowContract.staticcall(
            abi.encodeWithSignature("getLeaseInfo(uint256)", workflowId)
        );
        
        if (!success) return (false, address(0), 0);
        
        (leasable, creator, creatorPercent) = abi.decode(data, (bool, address, uint8));
    }

    // =============================================================================
    // Admin Functions
    // =============================================================================

    function setWorkflowContract(address _workflow) external {
        require(msg.sender == _admin, "Not admin");
        workflowContract = _workflow;
    }

    function transferAdmin(address newAdmin) external {
        require(msg.sender == _admin, "Not admin");
        require(newAdmin != address(0), "Zero address");
        _admin = newAdmin;
    }

    // =============================================================================
    // View Functions
    // =============================================================================

    function totalLeases() external view returns (uint256) {
        return _totalLeases;
    }

    function getAdmin() external view returns (address) {
        return _admin;
    }

    function getUSDC() external view returns (address) {
        return address(usdc);
    }

    /// @notice Expire a lease if past end time
    function expireLeaseIfNeeded(uint256 leaseId) external {
        LeaseData storage lease = _leases[leaseId];
        if (lease.status == LeaseStatus.Active && block.timestamp > lease.endTime) {
            lease.status = LeaseStatus.Expired;
            delete _activeLeases[lease.workflowId];
        }
    }
}

// =============================================================================
// Minimal IERC20 Interface
// =============================================================================

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}
