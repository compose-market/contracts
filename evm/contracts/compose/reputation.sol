// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAgentFactory} from "./interfaces/Iagentfactory.sol";
import {IERC8004Reputation} from "./interfaces/IERC8004.sol";

/**
 * @title Reputation
 * @notice ERC8004 reputation registry for Manowar agents.
 * @dev Native API/SDK feedback should be anchored through feedbackURI +
 * feedbackHash; verbose feedback context stays off-chain.
 */
contract Reputation is IERC8004Reputation {
    int128 private constant MAX_ABS_VALUE = 1e38;

    IAgentFactory public immutable agentFactory;

    mapping(uint256 => mapping(address => mapping(uint64 => Feedback))) private _feedback;
    mapping(uint256 => mapping(address => uint64)) private _lastIndex;
    mapping(uint256 => address[]) private _clients;
    mapping(uint256 => mapping(address => bool)) private _clientExists;

    mapping(uint256 => mapping(address => mapping(uint64 => mapping(address => uint64)))) private _responseCount;
    mapping(uint256 => mapping(address => mapping(uint64 => address[]))) private _responders;
    mapping(uint256 => mapping(address => mapping(uint64 => mapping(address => bool)))) private _responderExists;

    error AgentNotFound(uint256 agentId);
    error SelfFeedbackNotAllowed(uint256 agentId, address clientAddress);
    error InvalidValueDecimals(uint8 valueDecimals);
    error ValueTooLarge(int128 value);
    error InvalidFeedbackIndex(uint64 feedbackIndex);
    error FeedbackAlreadyRevoked(uint256 agentId, address clientAddress, uint64 feedbackIndex);
    error EmptyResponseURI();
    error ClientAddressesRequired();

    constructor(address agentFactory_) {
        require(agentFactory_ != address(0), "Zero factory");
        agentFactory = IAgentFactory(agentFactory_);
    }

    function getIdentityRegistry() external view returns (address identityRegistry) {
        return address(agentFactory);
    }

    function giveFeedback(
        uint256 agentId,
        int128 value,
        uint8 valueDecimals,
        string calldata tag1,
        string calldata tag2,
        string calldata endpoint,
        string calldata feedbackURI,
        bytes32 feedbackHash
    ) external {
        if (!agentFactory.agentExists(agentId)) revert AgentNotFound(agentId);
        if (agentFactory.isAuthorizedOrOwner(msg.sender, agentId)) {
            revert SelfFeedbackNotAllowed(agentId, msg.sender);
        }
        if (valueDecimals > 18) revert InvalidValueDecimals(valueDecimals);
        if (value < -MAX_ABS_VALUE || value > MAX_ABS_VALUE) revert ValueTooLarge(value);

        uint64 feedbackIndex = ++_lastIndex[agentId][msg.sender];
        _feedback[agentId][msg.sender][feedbackIndex] = Feedback({
            value: value,
            valueDecimals: valueDecimals,
            isRevoked: false,
            tag1: tag1,
            tag2: tag2
        });

        if (!_clientExists[agentId][msg.sender]) {
            _clients[agentId].push(msg.sender);
            _clientExists[agentId][msg.sender] = true;
        }

        emit NewFeedback(
            agentId,
            msg.sender,
            feedbackIndex,
            value,
            valueDecimals,
            tag1,
            tag1,
            tag2,
            endpoint,
            feedbackURI,
            feedbackHash
        );
    }

    function revokeFeedback(uint256 agentId, uint64 feedbackIndex) external {
        if (feedbackIndex == 0 || feedbackIndex > _lastIndex[agentId][msg.sender]) {
            revert InvalidFeedbackIndex(feedbackIndex);
        }

        Feedback storage stored = _feedback[agentId][msg.sender][feedbackIndex];
        if (stored.isRevoked) {
            revert FeedbackAlreadyRevoked(agentId, msg.sender, feedbackIndex);
        }
        stored.isRevoked = true;

        emit FeedbackRevoked(agentId, msg.sender, feedbackIndex);
    }

    function appendResponse(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        string calldata responseURI,
        bytes32 responseHash
    ) external {
        if (feedbackIndex == 0 || feedbackIndex > _lastIndex[agentId][clientAddress]) {
            revert InvalidFeedbackIndex(feedbackIndex);
        }
        if (bytes(responseURI).length == 0) revert EmptyResponseURI();

        if (!_responderExists[agentId][clientAddress][feedbackIndex][msg.sender]) {
            _responders[agentId][clientAddress][feedbackIndex].push(msg.sender);
            _responderExists[agentId][clientAddress][feedbackIndex][msg.sender] = true;
        }
        _responseCount[agentId][clientAddress][feedbackIndex][msg.sender]++;

        emit ResponseAppended(agentId, clientAddress, feedbackIndex, msg.sender, responseURI, responseHash);
    }

    function getLastIndex(uint256 agentId, address clientAddress) external view returns (uint64 feedbackIndex) {
        return _lastIndex[agentId][clientAddress];
    }

    function readFeedback(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex
    ) external view returns (int128 value, uint8 valueDecimals, string memory tag1, string memory tag2, bool isRevoked) {
        if (feedbackIndex == 0 || feedbackIndex > _lastIndex[agentId][clientAddress]) {
            revert InvalidFeedbackIndex(feedbackIndex);
        }
        Feedback storage stored = _feedback[agentId][clientAddress][feedbackIndex];
        return (stored.value, stored.valueDecimals, stored.tag1, stored.tag2, stored.isRevoked);
    }

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
        )
    {
        address[] memory clientList = _resolveClientList(agentId, clientAddresses);
        uint256 totalCount = _matchingFeedbackCount(agentId, clientList, tag1, tag2, includeRevoked);

        clients = new address[](totalCount);
        feedbackIndexes = new uint64[](totalCount);
        values = new int128[](totalCount);
        valueDecimals = new uint8[](totalCount);
        tag1s = new string[](totalCount);
        tag2s = new string[](totalCount);
        revokedStatuses = new bool[](totalCount);

        uint256 index;
        for (uint256 i; i < clientList.length; i++) {
            address clientAddress = clientList[i];
            uint64 lastIndex = _lastIndex[agentId][clientAddress];
            for (uint64 j = 1; j <= lastIndex; j++) {
                Feedback storage stored = _feedback[agentId][clientAddress][j];
                if (!_matches(stored, tag1, tag2, includeRevoked)) continue;

                clients[index] = clientAddress;
                feedbackIndexes[index] = j;
                values[index] = stored.value;
                valueDecimals[index] = stored.valueDecimals;
                tag1s[index] = stored.tag1;
                tag2s[index] = stored.tag2;
                revokedStatuses[index] = stored.isRevoked;
                index++;
            }
        }
    }

    function getSummary(
        uint256 agentId,
        address[] calldata clientAddresses,
        string calldata tag1,
        string calldata tag2
    ) external view returns (uint64 count, int128 summaryValue, uint8 summaryValueDecimals) {
        if (clientAddresses.length == 0) revert ClientAddressesRequired();

        int256 sumWad;
        uint64[19] memory decimalCounts;

        for (uint256 i; i < clientAddresses.length; i++) {
            address clientAddress = clientAddresses[i];
            uint64 lastIndex = _lastIndex[agentId][clientAddress];
            for (uint64 j = 1; j <= lastIndex; j++) {
                Feedback storage stored = _feedback[agentId][clientAddress][j];
                if (!_matches(stored, tag1, tag2, false)) continue;

                int256 factor = int256(10 ** uint256(18 - stored.valueDecimals));
                sumWad += int256(stored.value) * factor;
                decimalCounts[stored.valueDecimals]++;
                count++;
            }
        }

        if (count == 0) return (0, 0, 0);

        uint8 modeDecimals;
        uint64 maxCount;
        for (uint8 decimals; decimals <= 18; decimals++) {
            if (decimalCounts[decimals] > maxCount) {
                maxCount = decimalCounts[decimals];
                modeDecimals = decimals;
            }
        }

        int256 averageWad = sumWad / int256(uint256(count));
        summaryValue = int128(averageWad / int256(10 ** uint256(18 - modeDecimals)));
        summaryValueDecimals = modeDecimals;
    }

    function getResponseCount(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        address[] calldata responders
    ) external view returns (uint64 count) {
        if (clientAddress == address(0)) {
            address[] memory clients = _clients[agentId];
            for (uint256 i; i < clients.length; i++) {
                uint64 lastIndex = _lastIndex[agentId][clients[i]];
                for (uint64 j = 1; j <= lastIndex; j++) {
                    count += _countResponses(agentId, clients[i], j, responders);
                }
            }
            return count;
        }

        if (feedbackIndex == 0) {
            uint64 lastIndex = _lastIndex[agentId][clientAddress];
            for (uint64 j = 1; j <= lastIndex; j++) {
                count += _countResponses(agentId, clientAddress, j, responders);
            }
            return count;
        }

        return _countResponses(agentId, clientAddress, feedbackIndex, responders);
    }

    function getClients(uint256 agentId) external view returns (address[] memory clients) {
        return _clients[agentId];
    }

    function _matchingFeedbackCount(
        uint256 agentId,
        address[] memory clientList,
        string calldata tag1,
        string calldata tag2,
        bool includeRevoked
    ) internal view returns (uint256 totalCount) {
        for (uint256 i; i < clientList.length; i++) {
            uint64 lastIndex = _lastIndex[agentId][clientList[i]];
            for (uint64 j = 1; j <= lastIndex; j++) {
                if (_matches(_feedback[agentId][clientList[i]][j], tag1, tag2, includeRevoked)) totalCount++;
            }
        }
    }

    function _resolveClientList(
        uint256 agentId,
        address[] calldata clientAddresses
    ) internal view returns (address[] memory clientList) {
        if (clientAddresses.length > 0) {
            clientList = new address[](clientAddresses.length);
            for (uint256 i; i < clientAddresses.length; i++) {
                clientList[i] = clientAddresses[i];
            }
            return clientList;
        }

        address[] storage storedClients = _clients[agentId];
        clientList = new address[](storedClients.length);
        for (uint256 i; i < storedClients.length; i++) {
            clientList[i] = storedClients[i];
        }
    }

    function _matches(
        Feedback storage stored,
        string calldata tag1,
        string calldata tag2,
        bool includeRevoked
    ) internal view returns (bool) {
        if (!includeRevoked && stored.isRevoked) return false;
        if (bytes(tag1).length != 0 && keccak256(bytes(tag1)) != keccak256(bytes(stored.tag1))) return false;
        if (bytes(tag2).length != 0 && keccak256(bytes(tag2)) != keccak256(bytes(stored.tag2))) return false;
        return true;
    }

    function _countResponses(
        uint256 agentId,
        address clientAddress,
        uint64 feedbackIndex,
        address[] calldata responders
    ) internal view returns (uint64 count) {
        if (responders.length == 0) {
            address[] memory allResponders = _responders[agentId][clientAddress][feedbackIndex];
            for (uint256 i; i < allResponders.length; i++) {
                count += _responseCount[agentId][clientAddress][feedbackIndex][allResponders[i]];
            }
            return count;
        }

        for (uint256 i; i < responders.length; i++) {
            count += _responseCount[agentId][clientAddress][feedbackIndex][responders[i]];
        }
    }
}
