// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IAgentFactory} from "./interfaces/Iagentfactory.sol";
import {IERC8004Validation} from "./interfaces/IERC8004.sol";

contract Validation is IERC8004Validation {
    IAgentFactory public immutable agentFactory;

    uint256 private _nextRequestId = 1;
    uint256 private _nextResponseId = 1;

    mapping(uint256 => ValidationRequest) private _requests;
    mapping(uint256 => ValidationResponse) private _responses;
    mapping(uint256 => uint256[]) private _agentRequests;
    mapping(uint256 => uint256[]) private _requestResponses;

    error AgentNotFound(uint256 agentId);
    error ValidationRequestNotFound(uint256 requestId);

    constructor(address agentFactory_) {
        require(agentFactory_ != address(0), "Zero factory");
        agentFactory = IAgentFactory(agentFactory_);
    }

    function requestValidation(
        uint256 agentId,
        string calldata validatorType,
        bytes32 taskHash,
        string calldata requestURI
    ) external returns (uint256 requestId) {
        if (!agentFactory.agentExists(agentId)) revert AgentNotFound(agentId);

        requestId = _nextRequestId++;
        _requests[requestId] = ValidationRequest({
            agentId: agentId,
            requester: msg.sender,
            validatorType: validatorType,
            taskHash: taskHash,
            requestURI: requestURI,
            timestamp: uint64(block.timestamp),
            closed: false
        });
        _agentRequests[agentId].push(requestId);

        emit ValidationRequested(requestId, agentId, msg.sender, validatorType, taskHash, requestURI);
    }

    function respondValidation(
        uint256 requestId,
        bool valid,
        bytes32 evidenceHash,
        string calldata evidenceURI
    ) external returns (uint256 responseId) {
        ValidationRequest storage request = _requests[requestId];
        if (request.timestamp == 0) revert ValidationRequestNotFound(requestId);

        responseId = _nextResponseId++;
        _responses[responseId] = ValidationResponse({
            requestId: requestId,
            validator: msg.sender,
            valid: valid,
            evidenceHash: evidenceHash,
            evidenceURI: evidenceURI,
            timestamp: uint64(block.timestamp)
        });
        _requestResponses[requestId].push(responseId);

        emit ValidationResponded(responseId, requestId, msg.sender, valid, evidenceHash, evidenceURI);
    }

    function getValidationRequest(uint256 requestId) external view returns (ValidationRequest memory request) {
        request = _requests[requestId];
        if (request.timestamp == 0) revert ValidationRequestNotFound(requestId);
    }

    function getValidationResponse(uint256 responseId) external view returns (ValidationResponse memory response) {
        response = _responses[responseId];
        if (response.timestamp == 0) revert ValidationRequestNotFound(responseId);
    }

    function getAgentValidationRequests(uint256 agentId) external view returns (uint256[] memory requestIds) {
        return _agentRequests[agentId];
    }

    function getValidationResponses(uint256 requestId) external view returns (uint256[] memory responseIds) {
        return _requestResponses[requestId];
    }
}
