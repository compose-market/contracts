use borsh::{BorshDeserialize, BorshSerialize};
#[allow(deprecated)]
use solana_program::system_instruction;
use solana_program::{
    account_info::AccountInfo, entrypoint::ProgramResult, program::invoke_signed,
    program_error::ProgramError, pubkey::Pubkey, rent::Rent, sysvar::Sysvar,
};

use crate::{assert_pda, ManowarError};

const HEADER: usize = 4;

pub fn read<T: BorshDeserialize>(account: &AccountInfo, owner: &Pubkey) -> Result<T, ProgramError> {
    if account.owner != owner {
        return Err(ManowarError::InvalidAccountOwner.into());
    }
    read_unchecked(account)
}

pub fn read_unchecked<T: BorshDeserialize>(account: &AccountInfo) -> Result<T, ProgramError> {
    let data = account.data.borrow();
    if data.len() < HEADER {
        return Err(ManowarError::AccountTooSmall.into());
    }
    let len = u32::from_le_bytes(
        data[0..HEADER]
            .try_into()
            .map_err(|_| ProgramError::InvalidAccountData)?,
    ) as usize;
    if len == 0 {
        return Err(ManowarError::AccountNotInitialized.into());
    }
    if HEADER + len > data.len() {
        return Err(ManowarError::AccountTooSmall.into());
    }
    T::try_from_slice(&data[HEADER..HEADER + len]).map_err(|_| ManowarError::Serialization.into())
}

pub fn write<T: BorshSerialize>(account: &AccountInfo, state: &T) -> ProgramResult {
    let encoded = borsh::to_vec(state).map_err(|_| ManowarError::Serialization)?;
    let mut data = account.data.borrow_mut();
    if HEADER + encoded.len() > data.len() {
        return Err(ManowarError::AccountTooSmall.into());
    }
    data.fill(0);
    data[0..HEADER].copy_from_slice(&(encoded.len() as u32).to_le_bytes());
    data[HEADER..HEADER + encoded.len()].copy_from_slice(&encoded);
    Ok(())
}

pub fn has_state(account: &AccountInfo) -> bool {
    let data = account.data.borrow();
    data.len() >= HEADER && u32::from_le_bytes(data[0..HEADER].try_into().unwrap_or([0; 4])) != 0
}

pub fn create_pda<'a>(
    payer: &AccountInfo<'a>,
    account: &AccountInfo<'a>,
    system: &AccountInfo<'a>,
    program_id: &Pubkey,
    seeds: &[&[u8]],
    space: usize,
) -> ProgramResult {
    if has_state(account) {
        return Err(ManowarError::AccountAlreadyInitialized.into());
    }
    let bump = assert_pda(account.key, program_id, seeds)?;
    let rent = Rent::get()?;
    let lamports = rent.minimum_balance(space);
    let bump_seed = [bump];
    let mut signed = Vec::with_capacity(seeds.len() + 1);
    signed.extend_from_slice(seeds);
    signed.push(&bump_seed);
    invoke_signed(
        &system_instruction::create_account(
            payer.key,
            account.key,
            lamports,
            space as u64,
            program_id,
        ),
        &[payer.clone(), account.clone(), system.clone()],
        &[&signed],
    )
}
