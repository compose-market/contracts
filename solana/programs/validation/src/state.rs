use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::pubkey::Pubkey;

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Registry {
    pub version: u8,
    pub admin: Pubkey,
    pub next_request_id: u64,
    pub total_requests: u64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Request {
    pub version: u8,
    pub request_id: u64,
    pub agent_id: u64,
    pub requester: Pubkey,
    pub validator_type: String,
    pub task_hash: [u8; 32],
    pub request_uri: String,
    pub timestamp: i64,
    pub closed: bool,
    pub response_count: u64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Response {
    pub version: u8,
    pub response_id: u64,
    pub request_id: u64,
    pub validator: Pubkey,
    pub valid: bool,
    pub evidence_hash: [u8; 32],
    pub evidence_uri: String,
    pub timestamp: i64,
}

pub const REGISTRY_SPACE: usize = 4 + 1 + 32 + 8 + 8;
pub const REQUEST_SPACE: usize = 1_536;
pub const RESPONSE_SPACE: usize = 1_024;
