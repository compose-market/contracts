use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::pubkey::Pubkey;

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct FeedbackIndex {
    pub version: u8,
    pub agent_id: u64,
    pub client: Pubkey,
    pub last_index: u64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Feedback {
    pub version: u8,
    pub agent_id: u64,
    pub client: Pubkey,
    pub feedback_index: u64,
    pub value: i128,
    pub value_decimals: u8,
    pub is_revoked: bool,
    pub tag1: String,
    pub tag2: String,
    pub endpoint: String,
    pub feedback_uri: String,
    pub feedback_hash: [u8; 32],
    pub created_at: i64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Response {
    pub version: u8,
    pub agent_id: u64,
    pub client: Pubkey,
    pub feedback_index: u64,
    pub responder: Pubkey,
    pub response_index: u64,
    pub response_uri: String,
    pub response_hash: [u8; 32],
    pub created_at: i64,
}

pub const INDEX_SPACE: usize = 4 + 1 + 8 + 32 + 8;
pub const FEEDBACK_SPACE: usize = 2_048;
pub const RESPONSE_SPACE: usize = 1_024;
