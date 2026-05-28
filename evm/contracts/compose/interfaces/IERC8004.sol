// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IERC8004Identity {
    struct MetadataEntry {
        string key;
        bytes value;
    }

    event AgentRegistered(uint256 indexed agentId, address indexed owner, string agentURI);
    event AgentURIUpdated(uint256 indexed agentId, string agentURI);
    event AgentMetadataSet(uint256 indexed agentId, string key, bytes value);
    event AgentMetadataRemoved(uint256 indexed agentId, string key);
    event AgentWalletUpdated(uint256 indexed agentId, address indexed previousWallet, address indexed newWallet);

    function register(string calldata agentURI) external returns (uint256 agentId);
    function register(string calldata agentURI, MetadataEntry[] calldata metadata) external returns (uint256 agentId);
    function agentURI(uint256 agentId) external view returns (string memory uri);
    function setAgentURI(uint256 agentId, string calldata newURI) external;
    function getMetadata(uint256 agentId, string calldata key) external view returns (bytes memory value);
    function setMetadata(uint256 agentId, string calldata key, bytes calldata value) external;
    function removeMetadata(uint256 agentId, string calldata key) external;
    function getAgentWallet(uint256 agentId) external view returns (address wallet);
    function setAgentWallet(uint256 agentId, address wallet, bytes calldata walletSignature) external;
    function agentExists(uint256 agentId) external view returns (bool exists);
    function getAgentCreator(uint256 agentId) external view returns (address creator);
    function isAuthorizedOrOwner(address spender, uint256 agentId) external view returns (bool authorized);
}

interface IERC8004Reputation {
    struct Feedback {
        int128 value;
        uint8 valueDecimals;
        bool isRevoked;
        string tag1;
        string tag2;
    }

    event NewFeedback(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        int128 value,
        uint8 valueDecimals,
        string indexed indexedTag1,
        string tag1,
        string tag2,
        string endpoint,
        string feedbackURI,
        bytes32 feedbackHash
    );
    event FeedbackRevoked(uint256 indexed agentId, address indexed clientAddress, uint64 indexed feedbackIndex);
    event ResponseAppended(
        uint256 indexed agentId,
        address indexed clientAddress,
        uint64 feedbackIndex,
        address indexed responder,
        string responseURI,
        bytes32 responseHash
    );

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external;

    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external;
    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external;
    function getIdentityRegistry() external view returns (address identityRegistry);
    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64 feedbackIndex);
    function readFeedback(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex
    ) external view returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked);
    function readAllFeedback(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2,
        bool includeRevoked
    )
        external
        view
        returns (
            address[] memory clients,
            uint64[] memory feedbackIndexes,
            int128[] memory values,
            uint8[] memory valueDecimals,
            string[] memory tag1s,
            string[] memory tag2s,
            bool[] memory revokedStatuses
        );
    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2
    ) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals);
    function getResponseCount(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        address[] calldata responders
    ) external view returns (uint64 count);
    function getClients(uint256 agentId) external view returns (address[] memory clients);
}

interface IERC8004Validation {
    struct ValidationRequest {
        uint256 agentId;
        address requester;
        string validatorType;
        bytes32 taskHash;
        string requestURI;
        uint64 timestamp;
        bool closed;
    }

    struct ValidationResponse {
        uint256 requestId;
        address validator;
        bool valid;
        bytes32 evidenceHash;
        string evidenceURI;
        uint64 timestamp;
    }

    event ValidationRequested(
        uint256 indexed requestId,
        uint256 indexed agentId,
        address indexed requester,
        string validatorType,
        bytes32 taskHash,
        string requestURI
    );
    event ValidationResponded(
        uint256 indexed responseId,
        uint256 indexed requestId,
        address indexed validator,
        bool valid,
        bytes32 evidenceHash,
        string evidenceURI
    );

    function requestValidation(
        uint256 agentId,
        string calldata validatorType,
        bytes32 taskHash,
        string calldata requestURI
    ) external returns (uint256 requestId);

    function respondValidation(
        uint256 requestId,
        bool valid,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external returns (uint256 responseId);

    function getValidationRequest(uint256 requestId) external view returns (ValidationRequest memory request);
    function getValidationResponse(uint256 responseId) external view returns (ValidationResponse memory response);
    function getAgentValidationRequests(uint256 agentId) external view returns (uint256[] memory requestIds);
    function getValidationResponses(uint256 requestId) external view returns (uint256[] memory responseIds);
}
