# Manowar Solana Contracts

This workspace is the Solana-native Manowar protocol implementation. It avoids
the EVM one-contract-per-feature shape where that would create unnecessary CPI
and account pressure, but keeps the ERC8004 surfaces split by responsibility.

## Layout

- `crates/manowar`: shared seeds, account serialization, metadata rules,
  ERC8004 agent state, fixed-point helpers, and SPL-token CPI helpers.
- `programs/identity`: agent identity registry, DNA markers, `x402` metadata,
  reserved `agentWallet`, owner transfer with wallet reset, clone, and warp.
- `programs/reputation`: raw feedback anchors for the native API/SDK feedback
  loop using signed fixed-point `value` + `valueDecimals`, tags, endpoint,
  URI/hash, revocation, and responses.
- `programs/validation`: objective validation requests and validator responses.
- `programs/market`: workflows, market-owned license counters, SPL-token
  license payments, RFA escrow, leases, and royalty records.

## Verification

```sh
cargo test --workspace --all-targets
cargo test -p identity --features no-entrypoint
cargo test -p reputation --features no-entrypoint
cargo test -p validation --features no-entrypoint
cargo test -p market --features no-entrypoint
cargo build --workspace --release
```
