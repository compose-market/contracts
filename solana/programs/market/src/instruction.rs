use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::pubkey::Pubkey;

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub enum MarketInstruction {
    Initialize {
        treasury_token: Pubkey,
        payment_mint: Pubkey,
    },
    MintWorkflow {
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
    },
    AddAgent {
        workflow_id: u64,
    },
    RemoveAgent {
        workflow_id: u64,
        agent_id: u64,
    },
    ConsumeUnit {
        workflow_id: u64,
    },
    CreateRfa {
        workflow_id: u64,
        title: String,
        description: String,
        required_skills: Vec<[u8; 32]>,
        offer_amount: u64,
    },
    SubmitAgent {
        rfa_id: u64,
        agent_id: u64,
    },
    AcceptAgent {
        rfa_id: u64,
        agent_id: u64,
    },
    CancelRfa {
        rfa_id: u64,
    },
    CreateLease {
        workflow_id: u64,
        duration_days: u64,
    },
    TerminateLease {
        lease_id: u64,
    },
    DistributeLease {
        lease_id: u64,
        amount: u64,
    },
    SetRoyalty {
        token_id: u64,
        receiver: Pubkey,
        fee_bps: u16,
    },
    DeleteRoyalty {
        token_id: u64,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packs_workflow_instruction() {
        let instruction = MarketInstruction::MintWorkflow {
            title: "Workflow".to_string(),
            description: "nested agents".to_string(),
            banner: "ipfs://banner".to_string(),
            uri: "ipfs://workflow".to_string(),
            units: 10,
            lease_enabled: true,
            lease_duration: 30,
            lease_percent: 20,
            has_coordinator: true,
            coordinator_model: "gpt-5.5".to_string(),
        };
        let encoded = borsh::to_vec(&instruction).unwrap();
        assert_eq!(
            MarketInstruction::try_from_slice(&encoded).unwrap(),
            instruction
        );
    }
}
