use manowar::{
    account::{create_pda, read, write},
    metadata::{validate_label, MAX_TAG_LEN},
    seed::{assert_pda, u64_seed, RFA, SUBMISSION},
    transfer_tokens_signed, zero_pubkey, Agent, ManowarError,
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
    state::{
        Registry, Rfa, RfaStatus, Submission, Workflow, MAX_SKILLS, RFA_SPACE, SUBMISSION_SPACE,
        VERSION,
    },
    workflow::{assert_agent, assert_workflow, require_signer, require_workflow_owner},
};

pub fn create(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    workflow_id: u64,
    title: String,
    description: String,
    required_skills: Vec<[u8; 32]>,
    offer_amount: u64,
) -> ProgramResult {
    validate_rfa_inputs(&title, &description, required_skills.len(), offer_amount)?;

    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let rfa_account = next_account_info(accounts)?;
    let workflow_account = next_account_info(accounts)?;
    let publisher = next_account_info(accounts)?;
    let token_program = next_account_info(accounts)?;
    let publisher_token = next_account_info(accounts)?;
    let escrow_token = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(publisher)?;
    assert_workflow(workflow_account.key, program_id, workflow_id)?;

    let mut registry: Registry = read(registry_account, program_id)?;
    let mut workflow: Workflow = read(workflow_account, program_id)?;
    require_workflow_owner(&workflow, publisher)?;
    if workflow.has_active_rfa {
        return Err(ManowarError::RfaNotOpen.into());
    }

    let rfa_id = registry.next_rfa_id;
    let rfa_seed = u64_seed(rfa_id);
    create_pda(
        publisher,
        rfa_account,
        system,
        program_id,
        &[RFA, &rfa_seed],
        RFA_SPACE,
    )?;
    manowar::transfer_tokens(
        token_program,
        publisher_token,
        escrow_token,
        publisher,
        offer_amount,
    )?;

    write(
        rfa_account,
        &Rfa {
            version: VERSION,
            rfa_id,
            workflow_id,
            title,
            description,
            required_skills,
            offer_amount,
            publisher: *publisher.key,
            created_at: Clock::get()?.unix_timestamp,
            status: RfaStatus::Open,
            fulfilled_by_agent_id: 0,
            agent_creator: zero_pubkey(),
        },
    )?;

    workflow.has_active_rfa = true;
    workflow.rfa_id = rfa_id;
    registry.next_rfa_id = registry
        .next_rfa_id
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    registry.total_escrowed = registry
        .total_escrowed
        .checked_add(offer_amount)
        .ok_or(ProgramError::InvalidInstructionData)?;
    write(workflow_account, &workflow)?;
    write(registry_account, &registry)
}

pub fn submit(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    rfa_id: u64,
    agent_id: u64,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let rfa_account = next_account_info(accounts)?;
    let submission_account = next_account_info(accounts)?;
    let identity_program = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let creator = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(creator)?;
    assert_rfa(rfa_account.key, program_id, rfa_id)?;
    assert_agent(agent_account.key, identity_program.key, agent_id)?;

    let rfa: Rfa = read(rfa_account, program_id)?;
    if rfa.status != RfaStatus::Open {
        return Err(ManowarError::RfaNotOpen.into());
    }
    let agent: Agent = read(agent_account, identity_program.key)?;
    if agent.agent_id != agent_id || agent.creator != *creator.key {
        return Err(ManowarError::Unauthorized.into());
    }

    let rfa_seed = u64_seed(rfa_id);
    let agent_seed = u64_seed(agent_id);
    create_pda(
        creator,
        submission_account,
        system,
        program_id,
        &[SUBMISSION, &rfa_seed, &agent_seed],
        SUBMISSION_SPACE,
    )?;
    write(
        submission_account,
        &Submission {
            version: VERSION,
            rfa_id,
            agent_id,
            creator: *creator.key,
            submitted_at: Clock::get()?.unix_timestamp,
        },
    )
}

pub fn accept(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    rfa_id: u64,
    agent_id: u64,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let rfa_account = next_account_info(accounts)?;
    let submission_account = next_account_info(accounts)?;
    let workflow_account = next_account_info(accounts)?;
    let publisher = next_account_info(accounts)?;
    let token_program = next_account_info(accounts)?;
    let escrow_token = next_account_info(accounts)?;
    let creator_token = next_account_info(accounts)?;
    require_signer(publisher)?;
    assert_rfa(rfa_account.key, program_id, rfa_id)?;

    let mut registry: Registry = read(registry_account, program_id)?;
    let mut rfa: Rfa = read(rfa_account, program_id)?;
    let mut workflow: Workflow = read(workflow_account, program_id)?;
    if rfa.status != RfaStatus::Open
        || rfa.publisher != *publisher.key
        || rfa.workflow_id != workflow.workflow_id
    {
        return Err(ManowarError::RfaNotOpen.into());
    }

    let rfa_seed = u64_seed(rfa_id);
    let agent_seed = u64_seed(agent_id);
    assert_pda(
        submission_account.key,
        program_id,
        &[SUBMISSION, &rfa_seed, &agent_seed],
    )?;
    let submission: Submission = read(submission_account, program_id)?;
    if submission.agent_id != agent_id || submission.rfa_id != rfa_id {
        return Err(ManowarError::SubmissionNotFound.into());
    }

    let bump = assert_pda(rfa_account.key, program_id, &[RFA, &rfa_seed])?;
    let bump_seed = [bump];
    let signer = [RFA, &rfa_seed, &bump_seed];
    transfer_tokens_signed(
        token_program,
        escrow_token,
        creator_token,
        rfa_account,
        rfa.offer_amount,
        &[&signer],
    )?;

    rfa.status = RfaStatus::Fulfilled;
    rfa.fulfilled_by_agent_id = agent_id;
    rfa.agent_creator = submission.creator;
    workflow.has_active_rfa = false;
    workflow.rfa_id = 0;
    registry.total_escrowed = registry.total_escrowed.saturating_sub(rfa.offer_amount);
    write(rfa_account, &rfa)?;
    write(workflow_account, &workflow)?;
    write(registry_account, &registry)
}

pub fn cancel(program_id: &Pubkey, accounts: &[AccountInfo], rfa_id: u64) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let rfa_account = next_account_info(accounts)?;
    let workflow_account = next_account_info(accounts)?;
    let publisher = next_account_info(accounts)?;
    let token_program = next_account_info(accounts)?;
    let escrow_token = next_account_info(accounts)?;
    let refund_token = next_account_info(accounts)?;
    require_signer(publisher)?;
    assert_rfa(rfa_account.key, program_id, rfa_id)?;

    let mut registry: Registry = read(registry_account, program_id)?;
    let mut rfa: Rfa = read(rfa_account, program_id)?;
    let mut workflow: Workflow = read(workflow_account, program_id)?;
    if rfa.status != RfaStatus::Open
        || rfa.publisher != *publisher.key
        || rfa.workflow_id != workflow.workflow_id
    {
        return Err(ManowarError::RfaNotOpen.into());
    }

    let rfa_seed = u64_seed(rfa_id);
    let bump = assert_pda(rfa_account.key, program_id, &[RFA, &rfa_seed])?;
    let bump_seed = [bump];
    let signer = [RFA, &rfa_seed, &bump_seed];
    transfer_tokens_signed(
        token_program,
        escrow_token,
        refund_token,
        rfa_account,
        rfa.offer_amount,
        &[&signer],
    )?;

    rfa.status = RfaStatus::Cancelled;
    workflow.has_active_rfa = false;
    workflow.rfa_id = 0;
    registry.total_escrowed = registry.total_escrowed.saturating_sub(rfa.offer_amount);
    write(rfa_account, &rfa)?;
    write(workflow_account, &workflow)?;
    write(registry_account, &registry)
}

fn assert_rfa(rfa: &Pubkey, program_id: &Pubkey, rfa_id: u64) -> ProgramResult {
    let rfa_seed = u64_seed(rfa_id);
    assert_pda(rfa, program_id, &[RFA, &rfa_seed])?;
    Ok(())
}

fn validate_rfa_inputs(
    title: &str,
    description: &str,
    skill_count: usize,
    offer_amount: u64,
) -> ProgramResult {
    if offer_amount == 0 {
        return Err(ManowarError::InvalidOffer.into());
    }
    if skill_count == 0 || skill_count > MAX_SKILLS {
        return Err(ManowarError::InvalidOffer.into());
    }
    validate_label(title, 128)?;
    validate_label(description, 1_024)?;
    validate_label("rfa", MAX_TAG_LEN)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rfa_requires_escrow_offer_and_skills() {
        assert!(validate_rfa_inputs("x", "y", 1, 1).is_ok());
        assert!(validate_rfa_inputs("x", "y", 0, 1).is_err());
        assert!(validate_rfa_inputs("x", "y", 1, 0).is_err());
    }
}
