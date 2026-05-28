use borsh::BorshDeserialize;
use manowar::{
    account::{create_pda, has_state, read, write},
    fixed::validate_fixed,
    is_zero_pubkey,
    metadata::{validate_label, validate_uri, MAX_ENDPOINT_LEN, MAX_TAG_LEN},
    seed::{assert_pda, u64_seed, AGENT, FEEDBACK, FEEDBACK_INDEX, RESPONSE},
    Agent, ManowarError,
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
    instruction::ReputationInstruction,
    state::{Feedback, FeedbackIndex, Response, FEEDBACK_SPACE, INDEX_SPACE, RESPONSE_SPACE},
};

const VERSION: u8 = 1;

pub fn process(program_id: &Pubkey, accounts: &[AccountInfo], data: &[u8]) -> ProgramResult {
    let instruction = ReputationInstruction::try_from_slice(data)
        .map_err(|_| ProgramError::InvalidInstructionData)?;
    match instruction {
        ReputationInstruction::GiveFeedback {
            agent_id,
            value,
            value_decimals,
            tag1,
            tag2,
            endpoint,
            feedback_uri,
            feedback_hash,
        } => give_feedback(
            program_id,
            accounts,
            agent_id,
            value,
            value_decimals,
            tag1,
            tag2,
            endpoint,
            feedback_uri,
            feedback_hash,
        ),
        ReputationInstruction::RevokeFeedback {
            agent_id,
            feedback_index,
        } => revoke_feedback(program_id, accounts, agent_id, feedback_index),
        ReputationInstruction::AppendResponse {
            agent_id,
            feedback_index,
            response_index,
            response_uri,
            response_hash,
        } => append_response(
            program_id,
            accounts,
            agent_id,
            feedback_index,
            response_index,
            response_uri,
            response_hash,
        ),
    }
}

#[allow(clippy::too_many_arguments)]
fn give_feedback(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    agent_id: u64,
    value: i128,
    value_decimals: u8,
    tag1: String,
    tag2: String,
    endpoint: String,
    feedback_uri: String,
    feedback_hash: [u8; 32],
) -> ProgramResult {
    validate_fixed(value, value_decimals)?;
    validate_label(&tag1, MAX_TAG_LEN)?;
    validate_label(&tag2, MAX_TAG_LEN)?;
    validate_label(&endpoint, MAX_ENDPOINT_LEN)?;
    validate_uri(&feedback_uri)?;

    let accounts = &mut accounts.iter();
    let identity_program = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let index_account = next_account_info(accounts)?;
    let feedback_account = next_account_info(accounts)?;
    let client = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(client)?;
    assert_agent(agent_account, identity_program.key, agent_id)?;

    let agent: Agent = read(agent_account, identity_program.key)?;
    if agent.owner == *client.key
        || (!is_zero_pubkey(&agent.agent_wallet) && agent.agent_wallet == *client.key)
    {
        return Err(ManowarError::SelfFeedback.into());
    }

    let mut index = if has_state(index_account) {
        let index: FeedbackIndex = read(index_account, program_id)?;
        if index.agent_id != agent_id || index.client != *client.key {
            return Err(ManowarError::InvalidIndex.into());
        }
        index
    } else {
        let agent_seed = u64_seed(agent_id);
        create_pda(
            client,
            index_account,
            system,
            program_id,
            &[FEEDBACK_INDEX, &agent_seed, client.key.as_ref()],
            INDEX_SPACE,
        )?;
        FeedbackIndex {
            version: VERSION,
            agent_id,
            client: *client.key,
            last_index: 0,
        }
    };

    index.last_index = index
        .last_index
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    let agent_seed = u64_seed(agent_id);
    let index_seed = u64_seed(index.last_index);
    create_pda(
        client,
        feedback_account,
        system,
        program_id,
        &[FEEDBACK, &agent_seed, client.key.as_ref(), &index_seed],
        FEEDBACK_SPACE,
    )?;

    let now = Clock::get()?.unix_timestamp;
    write(index_account, &index)?;
    write(
        feedback_account,
        &Feedback {
            version: VERSION,
            agent_id,
            client: *client.key,
            feedback_index: index.last_index,
            value,
            value_decimals,
            is_revoked: false,
            tag1,
            tag2,
            endpoint,
            feedback_uri,
            feedback_hash,
            created_at: now,
        },
    )
}

fn revoke_feedback(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    agent_id: u64,
    feedback_index: u64,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let feedback_account = next_account_info(accounts)?;
    let client = next_account_info(accounts)?;
    require_signer(client)?;

    let agent_seed = u64_seed(agent_id);
    let index_seed = u64_seed(feedback_index);
    assert_pda(
        feedback_account.key,
        program_id,
        &[FEEDBACK, &agent_seed, client.key.as_ref(), &index_seed],
    )?;

    let mut feedback: Feedback = read(feedback_account, program_id)?;
    if feedback.client != *client.key
        || feedback.agent_id != agent_id
        || feedback.feedback_index != feedback_index
    {
        return Err(ManowarError::InvalidIndex.into());
    }
    if feedback.is_revoked {
        return Err(ManowarError::AlreadyRevoked.into());
    }
    feedback.is_revoked = true;
    write(feedback_account, &feedback)
}

fn append_response(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    agent_id: u64,
    feedback_index: u64,
    response_index: u64,
    response_uri: String,
    response_hash: [u8; 32],
) -> ProgramResult {
    if response_index == 0 {
        return Err(ManowarError::InvalidIndex.into());
    }
    if response_uri.is_empty() {
        return Err(ManowarError::EmptyUri.into());
    }
    validate_uri(&response_uri)?;

    let accounts = &mut accounts.iter();
    let feedback_account = next_account_info(accounts)?;
    let response_account = next_account_info(accounts)?;
    let responder = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(responder)?;

    let feedback: Feedback = read(feedback_account, program_id)?;
    if feedback.agent_id != agent_id || feedback.feedback_index != feedback_index {
        return Err(ManowarError::InvalidIndex.into());
    }

    let agent_seed = u64_seed(agent_id);
    let feedback_seed = u64_seed(feedback_index);
    let response_seed = u64_seed(response_index);
    create_pda(
        responder,
        response_account,
        system,
        program_id,
        &[
            RESPONSE,
            &agent_seed,
            feedback.client.as_ref(),
            &feedback_seed,
            responder.key.as_ref(),
            &response_seed,
        ],
        RESPONSE_SPACE,
    )?;
    write(
        response_account,
        &Response {
            version: VERSION,
            agent_id,
            client: feedback.client,
            feedback_index,
            responder: *responder.key,
            response_index,
            response_uri,
            response_hash,
            created_at: Clock::get()?.unix_timestamp,
        },
    )
}

fn assert_agent(
    agent_account: &AccountInfo,
    identity_program: &Pubkey,
    agent_id: u64,
) -> ProgramResult {
    let agent_seed = u64_seed(agent_id);
    assert_pda(agent_account.key, identity_program, &[AGENT, &agent_seed])?;
    Ok(())
}

fn require_signer(account: &AccountInfo) -> ProgramResult {
    if !account.is_signer {
        return Err(ManowarError::Unauthorized.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use manowar::{average, MAX_VALUE_DECIMALS};

    #[test]
    fn sdk_ratings_anchor_as_fixed_point_values() {
        let values = vec![(50, 1), (40, 1), (45, 1)];
        assert_eq!(average(&values, 1).unwrap(), 45);
        assert_eq!(MAX_VALUE_DECIMALS, 18);
    }
}
