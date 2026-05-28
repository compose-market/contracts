use manowar::transfer_tokens;
use solana_program::{account_info::AccountInfo, entrypoint::ProgramResult};

use crate::state::TREASURY_FEE_PERCENT;

pub fn pay_license<'a>(
    token_program: &AccountInfo<'a>,
    payer_token: &AccountInfo<'a>,
    treasury_token: &AccountInfo<'a>,
    creator_token: &AccountInfo<'a>,
    payer: &AccountInfo<'a>,
    price: u64,
) -> ProgramResult {
    if price == 0 {
        return Ok(());
    }
    let treasury = price.saturating_mul(TREASURY_FEE_PERCENT) / 100;
    let creator = price.saturating_sub(treasury);
    transfer_tokens(token_program, payer_token, treasury_token, payer, treasury)?;
    transfer_tokens(token_program, payer_token, creator_token, payer, creator)
}

pub fn split_lease(amount: u64, creator_percent: u8) -> (u64, u64) {
    let creator = amount.saturating_mul(u64::from(creator_percent)) / 100;
    (creator, amount.saturating_sub(creator))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn splits_license_price_like_evm_market() {
        let price = 1_000_000;
        let treasury = price * TREASURY_FEE_PERCENT / 100;
        assert_eq!(treasury, 100_000);
    }

    #[test]
    fn splits_lease_fees() {
        assert_eq!(split_lease(1_000, 20), (200, 800));
    }
}
