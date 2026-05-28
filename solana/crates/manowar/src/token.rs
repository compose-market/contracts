use solana_program::{
    account_info::AccountInfo,
    instruction::{AccountMeta, Instruction},
    program::invoke,
    program::invoke_signed,
    program_error::ProgramError,
};

use crate::ManowarError;

const SPL_TOKEN_TRANSFER: u8 = 3;

pub fn transfer_tokens<'a>(
    token_program: &AccountInfo<'a>,
    source: &AccountInfo<'a>,
    destination: &AccountInfo<'a>,
    authority: &AccountInfo<'a>,
    amount: u64,
) -> Result<(), ProgramError> {
    if amount == 0 {
        return Ok(());
    }
    let instruction =
        token_transfer_instruction(token_program, source, destination, authority, amount);
    invoke(
        &instruction,
        &[
            source.clone(),
            destination.clone(),
            authority.clone(),
            token_program.clone(),
        ],
    )
    .map_err(|_| ManowarError::TransferFailed.into())
}

pub fn transfer_tokens_signed<'a>(
    token_program: &AccountInfo<'a>,
    source: &AccountInfo<'a>,
    destination: &AccountInfo<'a>,
    authority: &AccountInfo<'a>,
    amount: u64,
    signer_seeds: &[&[&[u8]]],
) -> Result<(), ProgramError> {
    if amount == 0 {
        return Ok(());
    }
    let instruction =
        token_transfer_instruction(token_program, source, destination, authority, amount);
    invoke_signed(
        &instruction,
        &[
            source.clone(),
            destination.clone(),
            authority.clone(),
            token_program.clone(),
        ],
        signer_seeds,
    )
    .map_err(|_| ManowarError::TransferFailed.into())
}

fn token_transfer_instruction(
    token_program: &AccountInfo<'_>,
    source: &AccountInfo<'_>,
    destination: &AccountInfo<'_>,
    authority: &AccountInfo<'_>,
    amount: u64,
) -> Instruction {
    let mut data = Vec::with_capacity(9);
    data.push(SPL_TOKEN_TRANSFER);
    data.extend_from_slice(&amount.to_le_bytes());
    Instruction {
        program_id: *token_program.key,
        accounts: vec![
            AccountMeta::new(*source.key, false),
            AccountMeta::new(*destination.key, false),
            AccountMeta::new_readonly(*authority.key, true),
        ],
        data,
    }
}
