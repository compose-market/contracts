use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::pubkey::Pubkey;

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Registry {
    pub version: u8,
    pub admin: Pubkey,
    pub next_agent_id: u64,
    pub total_agents: u64,
    pub consumers: Vec<Pubkey>,
}

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Warp {
    pub version: u8,
    pub agent_id: u64,
    pub original_hash: [u8; 32],
    pub original_creator: Pubkey,
    pub warper: Pubkey,
    pub royalty_expiry: i64,
    pub royalties_claimed: bool,
    pub accumulated_royalties: u64,
}

pub const REGISTRY_SPACE: usize = 4 + 1 + 32 + 8 + 8 + 4 + (32 * 32);
pub const AGENT_SPACE: usize = 12_288;
pub const DNA_SPACE: usize = 4 + 32 + 8;
pub const WARP_SPACE: usize = 4 + 1 + 8 + 32 + 32 + 32 + 8 + 1 + 8;

pub const ROYALTY_CLAIM_PERIOD_SECONDS: i64 = 365 * 24 * 60 * 60;
