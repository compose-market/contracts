use borsh::{BorshDeserialize, BorshSerialize};
use manowar::Metadata;
use solana_program::pubkey::Pubkey;

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub enum IdentityInstruction {
    Initialize,
    Register {
        uri: String,
        metadata: Vec<Metadata>,
    },
    Mint {
        dna_hash: [u8; 32],
        licenses: u64,
        license_price: u64,
        cloneable: bool,
        uri: String,
        metadata: Vec<Metadata>,
    },
    Clone {
        dna_hash: [u8; 32],
        licenses: u64,
        license_price: u64,
        uri: String,
        metadata: Vec<Metadata>,
    },
    Warp {
        original_hash: [u8; 32],
        original_creator: Pubkey,
        dna_hash: [u8; 32],
        licenses: u64,
        license_price: u64,
        uri: String,
        metadata: Vec<Metadata>,
    },
    SetUri {
        agent_id: u64,
        uri: String,
    },
    SetMetadata {
        agent_id: u64,
        key: String,
        value: Vec<u8>,
    },
    RemoveMetadata {
        agent_id: u64,
        key: String,
    },
    SetAgentWallet {
        agent_id: u64,
        wallet: Pubkey,
    },
    Transfer {
        agent_id: u64,
        new_owner: Pubkey,
    },
    UpdatePrice {
        agent_id: u64,
        license_price: u64,
    },
    Authorize {
        consumer: Pubkey,
    },
    Revoke {
        consumer: Pubkey,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packs_identity_instruction() {
        let instruction = IdentityInstruction::SetMetadata {
            agent_id: 7,
            key: "x402".to_string(),
            value: vec![1],
        };
        let encoded = borsh::to_vec(&instruction).unwrap();
        let decoded = IdentityInstruction::try_from_slice(&encoded).unwrap();
        assert_eq!(decoded, instruction);
    }
}
