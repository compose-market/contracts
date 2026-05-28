use solana_program::pubkey::Pubkey;

pub const REGISTRY: &[u8] = b"registry";
pub const AGENT: &[u8] = b"agent";
pub const DNA: &[u8] = b"dna";
pub const WARP: &[u8] = b"warp";
pub const FEEDBACK: &[u8] = b"feedback";
pub const FEEDBACK_INDEX: &[u8] = b"feedback-index";
pub const RESPONSE: &[u8] = b"response";
pub const REQUEST: &[u8] = b"request";
pub const WORKFLOW: &[u8] = b"workflow";
pub const LICENSE: &[u8] = b"license";
pub const COUNTER: &[u8] = b"counter";
pub const RFA: &[u8] = b"rfa";
pub const SUBMISSION: &[u8] = b"submission";
pub const LEASE: &[u8] = b"lease";
pub const ROYALTY: &[u8] = b"royalty";

pub fn u64_seed(value: u64) -> [u8; 8] {
    value.to_le_bytes()
}

pub fn assert_pda(
    key: &Pubkey,
    program_id: &Pubkey,
    seeds: &[&[u8]],
) -> Result<u8, crate::ManowarError> {
    let (expected, bump) = Pubkey::find_program_address(seeds, program_id);
    if expected != *key {
        return Err(crate::ManowarError::InvalidPda);
    }
    Ok(bump)
}
