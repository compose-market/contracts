use manowar::{
    account::{create_pda, has_state, read, write},
    is_zero_pubkey,
    seed::{assert_pda, u64_seed, ROYALTY},
    zero_pubkey, ManowarError,
};
use solana_program::{
    account_info::{next_account_info, AccountInfo},
    entrypoint::ProgramResult,
    pubkey::Pubkey,
};

use crate::{
    state::{Registry, Royalty, BASIS_POINTS, ROYALTY_SPACE, VERSION},
    workflow::require_signer,
};

pub fn set(
    program_id: &Pubkey,
    accounts: &[AccountInfo],
    token_id: u64,
    receiver: Pubkey,
    fee_bps: u16,
) -> ProgramResult {
    if is_zero_pubkey(&receiver) || fee_bps > BASIS_POINTS {
        return Err(ManowarError::InvalidOffer.into());
    }
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let royalty_account = next_account_info(accounts)?;
    let admin = next_account_info(accounts)?;
    let system = next_account_info(accounts)?;
    require_signer(admin)?;
    let registry: Registry = read(registry_account, program_id)?;
    if registry.admin != *admin.key {
        return Err(ManowarError::Unauthorized.into());
    }
    let token_seed = u64_seed(token_id);
    if has_state(royalty_account) {
        assert_pda(royalty_account.key, program_id, &[ROYALTY, &token_seed])?;
    } else {
        create_pda(
            admin,
            royalty_account,
            system,
            program_id,
            &[ROYALTY, &token_seed],
            ROYALTY_SPACE,
        )?;
    }
    write(
        royalty_account,
        &Royalty {
            version: VERSION,
            token_id,
            receiver,
            fee_bps,
        },
    )
}

pub fn delete(program_id: &Pubkey, accounts: &[AccountInfo], token_id: u64) -> ProgramResult {
    let accounts = &mut accounts.iter();
    let registry_account = next_account_info(accounts)?;
    let royalty_account = next_account_info(accounts)?;
    let admin = next_account_info(accounts)?;
    require_signer(admin)?;
    let registry: Registry = read(registry_account, program_id)?;
    if registry.admin != *admin.key {
        return Err(ManowarError::Unauthorized.into());
    }
    let token_seed = u64_seed(token_id);
    assert_pda(royalty_account.key, program_id, &[ROYALTY, &token_seed])?;
    write(
        royalty_account,
        &Royalty {
            version: VERSION,
            token_id,
            receiver: zero_pubkey(),
            fee_bps: 0,
        },
    )
}

pub fn calculate(amount: u64, fee_bps: u16) -> u64 {
    amount.saturating_mul(u64::from(fee_bps)) / u64::from(BASIS_POINTS)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn calculates_bps_royalty() {
        assert_eq!(calculate(1_000_000, 500), 50_000);
    }
}
