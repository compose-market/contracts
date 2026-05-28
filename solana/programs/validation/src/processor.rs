use borsh::BorshDeserialize;
use manowar::{
    account::{create_pda, read, write},
    metadata::{validate_label, validate_uri, MAX_TAG_LEN},
    seed::{assert_pda, u64_seed, AGENT, REGISTRY, REQUEST, RESPONSE},
    ManowarError,
};
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    clock::Clock,
    entrypoint::ProgramResult,
    program_error::ProgramError,
    pubkey::Pubkey,
    sysvar::Sysvar,
};

use crate::{
    instruction::ValidationInstruction,
    state::{Registry, Request, Response, REGISTRY_SPACE, REQUEST_SPACE, RESPONSE_SPACE},
};

const VERSION: u8 = 1;

pub fn process(program_id: &Pubkey, accounts: &[AccountInfo], data: &[u8]) -> ProgramResult {
    let instruction = ValidationInstruction::try_from_slice(data)
        .map_err(|_| ProgramError::InvalidInstructionData)?;
    match instruction {
        ValidationInstruction::Initialize => initialize(program_id, accounts),
        ValidationInstruction::Request {
            agent_id,
            validator_type,
            task_hash,
            request_uri,
        } => request(
            program_id,
            accounts,
            agent_id,
            validator_type,
            task_hash,
            request_uri,
        ),
        ValidationInstruction::Respond {
            request_id,
            valid,
            evidence_hash,
            evidence_uri,
        } => respond(
            program_id,
            accounts,
            request_id,
            valid,
            evidence_hash,
            evidence_uri,
        ),
        ValidationInstruction::Close { request_id } => close(program_id, accounts, request_id),
    }
}

fn initialize(program_id: &Pubkey, accounts: &[AccountInfo]) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let admin = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(admin)?;
    create_pda(
        admin,
        registry_account,
        system,
        program_id,
        &[REGISTRY],
        REGISTRY_SPACE,
    )?;
    write(
        registry_account,
        &Registry {
            version: VERSION,
            admin: *admin.key,
            next_request_id: 1,
            total_requests: 0,
        },
    )
}

fn request(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    agent_id: u64,
    validator_type: String,
    task_hash: [u8; 32],
    request_uri: String,
) -> ProgramResult {
    validate_label(&validator_type, MAX_TAG_LEN)?;
    validate_uri(&request_uri)?;

    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let request_account = next_account_info(accounts)?;
    let identity_program = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let requester = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(requester)?;

    let agent_seed = u64_seed(agent_id);
    assert_pda(
        agent_account.key,
        identity_program.key,
        &[AGENT, &agent_seed],
    )?;
    if agent_account.owner != identity_program.key {
        return Err(ManowarError::InvalidAccountOwner.into());
    }

    let mut registry: Registry = read(registry_account, program_id)?;
    let request_id = registry.next_request_id;
    let request_seed = u64_seed(request_id);
    create_pda(
        requester,
        request_account,
        system,
        program_id,
        &[REQUEST, &request_seed],
        REQUEST_SPACE,
    )?;
    write(
        request_account,
        &Request {
            version: VERSION,
            request_id,
            agent_id,
            requester: *requester.key,
            validator_type,
            task_hash,
            request_uri,
            timestamp: Clock::get()?.unix_timestamp,
            closed: false,
            response_count: 0,
        },
    )?;

    registry.next_request_id = registry
        .next_request_id
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    registry.total_requests = registry
        .total_requests
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    write(registry_account, &registry)
}

fn respond(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    request_id: u64,
    valid: bool,
    evidence_hash: [u8; 32],
    evidence_uri: String,
) -> ProgramResult {
    validate_uri(&evidence_uri)?;
    let accounts = &mut accounts.iter();
    let request_account = next_account_info(accounts)?;
    let response_account = next_account_info(accounts)?;
    let validator = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(validator)?;
    let request_seed = u64_seed(request_id);
    assert_pda(request_account.key, program_id, &[REQUEST, &request_seed])?;

    let mut request: Request = read(request_account, program_id)?;
    if request.closed {
        return Err(ManowarError::Unauthorized.into());
    }
    request.response_count = request
        .response_count
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    let response_seed = u64_seed(request.response_count);
    create_pda(
        validator,
        response_account,
        system,
        program_id,
        &[RESPONSE, &request_seed, &response_seed],
        RESPONSE_SPACE,
    )?;
    write(
        response_account,
        &Response {
            version: VERSION,
            response_id: request.response_count,
            request_id,
            validator: *validator.key,
            valid,
            evidence_hash,
            evidence_uri,
            timestamp: Clock::get()?.unix_timestamp,
        },
    )?;
    write(request_account, &request)
}

fn close(program_id: &Pubkey, accounts: &[AccountInfo], request_id: u64) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let request_account = next_account_info(accounts)?;
    let requester = next_account_info(accounts)?;
    require_signer(requester)?;
    let request_seed = u64_seed(request_id);
    assert_pda(request_account.key, program_id, &[REQUEST, &request_seed])?;
    let mut request: Request = read(request_account, program_id)?;
    if request.requester != *requester.key {
        return Err(ManowarError::Unauthorized.into());
    }
    request.closed = true;
    write(request_account, &request)
}

fn require_signer(account: &AccountInfo) -> ProgramResult {
    if !account.is_signer {
        return Err(ManowarError::Unauthorized.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn request_space_allows_uri_evidence() {
        let request = Request {
            version: VERSION,
            request_id: 1,
            agent_id: 2,
            requester: Pubkey::new_unique(),
            validator_type: "replay".to_string(),
            task_hash: [3; 32],
            request_uri: "ipfs://request".to_string(),
            timestamp: 0,
            closed: false,
            response_count: 0,
        };
        let response = Response {
            version: VERSION,
            response_id: 1,
            request_id: 1,
            validator: Pubkey::new_unique(),
            valid: true,
            evidence_hash: [4; 32],
            evidence_uri: "ipfs://evidence".to_string(),
            timestamp: 0,
        };
        assert!(borsh::to_vec(&request).unwrap().len() + 4 <= REQUEST_SPACE);
        assert!(borsh::to_vec(&response).unwrap().len() + 4 <= RESPONSE_SPACE);
    }
}
