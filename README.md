# Manowar Contracts

On-chain contracts for the Manowar agent economy — the most complete implementation of [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) (Trustless Agents) and [ERC-7401](https://eips.ethereum.org/EIPS/eip-7401) (Nestable NFTs), deployed across two virtual machines.

The ERC-8004 reference implementation ships three registries: identity, reputation, and validation. This repo implements all three and builds the full agentic economy on top — agent composition, licensing, cloning, cross-chain warping, request-for-agent escrow, leasing, royalties, fee distribution, and x402 pay-per-use pricing — on both EVM and Solana.

## Layout

| Directory | Stack | Description |
|-----------|-------|-------------|
| [`evm/`](./evm) | Solidity / Foundry | 13 core contracts + interfaces, deterministic CREATE2 deployment |
| [`solana/`](./solana) | Rust / Solana | 4 programs + shared `manowar` crate, no inter-program CPI |

## Architecture

The same ERC-8004 agent economy model, implemented in two idioms:

| Surface | EVM contract(s) | Solana program |
|---------|-----------------|----------------|
| Agent identity (ERC-8004) | `AgentFactory` | `identity` |
| Subjective trust (ERC-8004) | `Reputation` | `reputation` |
| Objective trust (ERC-8004) | `Validation` | `validation` |
| Composition & market (ERC-7401) | `Workflow`, `Clone`, `Warp`, `Lease`, `RFA`, `Royalties`, `Distributor` | `market` |
| Orchestration | `AgentManager`, `Delegation` | — |
| x402 pricing | `Utils` | — |

## Build

```sh
# EVM
cd evm && forge build

# Solana
cd solana && cargo build --workspace --release
```

## License

MIT.
