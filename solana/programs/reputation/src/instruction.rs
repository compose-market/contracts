use borsh::{BorshDeserialize, BorshSerialize};

#[derive(BorshSerialize, BorshDeserialize, Clone, Debug, Eq, PartialEq)]
pub enum ReputationInstruction {
    GiveFeedback {
        agent_id: u64,
        value: i128,
        value_decimals: u8,
        tag1: String,
        tag2: String,
        endpoint: String,
        feedback_uri: String,
        feedback_hash: [u8; 32],
    },
    RevokeFeedback {
        agent_id: u64,
        feedback_index: u64,
    },
    AppendResponse {
        agent_id: u64,
        feedback_index: u64,
        response_index: u64,
        response_uri: String,
        response_hash: [u8; 32],
    },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packs_feedback_instruction() {
        let instruction = ReputationInstruction::GiveFeedback {
            agent_id: 9,
            value: 45,
            value_decimals: 1,
            tag1: "quality".to_string(),
            tag2: "agent".to_string(),
            endpoint: "https://api.example/a2a".to_string(),
            feedback_uri: "ipfs://feedback".to_string(),
            feedback_hash: [7; 32],
        };
        let encoded = borsh::to_vec(&instruction).unwrap();
        assert_eq!(
            ReputationInstruction::try_from_slice(&encoded).unwrap(),
            instruction
        );
    }
}
