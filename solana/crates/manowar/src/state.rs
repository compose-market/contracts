use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::pubkey::Pubkey;

use crate::Metadata;

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Agent {
    pub version: u8,
    pub agent_id: u64,
    pub owner: Pubkey,
    pub creator: Pubkey,
    pub dna_hash: [u8; 32],
    pub licenses: u64,
    pub licenses_minted: u64,
    pub license_price: u64,
    pub cloneable: bool,
    pub is_clone: bool,
    pub parent_agent_id: u64,
    pub agent_wallet: Pubkey,
    pub uri: String,
    pub metadata: Vec<Metadata>,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Dna {
    pub dna_hash: [u8; 32],
    pub agent_id: u64,
}

pub fn zero_pubkey() -> Pubkey {
    Pubkey::new_from_array([0; 32])
}

pub fn is_zero_pubkey(key: &Pubkey) -> bool {
    key.to_bytes() == [0; 32]
}
