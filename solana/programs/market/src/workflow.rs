use manowar::{
    account::{create_pda, has_state, read, write},
    metadata::{validate_label, validate_uri, MAX_ENDPOINT_LEN},
    seed::{assert_pda, u64_seed, AGENT, COUNTER, LICENSE, REGISTRY, WORKFLOW},
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
    payment,
    state::{
        License, LicenseCounter, Registry, Workflow, COUNTER_SPACE, LICENSE_SPACE, MAX_AGENTS,
        MAX_LEASE_PERCENT, REGISTRY_SPACE, VERSION, WORKFLOW_SPACE,
    },
};

pub fn initialize(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    treasury_token: Pubkey,
    payment_mint: Pubkey,
) -> ProgramResult {
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
            treasury_token,
            payment_mint,
            next_workflow_id: 1,
            next_rfa_id: 1,
            next_lease_id: 1,
            total_workflows: 0,
            total_escrowed: 0,
        },
    )
}

#[allow(clippy::too_many_arguments)]
#[allow(clippy::manual_is_multiple_of)]
pub fn mint(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    title: String,
    description: String,
    banner: String,
    uri: String,
    units: u64,
    lease_enabled: bool,
    lease_duration: u64,
    lease_percent: u8,
    has_coordinator: bool,
    coordinator_model: String,
) -> ProgramResult {
    validate_workflow_inputs(
        &title,
        &description,
        &banner,
        &uri,
        units,
        lease_enabled,
        lease_percent,
        &coordinator_model,
    )?;

    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let workflow_account = next_account_info(accounts)?;
    let owner = next_account_info(accounts)?;
    let identity_program = next_account_info(accounts)?;
    let token_program = next_account_info(accounts)?;
    let payer_token = next_account_info(accounts)?;
    let treasury_token = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(owner)?;

    let mut registry: Registry = read(registry_account, program_id)?;
    if *treasury_token.key != registry.treasury_token {
        return Err(ManowarError::Unauthorized.into());
    }

    let workflow_id = registry.next_workflow_id;
    let workflow_seed = u64_seed(workflow_id);
    create_pda(
        owner,
        workflow_account,
        system,
        program_id,
        &[WORKFLOW, &workflow_seed],
        WORKFLOW_SPACE,
    )?;

    let remaining: Vec<&AccountInfo> = accounts.collect();
    if remaining.len() % 4 != 0 {
        return Err(ProgramError::NotEnoughAccountKeys);
    }
    let mut agents = Vec::with_capacity(remaining.len() / 4);
    let mut total_price = 0_u64;
    for group in remaining.chunks(4) {
        let agent = license_agent(
            program_id,
            identity_program.key,
            owner,
            system,
            group[0],
            group[1],
            group[2],
            workflow_id,
        )?;
        payment::pay_license(
            token_program,
            payer_token,
            treasury_token,
            group[3],
            owner,
            agent.license_price,
        )?;
        total_price = total_price
            .checked_add(agent.license_price)
            .ok_or(ProgramError::InvalidInstructionData)?;
        agents.push(agent.agent_id);
    }

    write(
        workflow_account,
        &Workflow {
            version: VERSION,
            workflow_id,
            owner: *owner.key,
            creator: *owner.key,
            title,
            description,
            banner,
            uri,
            total_price,
            units,
            units_minted: 0,
            lease_enabled,
            lease_duration,
            lease_percent,
            has_coordinator,
            coordinator_model,
            has_active_rfa: false,
            rfa_id: 0,
            active_lease_id: 0,
            agents,
        },
    )?;

    registry.next_workflow_id = registry
        .next_workflow_id
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    registry.total_workflows = registry
        .total_workflows
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    write(registry_account, &registry)
}

pub fn add_agent(program_id: &Pubkey, accounts: &[AccountInfo], workflow_id: u64) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let workflow_account = next_account_info(accounts)?;
    let owner = next_account_info(accounts)?;
    let identity_program = next_account_info(accounts)?;
    let token_program = next_account_info(accounts)?;
    let payer_token = next_account_info(accounts)?;
    let treasury_token = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let counter_account = next_account_info(accounts)?;
    let license_account = next_account_info(accounts)?;
    let creator_token = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(owner)?;
    assert_workflow(workflow_account.key, program_id, workflow_id)?;

    let mut workflow: Workflow = read(workflow_account, program_id)?;
    require_workflow_owner(&workflow, owner)?;
    if workflow.agents.len() >= MAX_AGENTS {
        return Err(ManowarError::AccountTooSmall.into());
    }
    let agent = license_agent(
        program_id,
        identity_program.key,
        owner,
        system,
        agent_account,
        counter_account,
        license_account,
        workflow_id,
    )?;
    if workflow.agents.contains(&agent.agent_id) {
        return Err(ManowarError::AlreadyLicensed.into());
    }
    payment::pay_license(
        token_program,
        payer_token,
        treasury_token,
        creator_token,
        owner,
        agent.license_price,
    )?;
    workflow.total_price = workflow
        .total_price
        .checked_add(agent.license_price)
        .ok_or(ProgramError::InvalidInstructionData)?;
    workflow.agents.push(agent.agent_id);
    write(workflow_account, &workflow)
}

pub fn remove_agent(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    workflow_id: u64,
    agent_id: u64,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let workflow_account = next_account_info(accounts)?;
    let owner = next_account_info(accounts)?;
    let identity_program = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let license_account = next_account_info(accounts)?;
    require_signer(owner)?;
    assert_workflow(workflow_account.key, program_id, workflow_id)?;

    let mut workflow: Workflow = read(workflow_account, program_id)?;
    require_workflow_owner(&workflow, owner)?;
    let agent: Agent = read(agent_account, identity_program.key)?;
    if agent.agent_id != agent_id {
        return Err(ManowarError::AgentNotFound.into());
    }
    assert_agent(agent_account.key, identity_program.key, agent_id)?;

    let agent_seed = u64_seed(agent_id);
    let workflow_seed = u64_seed(workflow_id);
    assert_pda(
        license_account.key,
        program_id,
        &[LICENSE, &agent_seed, &workflow_seed],
    )?;
    let mut license: License = read(license_account, program_id)?;
    if !license.active {
        return Err(ManowarError::NotLicensed.into());
    }
    license.active = false;
    workflow.agents.retain(|existing| *existing != agent_id);
    workflow.total_price = workflow.total_price.saturating_sub(agent.license_price);
    write(license_account, &license)?;
    write(workflow_account, &workflow)
}

pub fn consume_unit(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    workflow_id: u64,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let workflow_account = next_account_info(accounts)?;
    let buyer = next_account_info(accounts)?;
    require_signer(buyer)?;
    assert_workflow(workflow_account.key, program_id, workflow_id)?;

    let mut workflow: Workflow = read(workflow_account, program_id)?;
    if workflow.units_minted >= workflow.units {
        return Err(ManowarError::NoLicensesAvailable.into());
    }
    workflow.units_minted = workflow
        .units_minted
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    write(workflow_account, &workflow)
}

#[allow(clippy::too_many_arguments)]
fn license_agent<'a>(
    program_id: &Pubkey,
    identity_program: &Pubkey,
    payer: &AccountInfo<'a>,
    system: &AccountInfo<'a>,
    agent_account: &AccountInfo<'a>,
    counter_account: &AccountInfo<'a>,
    license_account: &AccountInfo<'a>,
    workflow_id: u64,
) -> Result<Agent, ProgramError> {
    let agent: Agent = read(agent_account, identity_program)?;
    assert_agent(agent_account.key, identity_program, agent.agent_id)?;

    let agent_seed = u64_seed(agent.agent_id);
    let mut counter = if has_state(counter_account) {
        let counter: LicenseCounter = read(counter_account, program_id)?;
        if counter.agent_id != agent.agent_id {
            return Err(ManowarError::InvalidIndex.into());
        }
        counter
    } else {
        create_pda(
            payer,
            counter_account,
            system,
            program_id,
            &[COUNTER, &agent_seed],
            COUNTER_SPACE,
        )?;
        LicenseCounter {
            version: VERSION,
            agent_id: agent.agent_id,
            minted: 0,
        }
    };

    if agent.licenses != 0 && counter.minted >= agent.licenses {
        return Err(ManowarError::NoLicensesAvailable.into());
    }
    counter.minted = counter
        .minted
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;

    let workflow_seed = u64_seed(workflow_id);
    create_pda(
        payer,
        license_account,
        system,
        program_id,
        &[LICENSE, &agent_seed, &workflow_seed],
        LICENSE_SPACE,
    )?;
    write(counter_account, &counter)?;
    write(
        license_account,
        &License {
            version: VERSION,
            agent_id: agent.agent_id,
            workflow_id,
            license_number: counter.minted,
            licensed_at: Clock::get()?.unix_timestamp,
            active: true,
        },
    )?;
    Ok(agent)
}

#[allow(clippy::too_many_arguments)]
fn validate_workflow_inputs(
    title: &str,
    description: &str,
    banner: &str,
    uri: &str,
    units: u64,
    lease_enabled: bool,
    lease_percent: u8,
    coordinator_model: &str,
) -> ProgramResult {
    if units == 0 {
        return Err(ManowarError::InvalidUnits.into());
    }
    if lease_enabled && lease_percent > MAX_LEASE_PERCENT {
        return Err(ManowarError::InvalidLeasePercent.into());
    }
    validate_label(title, 128)?;
    validate_label(description, 1_024)?;
    validate_uri(banner)?;
    validate_uri(uri)?;
    validate_label(coordinator_model, MAX_ENDPOINT_LEN)?;
    Ok(())
}

pub fn assert_workflow(workflow: &Pubkey, program_id: &Pubkey, workflow_id: u64) -> ProgramResult {
    let workflow_seed = u64_seed(workflow_id);
    assert_pda(workflow, program_id, &[WORKFLOW, &workflow_seed])?;
    Ok(())
}

pub fn require_workflow_owner(workflow: &Workflow, owner: &AccountInfo) -> ProgramResult {
    if workflow.owner != *owner.key {
        return Err(ManowarError::Unauthorized.into());
    }
    Ok(())
}

pub fn assert_agent(agent: &Pubkey, identity_program: &Pubkey, agent_id: u64) -> ProgramResult {
    let agent_seed = u64_seed(agent_id);
    assert_pda(agent, identity_program, &[AGENT, &agent_seed])?;
    Ok(())
}

pub fn require_signer(account: &AccountInfo) -> ProgramResult {
    if !account.is_signer {
        return Err(ManowarError::Unauthorized.into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_workflow_without_units() {
        let result = validate_workflow_inputs("a", "b", "ipfs://b", "ipfs://w", 0, false, 0, "");
        assert_eq!(result, Err(ManowarError::InvalidUnits.into()));
    }

    #[test]
    fn enforces_lease_percent_cap() {
        let result = validate_workflow_inputs("a", "b", "ipfs://b", "ipfs://w", 1, true, 21, "");
        assert_eq!(result, Err(ManowarError::InvalidLeasePercent.into()));
    }
}
