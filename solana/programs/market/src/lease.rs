use manowar::{
    account::{create_pda, read, write},
    seed::{assert_pda, u64_seed, LEASE},
    transfer_tokens, ManowarError,
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
    payment,
    state::{Lease, LeaseStatus, Registry, Workflow, LEASE_SPACE, MAX_LEASE_PERCENT, VERSION},
    workflow::{assert_workflow, require_signer},
};

const DAY_SECONDS: i64 = 86_400;

pub fn create(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    workflow_id: u64,
    duration_days: u64,
) -> ProgramResult {
    if duration_days == 0 {
        return Err(ManowarError::InvalidLeasePercent.into());
    }

    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let lease_account = next_account_info(accounts)?;
    let workflow_account = next_account_info(accounts)?;
    let leaser = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(leaser)?;
    assert_workflow(workflow_account.key, program_id, workflow_id)?;

    let mut registry: Registry = read(registry_account, program_id)?;
    let mut workflow: Workflow = read(workflow_account, program_id)?;
    if !workflow.lease_enabled
        || workflow.active_lease_id != 0
        || workflow.lease_percent > MAX_LEASE_PERCENT
    {
        return Err(ManowarError::LeaseNotActive.into());
    }

    let lease_id = registry.next_lease_id;
    let lease_seed = u64_seed(lease_id);
    create_pda(
        leaser,
        lease_account,
        system,
        program_id,
        &[LEASE, &lease_seed],
        LEASE_SPACE,
    )?;
    let start = Clock::get()?.unix_timestamp;
    let duration = i64::try_from(duration_days)
        .map_err(|_| ProgramError::InvalidInstructionData)?
        .checked_mul(DAY_SECONDS)
        .ok_or(ProgramError::InvalidInstructionData)?;

    write(
        lease_account,
        &Lease {
            version: VERSION,
            lease_id,
            workflow_id,
            leaser: *leaser.key,
            creator: workflow.creator,
            start_time: start,
            end_time: start.saturating_add(duration),
            creator_percent: workflow.lease_percent,
            status: LeaseStatus::Active,
        },
    )?;
    workflow.active_lease_id = lease_id;
    registry.next_lease_id = registry
        .next_lease_id
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    write(workflow_account, &workflow)?;
    write(registry_account, &registry)
}

pub fn terminate(program_id: &Pubkey, accounts: &[AccountInfo], lease_id: u64) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let lease_account = next_account_info(accounts)?;
    let workflow_account = next_account_info(accounts)?;
    let caller = next_account_info(accounts)?;
    require_signer(caller)?;
    assert_lease(lease_account.key, program_id, lease_id)?;

    let mut lease: Lease = read(lease_account, program_id)?;
    let mut workflow: Workflow = read(workflow_account, program_id)?;
    if lease.status != LeaseStatus::Active
        || (lease.leaser != *caller.key && lease.creator != *caller.key)
    {
        return Err(ManowarError::LeaseNotActive.into());
    }
    lease.status = LeaseStatus::Terminated;
    if workflow.active_lease_id == lease_id {
        workflow.active_lease_id = 0;
    }
    write(lease_account, &lease)?;
    write(workflow_account, &workflow)
}

pub fn distribute(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    lease_id: u64,
    amount: u64,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let lease_account = next_account_info(accounts)?;
    let payer = next_account_info(accounts)?;
    let token_program = next_account_info(accounts)?;
    let payer_token = next_account_info(accounts)?;
    let creator_token = next_account_info(accounts)?;
    let leaser_token = next_account_info(accounts)?;
    require_signer(payer)?;
    assert_lease(lease_account.key, program_id, lease_id)?;

    let mut lease: Lease = read(lease_account, program_id)?;
    let now = Clock::get()?.unix_timestamp;
    if lease.status != LeaseStatus::Active || now > lease.end_time {
        if lease.status == LeaseStatus::Active {
            lease.status = LeaseStatus::Expired;
            write(lease_account, &lease)?;
        }
        return Err(ManowarError::LeaseNotActive.into());
    }
    let (creator_share, leaser_share) = payment::split_lease(amount, lease.creator_percent);
    transfer_tokens(
        token_program,
        payer_token,
        creator_token,
        payer,
        creator_share,
    )?;
    transfer_tokens(
        token_program,
        payer_token,
        leaser_token,
        payer,
        leaser_share,
    )
}

fn assert_lease(lease: &Pubkey, program_id: &Pubkey, lease_id: u64) -> ProgramResult {
    let lease_seed = u64_seed(lease_id);
    assert_pda(lease, program_id, &[LEASE, &lease_seed])?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lease_duration_is_days() {
        assert_eq!(DAY_SECONDS, 86_400);
    }
}
