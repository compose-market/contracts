// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IAgentFactory} from "./interfaces/Iagentfactory.sol";
import {IERC8004Identity} from "./interfaces/IERC8004.sol";

/**
 * @title AgentFactory
 * @notice ERC8004-Manowar identity registry with native Manowar licensing extensions.
 */
contract AgentFactory is IAgentFactory {
    bytes4 private constant ERC1271_MAGICVALUE = 0x1626ba7e;
    bytes32 private constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant SET_AGENT_WALLET_TYPEHASH =
        keccak256("SetAgentWallet(uint256 agentId,address wallet,uint256 nonce)");
    bytes32 public constant AGENT_WALLET_KEY = keccak256("agentWallet");
    bytes32 public constant X402_KEY = keccak256("x402");

    uint256 private _totalAgents;
    uint256 private _nextAgentId;
    address private _admin;

    mapping(uint256 => AgentData) private _agents;
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    mapping(uint256 => address) private _tokenApprovals;
    mapping(address => mapping(address => bool)) private _operatorApprovals;
    mapping(bytes32 => uint256) private _dnaHashToAgentId;

    mapping(address => bool) private _authorizedConsumers;
    mapping(uint256 => mapping(address => mapping(uint256 => bool))) private _licensedTo;
    mapping(uint256 => LicenseRecord[]) private _licenseRecords;

    mapping(uint256 => mapping(bytes32 => bytes)) private _metadata;
    mapping(uint256 => address) private _agentWallets;
    mapping(uint256 => uint256) private _agentWalletNonces;

    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    modifier onlyAdmin() {
        if (msg.sender != _admin) revert NotAgentCreator(0, msg.sender);
        _;
    }

    modifier onlyExistingAgent(uint256 agentId) {
        if (_owners[agentId] == address(0)) revert AgentNotFound(agentId);
        _;
    }

    modifier onlyAgentCreator(uint256 agentId) {
        if (_agents[agentId].creator != msg.sender) revert NotAgentCreator(agentId, msg.sender);
        _;
    }

    modifier onlyAuthorizedForAgent(uint256 agentId) {
        if (!_isApprovedOrOwner(msg.sender, agentId)) revert NotAgentCreator(agentId, msg.sender);
        _;
    }

    modifier onlyAuthorizedConsumer() {
        require(_authorizedConsumers[msg.sender] || msg.sender == _admin, "Not authorized");
        _;
    }

    constructor(address adminAddress) {
        require(adminAddress != address(0), "Zero admin");
        _admin = adminAddress;
        _nextAgentId = 1;
    }

    function mintAgent(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        bool cloneable,
        string calldata agentCardUri
    ) external returns (uint256 agentId) {
        agentId = _mintManowarAgent(dnaHash, licenses, licensePrice, msg.sender, cloneable, false, 0, agentCardUri);
        emit AgentMinted(agentId, msg.sender, dnaHash, licenses, licensePrice, cloneable);
    }

    function register(string calldata agentURI_) external returns (uint256 agentId) {
        IERC8004Identity.MetadataEntry[] memory emptyMetadata;
        agentId = _register(msg.sender, agentURI_, emptyMetadata);
    }

    function register(
        string calldata agentURI_,
        IERC8004Identity.MetadataEntry[] calldata metadata
    ) external returns (uint256 agentId) {
        agentId = _register(msg.sender, agentURI_, metadata);
    }

    function agentURI(uint256 agentId) external view onlyExistingAgent(agentId) returns (string memory uri) {
        return _agents[agentId].agentCardUri;
    }

    function setAgentURI(
        uint256 agentId,
        string calldata newURI
    ) external onlyExistingAgent(agentId) onlyAuthorizedForAgent(agentId) {
        _agents[agentId].agentCardUri = newURI;
        emit AgentURIUpdated(agentId, newURI);
    }

    function getMetadata(uint256 agentId, string calldata key) external view onlyExistingAgent(agentId) returns (bytes memory value) {
        return _metadata[agentId][_metadataKey(key)];
    }

    function setMetadata(
        uint256 agentId,
        string calldata key,
        bytes calldata value
    ) external onlyExistingAgent(agentId) onlyAuthorizedForAgent(agentId) {
        _setMetadata(agentId, key, value);
    }

    function removeMetadata(
        uint256 agentId,
        string calldata key
    ) external onlyExistingAgent(agentId) onlyAuthorizedForAgent(agentId) {
        bytes32 keyHash = _metadataKey(key);
        if (keyHash == AGENT_WALLET_KEY) revert InvalidMetadataKey();
        delete _metadata[agentId][keyHash];
        emit AgentMetadataRemoved(agentId, key);
    }

    function getAgentWallet(uint256 agentId) external view onlyExistingAgent(agentId) returns (address wallet) {
        return _agentWallets[agentId];
    }

    function agentWalletNonce(uint256 agentId) external view onlyExistingAgent(agentId) returns (uint256 nonce) {
        return _agentWalletNonces[agentId];
    }

    function agentWalletMessageHash(uint256 agentId, address wallet) public view onlyExistingAgent(agentId) returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                SET_AGENT_WALLET_TYPEHASH,
                agentId,
                wallet,
                _agentWalletNonces[agentId]
            )
        );
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    function setAgentWallet(
        uint256 agentId,
        address wallet,
        bytes calldata walletSignature
    ) external onlyExistingAgent(agentId) onlyAuthorizedForAgent(agentId) {
        address previousWallet = _agentWallets[agentId];

        if (wallet == address(0)) {
            _setAgentWallet(agentId, previousWallet, address(0));
            return;
        }

        bytes32 digest = agentWalletMessageHash(agentId, wallet);
        if (msg.sender != wallet && !_isValidWalletSignature(wallet, digest, walletSignature)) {
            revert InvalidAgentWalletSignature();
        }

        _agentWalletNonces[agentId]++;
        _setAgentWallet(agentId, previousWallet, wallet);
    }

    function getAgentData(uint256 agentId) external view onlyExistingAgent(agentId) returns (AgentData memory data) {
        return _agents[agentId];
    }

    function getDnaHash(uint256 agentId) external view onlyExistingAgent(agentId) returns (bytes32 dnaHash) {
        return _agents[agentId].dnaHash;
    }

    function hasAvailableLicenses(uint256 agentId) external view onlyExistingAgent(agentId) returns (bool available) {
        AgentData storage agent = _agents[agentId];
        return agent.licenses == 0 || agent.licensesMinted < agent.licenses;
    }

    function consumeLicense(
        uint256 agentId,
        address workflowContract,
        uint256 workflowId
    ) external onlyAuthorizedConsumer onlyExistingAgent(agentId) returns (uint256 licenseNumber) {
        AgentData storage agent = _agents[agentId];
        if (agent.licenses != 0 && agent.licensesMinted >= agent.licenses) revert NoLicensesAvailable(agentId);
        if (_licensedTo[agentId][workflowContract][workflowId]) {
            revert AlreadyLicensed(agentId, workflowContract, workflowId);
        }

        licenseNumber = ++agent.licensesMinted;
        _licensedTo[agentId][workflowContract][workflowId] = true;
        _licenseRecords[agentId].push(
            LicenseRecord({workflowContract: workflowContract, workflowId: workflowId, licensedAt: block.timestamp})
        );

        emit AgentLicensed(agentId, workflowContract, workflowId, licenseNumber);
    }

    function revokeLicense(
        uint256 agentId,
        address workflowContract,
        uint256 workflowId
    ) external onlyAuthorizedConsumer onlyExistingAgent(agentId) {
        if (!_licensedTo[agentId][workflowContract][workflowId]) {
            revert NotLicensed(agentId, workflowContract, workflowId);
        }

        _licensedTo[agentId][workflowContract][workflowId] = false;
        emit AgentLicenseRevoked(agentId, workflowContract, workflowId);
    }

    function isLicensedTo(
        uint256 agentId,
        address workflowContract,
        uint256 workflowId
    ) external view returns (bool licensed) {
        return _licensedTo[agentId][workflowContract][workflowId];
    }

    function getLicenseRecords(uint256 agentId) external view returns (LicenseRecord[] memory records) {
        return _licenseRecords[agentId];
    }

    function updatePrice(
        uint256 agentId,
        uint256 newPrice
    ) external onlyAgentCreator(agentId) onlyExistingAgent(agentId) {
        uint256 oldPrice = _agents[agentId].licensePrice;
        _agents[agentId].licensePrice = newPrice;
        emit AgentPriceUpdated(agentId, oldPrice, newPrice);
    }

    function isAgentClone(uint256 agentId) external view onlyExistingAgent(agentId) returns (bool) {
        return _agents[agentId].isClone;
    }

    function getParentAgent(uint256 agentId) external view onlyExistingAgent(agentId) returns (uint256 parentId) {
        return _agents[agentId].parentAgentId;
    }

    function totalAgents() external view returns (uint256 total) {
        return _totalAgents;
    }

    function agentExists(uint256 agentId) external view returns (bool exists) {
        return _owners[agentId] != address(0);
    }

    function getAgentCreator(uint256 agentId) external view onlyExistingAgent(agentId) returns (address creator) {
        return _agents[agentId].creator;
    }

    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool authorized) {
        return _owners[agentId] != address(0) && _isApprovedOrOwner(spender, agentId);
    }

    function mintClone(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        uint256 parentAgentId,
        address cloner,
        string calldata agentCardUri
    ) external onlyAuthorizedConsumer returns (uint256 agentId) {
        agentId = _mintManowarAgent(dnaHash, licenses, licensePrice, cloner, false, true, parentAgentId, agentCardUri);
        emit AgentMinted(agentId, cloner, dnaHash, licenses, licensePrice, false);
    }

    function mintWarped(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        address warper,
        string calldata agentCardUri
    ) external onlyAuthorizedConsumer returns (uint256 agentId) {
        agentId = _mintManowarAgent(dnaHash, licenses, licensePrice, warper, false, false, 0, agentCardUri);
        emit AgentMinted(agentId, warper, dnaHash, licenses, licensePrice, false);
    }

    function authorizeConsumer(address consumer) external onlyAdmin {
        _authorizedConsumers[consumer] = true;
    }

    function revokeConsumer(address consumer) external onlyAdmin {
        _authorizedConsumers[consumer] = false;
    }

    function isAuthorizedConsumer(address consumer) external view returns (bool) {
        return _authorizedConsumers[consumer];
    }

    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "Zero address");
        _admin = newAdmin;
    }

    function getAdmin() external view returns (address) {
        return _admin;
    }

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
        require(msg.sender == owner || _operatorApprovals[owner][msg.sender], "Not owner or approved");
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
            interfaceId == 0x01ffc9a7 ||
            interfaceId == 0x80ac58cd ||
            interfaceId == 0x5b5e139f ||
            interfaceId == type(IERC8004Identity).interfaceId ||
            interfaceId == type(IAgentFactory).interfaceId;
    }

    function _register(
        address owner,
        string calldata agentURI_,
        IERC8004Identity.MetadataEntry[] memory metadata
    ) internal returns (uint256 agentId) {
        bytes32 dnaHash = keccak256(abi.encodePacked("ERC8004_MANOWAR", owner, agentURI_, block.chainid, _nextAgentId));
        agentId = _mintManowarAgent(dnaHash, 0, 0, owner, false, false, 0, agentURI_);
        for (uint256 i = 0; i < metadata.length; i++) {
            _setMetadata(agentId, metadata[i].key, metadata[i].value);
        }
    }

    function _mintManowarAgent(
        bytes32 dnaHash,
        uint256 licenses,
        uint256 licensePrice,
        address owner,
        bool cloneable,
        bool isClone,
        uint256 parentAgentId,
        string calldata agentCardUri
    ) internal returns (uint256 agentId) {
        if (dnaHash == bytes32(0)) revert InvalidDnaHash();
        if (_dnaHashToAgentId[dnaHash] != 0) revert InvalidDnaHash();

        agentId = _nextAgentId++;
        _totalAgents++;
        _agents[agentId] = AgentData({
            dnaHash: dnaHash,
            licenses: licenses,
            licensesMinted: 0,
            licensePrice: licensePrice,
            creator: owner,
            cloneable: cloneable,
            isClone: isClone,
            parentAgentId: parentAgentId,
            agentCardUri: agentCardUri
        });

        _mint(owner, agentId);
        _dnaHashToAgentId[dnaHash] = agentId;
        _metadata[agentId][X402_KEY] = abi.encode(true);
        _setAgentWallet(agentId, address(0), owner);

        emit AgentRegistered(agentId, owner, agentCardUri);
        emit AgentDnaRegistered(agentId, dnaHash);
        emit AgentMetadataSet(agentId, "x402", abi.encode(true));
    }

    function _setMetadata(uint256 agentId, string memory key, bytes memory value) internal {
        bytes32 keyHash = _metadataKey(key);
        if (keyHash == AGENT_WALLET_KEY) revert InvalidMetadataKey();
        _metadata[agentId][keyHash] = value;
        emit AgentMetadataSet(agentId, key, value);
    }

    function _setAgentWallet(uint256 agentId, address previousWallet, address wallet) internal {
        _agentWallets[agentId] = wallet;
        if (wallet == address(0)) {
            delete _metadata[agentId][AGENT_WALLET_KEY];
            emit AgentMetadataRemoved(agentId, "agentWallet");
        } else {
            bytes memory encodedWallet = abi.encode(wallet);
            _metadata[agentId][AGENT_WALLET_KEY] = encodedWallet;
            emit AgentMetadataSet(agentId, "agentWallet", encodedWallet);
        }
        emit AgentWalletUpdated(agentId, previousWallet, wallet);
    }

    function _metadataKey(string memory key) internal pure returns (bytes32) {
        if (bytes(key).length == 0) revert InvalidMetadataKey();
        return keccak256(bytes(key));
    }

    function _isValidWalletSignature(address wallet, bytes32 digest, bytes calldata signature) internal view returns (bool) {
        if (wallet.code.length > 0) {
            try IERC1271(wallet).isValidSignature(digest, signature) returns (bytes4 magicValue) {
                return magicValue == ERC1271_MAGICVALUE;
            } catch {
                return false;
            }
        }
        return signature.length == 65 && ECDSA.recoverCalldata(digest, signature) == wallet;
    }

    function _domainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256(bytes("ERC8004-Manowar Identity")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

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

        delete _tokenApprovals[tokenId];
        address previousWallet = _agentWallets[tokenId];
        if (previousWallet != address(0)) {
            _setAgentWallet(tokenId, previousWallet, address(0));
        }

        _balances[from]--;
        _balances[to]++;
        _owners[tokenId] = to;
        emit Transfer(from, to, tokenId);
    }

    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view returns (bool) {
        address owner = _owners[tokenId];
        return spender == owner || _tokenApprovals[tokenId] == spender || _operatorApprovals[owner][spender];
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

interface IERC721Receiver {
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}
