use borsh::{BorshDeserialize, BorshSerialize};
use solana_program::pubkey::Pubkey;

use crate::ManowarError;

pub const AGENT_WALLET: &str = "agentWallet";
pub const X402: &str = "x402";
pub const X402_TRUE: &[u8] = &[1];
pub const MAX_URI_LEN: usize = 512;
pub const MAX_METADATA: usize = 32;
pub const MAX_METADATA_KEY_LEN: usize = 64;
pub const MAX_METADATA_VALUE_LEN: usize = 512;
pub const MAX_TAG_LEN: usize = 64;
pub const MAX_ENDPOINT_LEN: usize = 256;

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub struct Metadata {
    pub key: String,
    pub value: Vec<u8>,
}

pub fn validate_uri(uri: &str) -> Result<(), ManowarError> {
    if uri.len() > MAX_URI_LEN {
        return Err(ManowarError::UriTooLarge);
    }
    Ok(())
}

pub fn validate_label(value: &str, max: usize) -> Result<(), ManowarError> {
    if value.len() > max {
        return Err(ManowarError::MetadataTooLarge);
    }
    Ok(())
}

pub fn validate_metadata(
    key: &str,
    value: &[u8],
    allow_reserved: bool,
) -> Result<(), ManowarError> {
    if key.is_empty() || key.len() > MAX_METADATA_KEY_LEN {
        return Err(ManowarError::InvalidMetadataKey);
    }
    if !allow_reserved && key == AGENT_WALLET {
        return Err(ManowarError::InvalidMetadataKey);
    }
    if value.len() > MAX_METADATA_VALUE_LEN {
        return Err(ManowarError::MetadataTooLarge);
    }
    Ok(())
}

pub fn upsert_metadata(
    entries: &mut Vec<Metadata>,
    key: String,
    value: Vec<u8>,
    allow_reserved: bool,
) -> Result<(), ManowarError> {
    validate_metadata(&key, &value, allow_reserved)?;
    if let Some(entry) = entries.iter_mut().find(|entry| entry.key == key) {
        entry.value = value;
        return Ok(());
    }
    if entries.len() >= MAX_METADATA {
        return Err(ManowarError::MetadataTooLarge);
    }
    entries.push(Metadata { key, value });
    Ok(())
}

pub fn remove_metadata(
    entries: &mut Vec<Metadata>,
    key: &str,
    allow_reserved: bool,
) -> Result<(), ManowarError> {
    validate_metadata(key, &[], allow_reserved)?;
    entries.retain(|entry| entry.key != key);
    Ok(())
}

pub fn wallet_metadata_value(wallet: &Pubkey) -> Vec<u8> {
    wallet.to_bytes().to_vec()
}

pub fn default_agent_metadata(owner: &Pubkey) -> Vec<Metadata> {
    vec![
        Metadata {
            key: X402.to_string(),
            value: X402_TRUE.to_vec(),
        },
        Metadata {
            key: AGENT_WALLET.to_string(),
            value: wallet_metadata_value(owner),
        },
    ]
}

pub fn set_agent_wallet_metadata(
    entries: &mut Vec<Metadata>,
    wallet: Option<&Pubkey>,
) -> Result<(), ManowarError> {
    match wallet {
        Some(wallet) => upsert_metadata(
            entries,
            AGENT_WALLET.to_string(),
            wallet_metadata_value(wallet),
            true,
        ),
        None => remove_metadata(entries, AGENT_WALLET, true),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reserves_agent_wallet_for_identity_logic() {
        let mut entries = default_agent_metadata(&Pubkey::new_unique());
        assert!(upsert_metadata(&mut entries, AGENT_WALLET.to_string(), vec![0], false).is_err());
        assert!(upsert_metadata(&mut entries, X402.to_string(), vec![1], false).is_ok());
    }

    #[test]
    fn default_metadata_contains_x402_and_agent_wallet() {
        let owner = Pubkey::new_unique();
        let entries = default_agent_metadata(&owner);
        assert_eq!(
            entries
                .iter()
                .find(|entry| entry.key == X402)
                .unwrap()
                .value,
            vec![1]
        );
        assert_eq!(
            entries
                .iter()
                .find(|entry| entry.key == AGENT_WALLET)
                .unwrap()
                .value,
            owner.to_bytes().to_vec()
        );
    }
}
