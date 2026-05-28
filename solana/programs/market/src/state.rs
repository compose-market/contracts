use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::pubkey::Pubkey;

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Registry {
    pub version: u8,
    pub admin: Pubkey,
    pub treasury_token: Pubkey,
    pub payment_mint: Pubkey,
    pub next_workflow_id: u64,
    pub next_rfa_id: u64,
    pub next_lease_id: u64,
    pub total_workflows: u64,
    pub total_escrowed: u64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Workflow {
    pub version: u8,
    pub workflow_id: u64,
    pub owner: Pubkey,
    pub creator: Pubkey,
    pub title: String,
    pub description: String,
    pub banner: String,
    pub uri: String,
    pub total_price: u64,
    pub units: u64,
    pub units_minted: u64,
    pub lease_enabled: bool,
    pub lease_duration: u64,
    pub lease_percent: u8,
    pub has_coordinator: bool,
    pub coordinator_model: String,
    pub has_active_rfa: bool,
    pub rfa_id: u64,
    pub active_lease_id: u64,
    pub agents: Vec<u64>,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct LicenseCounter {
    pub version: u8,
    pub agent_id: u64,
    pub minted: u64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct License {
    pub version: u8,
    pub agent_id: u64,
    pub workflow_id: u64,
    pub license_number: u64,
    pub licensed_at: i64,
    pub active: bool,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub enum RfaStatus {
    Open,
    Fulfilled,
    Cancelled,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Rfa {
    pub version: u8,
    pub rfa_id: u64,
    pub workflow_id: u64,
    pub title: String,
    pub description: String,
    pub required_skills: Vec<[u8; 32]>,
    pub offer_amount: u64,
    pub publisher: Pubkey,
    pub created_at: i64,
    pub status: RfaStatus,
    pub fulfilled_by_agent_id: u64,
    pub agent_creator: Pubkey,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Submission {
    pub version: u8,
    pub rfa_id: u64,
    pub agent_id: u64,
    pub creator: Pubkey,
    pub submitted_at: i64,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub enum LeaseStatus {
    Active,
    Expired,
    Terminated,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Lease {
    pub version: u8,
    pub lease_id: u64,
    pub workflow_id: u64,
    pub leaser: Pubkey,
    pub creator: Pubkey,
    pub start_time: i64,
    pub end_time: i64,
    pub creator_percent: u8,
    pub status: LeaseStatus,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Royalty {
    pub version: u8,
    pub token_id: u64,
    pub receiver: Pubkey,
    pub fee_bps: u16,
}

pub const REGISTRY_SPACE: usize = 4 + 1 + 32 + 32 + 32 + 8 + 8 + 8 + 8 + 8;
pub const WORKFLOW_SPACE: usize = 8_192;
pub const COUNTER_SPACE: usize = 4 + 1 + 8 + 8;
pub const LICENSE_SPACE: usize = 4 + 1 + 8 + 8 + 8 + 8 + 1;
pub const RFA_SPACE: usize = 6_144;
pub const SUBMISSION_SPACE: usize = 4 + 1 + 8 + 8 + 32 + 8;
pub const LEASE_SPACE: usize = 4 + 1 + 8 + 8 + 32 + 32 + 8 + 8 + 1 + 1;
pub const ROYALTY_SPACE: usize = 4 + 1 + 8 + 32 + 2;

pub const VERSION: u8 = 1;
pub const MAX_LEASE_PERCENT: u8 = 20;
pub const TREASURY_FEE_PERCENT: u64 = 10;
pub const BASIS_POINTS: u16 = 10_000;
pub const MAX_AGENTS: usize = 64;
pub const MAX_SKILLS: usize = 32;
