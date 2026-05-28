#![allow(unexpected_cfgs)]

pub mod instruction;
pub mod lease;
pub mod payment;
pub mod processor;
pub mod rfa;
pub mod royalty;
pub mod state;
pub mod workflow;

#[cfg(not(feature = "no-entrypoint"))]
mod entrypoint {
    use solana_program::{
        account_info::AccountInfo, entrypoint, entrypoint::ProgramResult, pubkey::Pubkey,
    };

    entrypoint!(process_instruction);

    pub fn process_instruction(
        program_id: &Pubkey,
        accounts: &[AccountInfo],
        data: &[u8],
    ) -> ProgramResult {
        crate::processor::process(program_id, accounts, data)
    }
}
