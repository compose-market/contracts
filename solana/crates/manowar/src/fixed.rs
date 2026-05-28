use crate::ManowarError;

pub const MAX_VALUE_DECIMALS: u8 = 18;
pub const MAX_ABS_VALUE: i128 = 100_000_000_000_000_000_000_000_000_000_000_000_000;

pub fn validate_fixed(value: i128, decimals: u8) -> Result<(), ManowarError> {
    if decimals > MAX_VALUE_DECIMALS {
        return Err(ManowarError::InvalidValueDecimals);
    }
    if !(-MAX_ABS_VALUE..=MAX_ABS_VALUE).contains(&value) {
        return Err(ManowarError::ValueTooLarge);
    }
    Ok(())
}

pub fn to_wad(value: i128, decimals: u8) -> Result<i128, ManowarError> {
    validate_fixed(value, decimals)?;
    let factor = 10_i128.pow(u32::from(MAX_VALUE_DECIMALS - decimals));
    value.checked_mul(factor).ok_or(ManowarError::ValueTooLarge)
}

pub fn from_wad(value: i128, decimals: u8) -> Result<i128, ManowarError> {
    if decimals > MAX_VALUE_DECIMALS {
        return Err(ManowarError::InvalidValueDecimals);
    }
    let factor = 10_i128.pow(u32::from(MAX_VALUE_DECIMALS - decimals));
    Ok(value / factor)
}

pub fn average(values: &[(i128, u8)], output_decimals: u8) -> Result<i128, ManowarError> {
    if values.is_empty() {
        return Ok(0);
    }
    let mut sum = 0_i128;
    for (value, decimals) in values {
        sum = sum
            .checked_add(to_wad(*value, *decimals)?)
            .ok_or(ManowarError::ValueTooLarge)?;
    }
    from_wad(sum / values.len() as i128, output_decimals)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn averages_mixed_decimal_feedback() {
        let avg = average(&[(45, 1), (5, 0)], 1).unwrap();
        assert_eq!(avg, 47);
    }

    #[test]
    fn rejects_excess_decimals() {
        assert_eq!(
            validate_fixed(1, 19),
            Err(ManowarError::InvalidValueDecimals)
        );
    }
}
