use borsh::{BorshDeserialize, BorshSerialize};

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub enum ValidationInstruction {
    Initialize,
    Request {
        agent_id: u64,
        validator_type: String,
        task_hash: [u8; 32],
        request_uri: String,
    },
    Respond {
        request_id: u64,
        valid: bool,
        evidence_hash: [u8; 32],
        evidence_uri: String,
    },
    Close {
        request_id: u64,
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packs_validation_request() {
        let instruction = ValidationInstruction::Request {
            agent_id: 3,
            validator_type: "replay".to_string(),
            task_hash: [4; 32],
            request_uri: "ipfs://request".to_string(),
        };
        let encoded = borsh::to_vec(&instruction).unwrap();
        assert_eq!(
            ValidationInstruction::try_from_slice(&encoded).unwrap(),
            instruction
        );
    }
}
