use borsh::BorshDeserialize;
use manowar::{
    account::{create_pda, read, write},
    default_agent_metadata, is_zero_pubkey,
    metadata::{remove_metadata, set_agent_wallet_metadata, upsert_metadata, validate_uri},
    seed::{assert_pda, u64_seed, AGENT, DNA, REGISTRY, WARP},
    zero_pubkey, Agent, Dna, ManowarError, Metadata,
};
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    clock::Clock,
    entrypoint::ProgramResult,
    hash::hashv,
    program_error::ProgramError,
    pubkey::Pubkey,
    sysvar::Sysvar,
};

use crate::{
    instruction::IdentityInstruction,
    state::{
        Registry, Warp, AGENT_SPACE, DNA_SPACE, REGISTRY_SPACE, ROYALTY_CLAIM_PERIOD_SECONDS,
        WARP_SPACE,
    },
};

const VERSION: u8 = 1;
const MAX_CONSUMERS: usize = 32;

pub fn process<'a>(
    program_id: &Pubkey,
    accounts: &'a [AccountInfo<'a>],
    data: &[u8],
) -> ProgramResult {
    let instruction = IdentityInstruction::try_from_slice(data)
        .map_err(|_| ProgramError::InvalidInstructionData)?;
    match instruction {
        IdentityInstruction::Initialize => initialize(program_id, accounts),
        IdentityInstruction::Register { uri, metadata } => {
            register(program_id, accounts, uri, metadata)
        }
        IdentityInstruction::Mint {
            dna_hash,
            licenses,
            license_price,
            cloneable,
            uri,
            metadata,
        } => mint(
            program_id,
            accounts,
            dna_hash,
            licenses,
            license_price,
            cloneable,
            false,
            0,
            uri,
            metadata,
        ),
        IdentityInstruction::Clone {
            dna_hash,
            licenses,
            license_price,
            uri,
            metadata,
        } => clone_agent(
            program_id,
            accounts,
            dna_hash,
            licenses,
            license_price,
            uri,
            metadata,
        ),
        IdentityInstruction::Warp {
            original_hash,
            original_creator,
            dna_hash,
            licenses,
            license_price,
            uri,
            metadata,
        } => warp_agent(
            program_id,
            accounts,
            original_hash,
            original_creator,
            dna_hash,
            licenses,
            license_price,
            uri,
            metadata,
        ),
        IdentityInstruction::SetUri { agent_id, uri } => {
            set_uri(program_id, accounts, agent_id, uri)
        }
        IdentityInstruction::SetMetadata {
            agent_id,
            key,
            value,
        } => set_metadata(program_id, accounts, agent_id, key, value),
        IdentityInstruction::RemoveMetadata { agent_id, key } => {
            remove_metadata_instruction(program_id, accounts, agent_id, key)
        }
        IdentityInstruction::SetAgentWallet { agent_id, wallet } => {
            set_agent_wallet(program_id, accounts, agent_id, wallet)
        }
        IdentityInstruction::Transfer {
            agent_id,
            new_owner,
        } => transfer(program_id, accounts, agent_id, new_owner),
        IdentityInstruction::UpdatePrice {
            agent_id,
            license_price,
        } => update_price(program_id, accounts, agent_id, license_price),
        IdentityInstruction::Authorize { consumer } => {
            authorize(program_id, accounts, consumer, true)
        }
        IdentityInstruction::Revoke { consumer } => {
            authorize(program_id, accounts, consumer, false)
        }
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
            next_agent_id: 1,
            total_agents: 0,
            consumers: Vec::new(),
        },
    )
}

fn register(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    uri: String,
    metadata: Vec<Metadata>,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let dna_account = next_account_info(accounts)?;
    let owner = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(owner)?;

    let registry: Registry = read(registry_account, program_id)?;
    let dna_hash = derived_register_dna(owner.key, &uri, registry.next_agent_id);
    mint_from_parts(
        program_id,
        registry_account,
        agent_account,
        dna_account,
        owner,
        system,
        *owner.key,
        dna_hash,
        0,
        0,
        false,
        false,
        0,
        uri,
        metadata,
    )
    .map(|_| ())
}

#[allow(clippy::too_many_arguments)]
fn mint(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    dna_hash: [u8; 32],
    licenses: u64,
    license_price: u64,
    cloneable: bool,
    is_clone: bool,
    parent_agent_id: u64,
    uri: String,
    metadata: Vec<Metadata>,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let dna_account = next_account_info(accounts)?;
    let owner = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(owner)?;

    mint_from_parts(
        program_id,
        registry_account,
        agent_account,
        dna_account,
        owner,
        system,
        *owner.key,
        dna_hash,
        licenses,
        license_price,
        cloneable,
        is_clone,
        parent_agent_id,
        uri,
        metadata,
    )
    .map(|_| ())
}

fn clone_agent(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    dna_hash: [u8; 32],
    licenses: u64,
    license_price: u64,
    uri: String,
    metadata: Vec<Metadata>,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let parent_account = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let dna_account = next_account_info(accounts)?;
    let owner = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(owner)?;

    let parent: Agent = read(parent_account, program_id)?;
    assert_agent_pda(parent_account.key, program_id, parent.agent_id)?;
    if !parent.cloneable {
        return Err(ManowarError::AgentNotCloneable.into());
    }
    if parent.is_clone {
        return Err(ManowarError::CloneCannotBeCloned.into());
    }

    mint_from_parts(
        program_id,
        registry_account,
        agent_account,
        dna_account,
        owner,
        system,
        *owner.key,
        dna_hash,
        licenses,
        license_price,
        false,
        true,
        parent.agent_id,
        uri,
        metadata,
    )
    .map(|_| ())
}

#[allow(clippy::too_many_arguments)]
fn warp_agent(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    original_hash: [u8; 32],
    original_creator: Pubkey,
    dna_hash: [u8; 32],
    licenses: u64,
    license_price: u64,
    uri: String,
    metadata: Vec<Metadata>,
) -> ProgramResult {
    if original_hash == [0; 32] {
        return Err(ManowarError::InvalidDna.into());
    }

    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let agent_account = next_account_info(accounts)?;
    let dna_account = next_account_info(accounts)?;
    let warp_account = next_account_info(accounts)?;
    let warper = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(warper)?;

    let external_seeds = &[WARP, original_hash.as_ref()];
    create_pda(
        warper,
        warp_account,
        system,
        program_id,
        external_seeds,
        WARP_SPACE,
    )?;

    let agent_id = mint_from_parts(
        program_id,
        registry_account,
        agent_account,
        dna_account,
        warper,
        system,
        *warper.key,
        dna_hash,
        licenses,
        license_price,
        false,
        false,
        0,
        uri,
        metadata,
    )?;

    let now = Clock::get()?.unix_timestamp;
    write(
        warp_account,
        &Warp {
            version: VERSION,
            agent_id,
            original_hash,
            original_creator,
            warper: *warper.key,
            royalty_expiry: now.saturating_add(ROYALTY_CLAIM_PERIOD_SECONDS),
            royalties_claimed: false,
            accumulated_royalties: 0,
        },
    )
}

#[allow(clippy::too_many_arguments)]
fn mint_from_parts<'a>(
    program_id: &Pubkey,
    registry_account: &AccountInfo<'a>,
    agent_account: &AccountInfo<'a>,
    dna_account: &AccountInfo<'a>,
    payer: &AccountInfo<'a>,
    system: &AccountInfo<'a>,
    owner_key: Pubkey,
    dna_hash: [u8; 32],
    licenses: u64,
    license_price: u64,
    cloneable: bool,
    is_clone: bool,
    parent_agent_id: u64,
    uri: String,
    metadata: Vec<Metadata>,
) -> Result<u64, ProgramError> {
    if dna_hash == [0; 32] {
        return Err(ManowarError::InvalidDna.into());
    }
    validate_uri(&uri)?;

    let mut registry: Registry = read(registry_account, program_id)?;
    let agent_id = registry.next_agent_id;
    let agent_id_seed = u64_seed(agent_id);
    create_pda(
        payer,
        agent_account,
        system,
        program_id,
        &[AGENT, &agent_id_seed],
        AGENT_SPACE,
    )?;
    create_pda(
        payer,
        dna_account,
        system,
        program_id,
        &[DNA, dna_hash.as_ref()],
        DNA_SPACE,
    )?;

    let mut entries = default_agent_metadata(&owner_key);
    for entry in metadata {
        upsert_metadata(&mut entries, entry.key, entry.value, false)?;
    }

    write(
        agent_account,
        &Agent {
            version: VERSION,
            agent_id,
            owner: owner_key,
            creator: owner_key,
            dna_hash,
            licenses,
            licenses_minted: 0,
            license_price,
            cloneable,
            is_clone,
            parent_agent_id,
            agent_wallet: owner_key,
            uri,
            metadata: entries,
        },
    )?;
    write(dna_account, &Dna { dna_hash, agent_id })?;

    registry.next_agent_id = registry
        .next_agent_id
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    registry.total_agents = registry
        .total_agents
        .checked_add(1)
        .ok_or(ProgramError::InvalidInstructionData)?;
    write(registry_account, &registry)?;

    Ok(agent_id)
}

fn set_uri<'a>(
    program_id: &Pubkey,
    accounts: &'a [AccountInfo<'a>],
    agent_id: u64,
    uri: String,
) -> ProgramResult {
    validate_uri(&uri)?;
    let (agent_account, signer) = agent_and_owner(program_id, accounts, agent_id)?;
    let mut agent: Agent = read(agent_account, program_id)?;
    require_owner(&agent, signer)?;
    agent.uri = uri;
    write(agent_account, &agent)
}

fn set_metadata<'a>(
    program_id: &Pubkey,
    accounts: &'a [AccountInfo<'a>],
    agent_id: u64,
    key: String,
    value: Vec<u8>,
) -> ProgramResult {
    let (agent_account, signer) = agent_and_owner(program_id, accounts, agent_id)?;
    let mut agent: Agent = read(agent_account, program_id)?;
    require_owner(&agent, signer)?;
    upsert_metadata(&mut agent.metadata, key, value, false)?;
    write(agent_account, &agent)
}

fn remove_metadata_instruction<'a>(
    program_id: &Pubkey,
    accounts: &'a [AccountInfo<'a>],
    agent_id: u64,
    key: String,
) -> ProgramResult {
    let (agent_account, signer) = agent_and_owner(program_id, accounts, agent_id)?;
    let mut agent: Agent = read(agent_account, program_id)?;
    require_owner(&agent, signer)?;
    remove_metadata(&mut agent.metadata, &key, false)?;
    write(agent_account, &agent)
}

fn set_agent_wallet(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    agent_id: u64,
    wallet: Pubkey,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let agent_account = next_account_info(accounts)?;
    let owner = next_account_info(accounts)?;
    require_signer(owner)?;
    assert_agent_pda(agent_account.key, program_id, agent_id)?;

    let mut agent: Agent = read(agent_account, program_id)?;
    require_owner(&agent, owner)?;

    if !is_zero_pubkey(&wallet) && wallet != agent.owner {
        let wallet_account = next_account_info(accounts)?;
        if wallet_account.key != &wallet || !wallet_account.is_signer {
            return Err(ManowarError::InvalidAgentWallet.into());
        }
    }

    agent.agent_wallet = wallet;
    if is_zero_pubkey(&wallet) {
        set_agent_wallet_metadata(&mut agent.metadata, None)?;
    } else {
        set_agent_wallet_metadata(&mut agent.metadata, Some(&wallet))?;
    }
    write(agent_account, &agent)
}

fn transfer<'a>(
    program_id: &Pubkey,
    accounts: &'a [AccountInfo<'a>],
    agent_id: u64,
    new_owner: Pubkey,
) -> ProgramResult {
    if is_zero_pubkey(&new_owner) {
        return Err(ManowarError::Unauthorized.into());
    }
    let (agent_account, signer) = agent_and_owner(program_id, accounts, agent_id)?;
    let mut agent: Agent = read(agent_account, program_id)?;
    require_owner(&agent, signer)?;
    agent.owner = new_owner;
    agent.agent_wallet = zero_pubkey();
    set_agent_wallet_metadata(&mut agent.metadata, None)?;
    write(agent_account, &agent)
}

fn update_price(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    agent_id: u64,
    license_price: u64,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let agent_account = next_account_info(accounts)?;
    let creator = next_account_info(accounts)?;
    require_signer(creator)?;
    assert_agent_pda(agent_account.key, program_id, agent_id)?;
    let mut agent: Agent = read(agent_account, program_id)?;
    if agent.creator != *creator.key {
        return Err(ManowarError::Unauthorized.into());
    }
    agent.license_price = license_price;
    write(agent_account, &agent)
}

fn authorize(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    consumer: Pubkey,
    enabled: bool,
) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let admin = next_account_info(accounts)?;
    require_signer(admin)?;
    assert_pda(registry_account.key, program_id, &[REGISTRY])?;

    let mut registry: Registry = read(registry_account, program_id)?;
    if registry.admin != *admin.key {
        return Err(ManowarError::Unauthorized.into());
    }
    if enabled {
        if !registry.consumers.contains(&consumer) {
            if registry.consumers.len() >= MAX_CONSUMERS {
                return Err(ManowarError::AccountTooSmall.into());
            }
            registry.consumers.push(consumer);
        }
    } else {
        registry
            .consumers
            .retain(|candidate| *candidate != consumer);
    }
    write(registry_account, &registry)
}

fn agent_and_owner<'a>(
    program_id: &Pubkey,
    accounts: &'a [AccountInfo<'a>],
    agent_id: u64,
) -> Result<(&'a AccountInfo<'a>, &'a AccountInfo<'a>), ProgramError> {
    let accounts = &mut accounts.iter();
    let agent_account = next_account_info(accounts)?;
    let owner = next_account_info(accounts)?;
    require_signer(owner)?;
    assert_agent_pda(agent_account.key, program_id, agent_id)?;
    Ok((agent_account, owner))
}

fn assert_agent_pda(agent: &Pubkey, program_id: &Pubkey, agent_id: u64) -> ProgramResult {
    let agent_id_seed = u64_seed(agent_id);
    assert_pda(agent, program_id, &[AGENT, &agent_id_seed])?;
    Ok(())
}

fn require_owner(agent: &Agent, signer: &AccountInfo) -> ProgramResult {
    if agent.owner != *signer.key {
        return Err(ManowarError::Unauthorized.into());
    }
    Ok(())
}

fn require_signer(account: &AccountInfo) -> ProgramResult {
    if !account.is_signer {
        return Err(ManowarError::Unauthorized.into());
    }
    Ok(())
}

fn derived_register_dna(owner: &Pubkey, uri: &str, agent_id: u64) -> [u8; 32] {
    hashv(&[
        b"ERC8004_MANOWAR",
        owner.as_ref(),
        uri.as_bytes(),
        &agent_id.to_le_bytes(),
    ])
    .to_bytes()
}

#[cfg(test)]
mod tests {
    use super::*;
    use manowar::{AGENT_WALLET, X402};

    #[test]
    fn register_dna_is_stable_for_same_inputs() {
        let owner = Pubkey::new_unique();
        let first = derived_register_dna(&owner, "ipfs://agent", 1);
        let second = derived_register_dna(&owner, "ipfs://agent", 1);
        assert_eq!(first, second);
        assert_ne!(first, derived_register_dna(&owner, "ipfs://agent", 2));
    }

    #[test]
    fn default_agent_fields_are_erc8004_ready() {
        let owner = Pubkey::new_unique();
        let metadata = default_agent_metadata(&owner);
        assert!(metadata
            .iter()
            .any(|entry| entry.key == X402 && entry.value == vec![1]));
        assert!(metadata
            .iter()
            .any(|entry| entry.key == AGENT_WALLET && entry.value == owner.to_bytes().to_vec()));
    }
}
