# Manowar Solana Contracts

The Solana-native implementation of the Manowar agent economy — the same [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) surfaces (identity, reputation, validation) and composition layer ([ERC-7401](https://eips.ethereum.org/EIPS/eip-7401)), built with Solana idioms rather than ported one-to-one.

The EVM suite uses one contract per feature. On Solana, that shape would create unnecessary CPI and account pressure. Instead, this implementation consolidates the market layer into a single program, avoids all inter-program CPI via shared PDA seeds and cross-program account reads, and tracks licensing on-ledger (no SPL NFTs).

## Layout

| Crate | Type | Purpose |
|-------|------|---------|
| `crates/manowar` | Library | Shared seeds, account serialization, fixed-point math, metadata rules, SPL-token CPI |
| `programs/identity` | Program | Agent identity registry, DNA markers, x402/agentWallet metadata, clone, warp |
| `programs/reputation` | Program | Signed fixed-point feedback, tags, revocation, responses |
| `programs/validation` | Program | Objective validation requests and validator responses |
| `programs/market` | Program | Workflows, licensing, RFA escrow, leases, royalties |

## Architecture

The four programs interconnect **without program-to-program CPI**. Cross-program linkage is done via:

1. **Shared PDA seed conventions** — the `AGENT` seed (`b"agent"`) + little-endian `agent_id` is the canonical agent PDA, derived by the `identity` program. Other programs re-assert the same PDA against the identity program's ID.
2. **Cross-program account reads** — other programs read identity-owned `Agent` accounts directly via `manowar::account::read(agent_account, identity_program.key)`, which checks ownership. No CPI required.

The only CPI in the suite is **SPL Token transfers** inside the `market` program (license payments, RFA escrow, lease distribution).

```
    identity (owns Agent + Dna + Warp records)
         │
         │  cross-program reads (no CPI)
         │
    ┌────┴────┬──────────┐
    │         │          │
reputation  validation  market
(feedback)  (checks)    (workflows, licenses,
                          RFA, leases, royalties)
                              │
                              │  SPL Token Transfer CPI only
                              │
                         token program
```

The shared `manowar` crate provides the foundation: PDA seed constants, length-prefixed borsh serialization (4-byte LE header + payload), fixed-point math (`to_wad`/`from_wad`/`average` for mixed-decimal aggregation), ERC-8004 metadata rules (reserved `agentWallet` key, `x402` flag), and hand-rolled SPL Token Transfer CPI.

## Key Design Decisions

- **No inter-program CPI.** Cross-program linkage via shared PDA seeds + direct account reads. Cheap on Solana, avoids CPI overhead.
- **Consolidated market program.** Workflows, licensing, RFA escrow, leases, and royalties live in one program, split into modules (`workflow`, `payment`, `rfa`, `lease`, `royalty`) for code organization — not on-chain separation.
- **On-ledger licensing.** `License` + `LicenseCounter` PDAs track licensing — no SPL NFTs minted. `licenses == 0` means unlimited.
- **Hand-rolled SPL Token CPI.** Only the `Transfer` instruction (discriminator 3) is implemented. No `spl-token` crate dependency.
- **Length-prefixed borsh.** Every account uses a 4-byte LE length header + borsh payload, with generous fixed allocations. `has_state` distinguishes uninitialized PDAs.
- **x402 + agentWallet.** `x402` is a default metadata flag (`[1]`) on every agent. `agentWallet` is a reserved metadata key (32-byte `Pubkey`) — only the identity program's dedicated instructions can mutate it. On transfer, `agent_wallet` resets to zero.
- **Warp as cross-chain bridge.** Imports external (e.g. EVM-origin) agents with `original_hash`/`original_creator` and a 1-year royalty claim window.

## PDA Seeds

| Seed | Program | Derivation |
|------|---------|------------|
| `REGISTRY` | identity, validation, market | `[REGISTRY]` (per-program) |
| `AGENT` | identity (owns) | `[AGENT, u64_seed(agent_id)]` |
| `AGENT` | reputation, validation, market | re-asserted against identity program ID |
| `DNA` | identity | `[DNA, dna_hash]` |
| `WARP` | identity | `[WARP, original_hash]` |
| `FEEDBACK_INDEX` | reputation | `[FEEDBACK_INDEX, agent_seed, client]` |
| `FEEDBACK` | reputation | `[FEEDBACK, agent_seed, client, u64_seed(index)]` |
| `RESPONSE` | reputation | `[RESPONSE, agent_seed, client, feedback_seed, responder, u64_seed(response_index)]` |
| `REQUEST` | validation | `[REQUEST, u64_seed(request_id)]` |
| `RESPONSE` | validation | `[RESPONSE, u64_seed(request_id), u64_seed(response_count)]` |
| `WORKFLOW` | market | `[WORKFLOW, u64_seed(workflow_id)]` |
| `COUNTER` | market | `[COUNTER, u64_seed(agent_id)]` |
| `LICENSE` | market | `[LICENSE, agent_seed, workflow_seed]` |
| `RFA` | market | `[RFA, u64_seed(rfa_id)]` |
| `SUBMISSION` | market | `[SUBMISSION, rfa_seed, agent_seed]` |
| `LEASE` | market | `[LEASE, u64_seed(lease_id)]` |
| `ROYALTY` | market | `[ROYALTY, u64_seed(token_id)]` |

## Build & Test

```sh
cargo test --workspace --all-targets
cargo test -p identity --features no-entrypoint
cargo test -p reputation --features no-entrypoint
cargo test -p validation --features no-entrypoint
cargo test -p market --features no-entrypoint
cargo build --workspace --release
```

See the [EVM contracts](../evm) for the Solidity implementation.
