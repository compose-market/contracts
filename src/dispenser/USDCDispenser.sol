// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title USDCDispenser
 * @notice dispenser for distributing USDC to new accounts
 * @dev Only authorized callers (our backend) can trigger claims
 * 
 * CHAIN-AWARE: Automatically determines USDC address based on chain ID.
 * This allows the SAME contract bytecode to be deployed at the SAME address
 * across multiple chains using CREATE2.
 */
contract USDCDispenser is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    // Chain-specific USDC addresses (hardcoded for deterministic deployment)
    address private immutable USDC_ADDRESS;

    uint256 public claimAmount;
    uint256 public maxClaims;
    uint256 public totalClaims;

    mapping(address => bool) public authorizedCallers;
    mapping(address => bool) public hasClaimed;

    event Claimed(address indexed recipient, uint256 amount, uint256 totalClaims, uint256 indexed chainId);
    event Funded(address indexed funder, uint256 amount, uint256 newBalance);
    event AuthorizedCallerAdded(address indexed caller);
    event AuthorizedCallerRemoved(address indexed caller);
    event ClaimAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event MaxClaimsUpdated(uint256 oldMax, uint256 newMax);
    event EmergencyWithdraw(address indexed to, uint256 amount);

    error UnauthorizedCaller(address caller);
    error AlreadyClaimed(address recipient);
    error MaxClaimsReached(uint256 current, uint256 max);
    error InsufficientDispenserBalance(uint256 balance, uint256 required);
    error InvalidAmount();
    error ZeroAddress();
    error UnsupportedChain(uint256 chainId);

    constructor(
        address _owner,
        address _authorizedCaller,
        uint256 _claimAmount,
        uint256 _maxClaims
    ) Ownable(_owner) {
        if (_owner == address(0) || _authorizedCaller == address(0)) {
            revert ZeroAddress();
        }
        if (_claimAmount == 0 || _maxClaims == 0) {
            revert InvalidAmount();
        }

        // Determine USDC address based on chain ID
        USDC_ADDRESS = _getUSDCAddress(block.chainid);
        if (USDC_ADDRESS == address(0)) {
            revert UnsupportedChain(block.chainid);
        }

        claimAmount = _claimAmount;
        maxClaims = _maxClaims;
        authorizedCallers[_authorizedCaller] = true;

        emit AuthorizedCallerAdded(_authorizedCaller);
        emit ClaimAmountUpdated(0, _claimAmount);
        emit MaxClaimsUpdated(0, _maxClaims);
    }

    function _getUSDCAddress(uint256 chainId) internal pure returns (address) {
        if (chainId == 43113) return 0x5425890298aed601595a70AB815c96711a31Bc65;   // Avalanche Fuji
        if (chainId == 421614) return 0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d;  // Arbitrum Sepolia
        if (chainId == 84532) return 0x036CbD53842c5426634e7929541eC2318f3dCF7e; // Base Sepolia
        return address(0);
    }

    function claimUSDC(address recipient)
        external
        nonReentrant
        whenNotPaused
    {
        if (!authorizedCallers[msg.sender]) {
            revert UnauthorizedCaller(msg.sender);
        }
        if (recipient == address(0)) {
            revert ZeroAddress();
        }
        if (hasClaimed[recipient]) {
            revert AlreadyClaimed(recipient);
        }
        if (totalClaims >= maxClaims) {
            revert MaxClaimsReached(totalClaims, maxClaims);
        }

        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 balance = usdc.balanceOf(address(this));
        if (balance < claimAmount) {
            revert InsufficientDispenserBalance(balance, claimAmount);
        }

        hasClaimed[recipient] = true;
        totalClaims++;

        usdc.safeTransfer(recipient, claimAmount);

        emit Claimed(recipient, claimAmount, totalClaims, block.chainid);
    }

    function batchClaimUSDC(address[] calldata recipients)
        external
        nonReentrant
        whenNotPaused
        returns (uint256 successCount)
    {
        if (!authorizedCallers[msg.sender]) {
            revert UnauthorizedCaller(msg.sender);
        }

        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 balance = usdc.balanceOf(address(this));
        uint256 availableClaims = balance / claimAmount;
        uint256 remainingClaims = maxClaims - totalClaims;
        uint256 maxPossible = availableClaims < remainingClaims ? availableClaims : remainingClaims;

        for (uint256 i = 0; i < recipients.length && successCount < maxPossible; i++) {
            address recipient = recipients[i];
            if (recipient != address(0) && !hasClaimed[recipient]) {
                hasClaimed[recipient] = true;
                usdc.safeTransfer(recipient, claimAmount);
                successCount++;
                emit Claimed(recipient, claimAmount, totalClaims + successCount, block.chainid);
            }
        }

        totalClaims += successCount;
    }

    function fund(uint256 amount) external {
        IERC20 usdc = IERC20(USDC_ADDRESS);
        usdc.safeTransferFrom(msg.sender, address(this), amount);
        emit Funded(msg.sender, amount, usdc.balanceOf(address(this)));
    }

    function addAuthorizedCaller(address caller) external onlyOwner {
        if (caller == address(0)) {
            revert ZeroAddress();
        }
        authorizedCallers[caller] = true;
        emit AuthorizedCallerAdded(caller);
    }

    function removeAuthorizedCaller(address caller) external onlyOwner {
        authorizedCallers[caller] = false;
        emit AuthorizedCallerRemoved(caller);
    }

    function setClaimAmount(uint256 newAmount) external onlyOwner {
        if (newAmount == 0) {
            revert InvalidAmount();
        }
        emit ClaimAmountUpdated(claimAmount, newAmount);
        claimAmount = newAmount;
    }

    function setMaxClaims(uint256 newMax) external onlyOwner {
        if (newMax == 0) {
            revert InvalidAmount();
        }
        emit MaxClaimsUpdated(maxClaims, newMax);
        maxClaims = newMax;
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function emergencyWithdraw(address to) external onlyOwner {
        if (to == address(0)) {
            revert ZeroAddress();
        }
        IERC20 usdc = IERC20(USDC_ADDRESS);
        uint256 balance = usdc.balanceOf(address(this));
        usdc.safeTransfer(to, balance);
        emit EmergencyWithdraw(to, balance);
    }

    function hasAddressClaimed(address addr) external view returns (bool) {
        return hasClaimed[addr];
    }

    function getUSDCAddress() external view returns (address) {
        return USDC_ADDRESS;
    }

    function getDispenserStatus() external view returns (
        uint256 balance,
        uint256 remainingClaims,
        bool isPaused,
        uint256 _claimAmount,
        uint256 _maxClaims,
        uint256 _totalClaims,
        address usdcAddress
    ) {
        IERC20 usdc = IERC20(USDC_ADDRESS);
        balance = usdc.balanceOf(address(this));
        remainingClaims = maxClaims > totalClaims ? maxClaims - totalClaims : 0;
        isPaused = paused();
        _claimAmount = claimAmount;
        _maxClaims = maxClaims;
        _totalClaims = totalClaims;
        usdcAddress = USDC_ADDRESS;
    }
}