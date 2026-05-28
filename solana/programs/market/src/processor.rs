use borsh::BorshDeserialize;
use solana_program::{
    account_info::AccountInfo, entrypoint::ProgramResult, program_error::ProgramError,
    pubkey::Pubkey,
};

use crate::{instruction::MarketInstruction, lease, rfa, royalty, workflow};

pub fn process(program_id: &Pubkey, accounts: &[AccountInfo], data: &[u8]) -> ProgramResult {
    let instruction = MarketInstruction::try_from_slice(data)
        .map_err(|_| ProgramError::InvalidInstructionData)?;
    match instruction {
        MarketInstruction::Initialize {
            treasury_token,
            payment_mint,
        } => workflow::initialize(program_id, accounts, treasury_token, payment_mint),
        MarketInstruction::MintWorkflow {
            title,
            description,
            banner,
            uri,
            units,
            lease_enabled,
            lease_duration,
            lease_percent,
            has_coordinator,
            coordinator_model,
        } => workflow::mint(
            program_id,
            accounts,
            title,
            description,
            banner,
            uri,
            units,
            lease_enabled,
            lease_duration,
            lease_percent,
            has_coordinator,
            coordinator_model,
        ),
        MarketInstruction::AddAgent { workflow_id } => {
            workflow::add_agent(program_id, accounts, workflow_id)
        }
        MarketInstruction::RemoveAgent {
            workflow_id,
            agent_id,
        } => workflow::remove_agent(program_id, accounts, workflow_id, agent_id),
        MarketInstruction::ConsumeUnit { workflow_id } => {
            workflow::consume_unit(program_id, accounts, workflow_id)
        }
        MarketInstruction::CreateRfa {
            workflow_id,
            title,
            description,
            required_skills,
            offer_amount,
        } => rfa::create(
            program_id,
            accounts,
            workflow_id,
            title,
            description,
            required_skills,
            offer_amount,
        ),
        MarketInstruction::SubmitAgent { rfa_id, agent_id } => {
            rfa::submit(program_id, accounts, rfa_id, agent_id)
        }
        MarketInstruction::AcceptAgent { rfa_id, agent_id } => {
            rfa::accept(program_id, accounts, rfa_id, agent_id)
        }
        MarketInstruction::CancelRfa { rfa_id } => rfa::cancel(program_id, accounts, rfa_id),
        MarketInstruction::CreateLease {
            workflow_id,
            duration_days,
        } => lease::create(program_id, accounts, workflow_id, duration_days),
        MarketInstruction::TerminateLease { lease_id } => {
            lease::terminate(program_id, accounts, lease_id)
        }
        MarketInstruction::DistributeLease { lease_id, amount } => {
            lease::distribute(program_id, accounts, lease_id, amount)
        }
        MarketInstruction::SetRoyalty {
            token_id,
            receiver,
            fee_bps,
        } => royalty::set(program_id, accounts, token_id, receiver, fee_bps),
        MarketInstruction::DeleteRoyalty { token_id } => {
            royalty::delete(program_id, accounts, token_id)
        }
    }
}
