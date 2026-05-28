use solana_program::program_error::ProgramError;

#[repr(u32)]
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ManowarError {
    InvalidPda = 1,
    InvalidAccountOwner = 2,
    AccountAlreadyInitialized = 3,
    AccountNotInitialized = 4,
    AccountTooSmall = 5,
    Serialization = 6,
    Unauthorized = 7,
    InvalidMetadataKey = 8,
    MetadataTooLarge = 9,
    UriTooLarge = 10,
    InvalidAgentWallet = 11,
    AgentNotFound = 12,
    InvalidDna = 13,
    AgentNotCloneable = 14,
    CloneCannotBeCloned = 15,
    NoLicensesAvailable = 16,
    AlreadyLicensed = 17,
    NotLicensed = 18,
    SelfFeedback = 19,
    InvalidValueDecimals = 20,
    ValueTooLarge = 21,
    InvalidIndex = 22,
    AlreadyRevoked = 23,
    EmptyUri = 24,
    InvalidUnits = 25,
    InvalidLeasePercent = 26,
    WorkflowNotFound = 27,
    RfaNotOpen = 28,
    InvalidOffer = 29,
    SubmissionNotFound = 30,
    LeaseNotActive = 31,
    TransferFailed = 32,
}

impl From<ManowarError> for ProgramError {
    fn from(error: ManowarError) -> Self {
        ProgramError::Custom(error as u32)
    }
}
