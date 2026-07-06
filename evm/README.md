# EVM Contracts

The EVM implementation of the Manowar agent economy. Thirteen contracts that implement [ERC-8004](https://eips.ethereum.org/EIPS/eip-8004) (Trustless Agents) and [ERC-7401](https://eips.ethereum.org/EIPS/eip-7401) (Nestable NFTs) — and build the full agentic economy on top.

The ERC-8004 reference implementation provides three standalone registries: identity, reputation, and validation. This suite extends them into a complete on-chain agent marketplace. Agents are NFTs with DNA, licensing, and payment wallets. Workflows are nestable NFTs that compose multiple agents and split payments. Agents can be cloned, warped cross-chain, leased, procured via escrow, rated, validated, and royalty-bearing. All contracts deploy deterministically via CREATE2, giving them identical addresses on every EVM chain.

## Contracts

### Core

| Contract | Path | Purpose | Standards |
|----------|------|---------|-----------|
| `AgentFactory` | `compose/agentfactory.sol` | Agent identity registry, ERC-721 NFT, DNA, licensing, agent wallet, metadata | ERC-8004, ERC-721, ERC-165, ERC-1271 |
| `Workflow` | `compose/workflow.sol` | Nestable workflow NFTs that compose agents, USDC payment splitting, leasing config | ERC-7401, ERC-721, ERC-3009 |
| `Reputation` | `compose/reputation.sol` | Signed fixed-point feedback with tags, revocation, responses, WAD-normalized summaries | ERC-8004 |
| `Validation` | `compose/validation.sol` | Objective validation requests and validator responses | ERC-8004 |

### Extensions

| Contract | Path | Purpose |
|----------|------|---------|
| `Clone` | `compose/clone.sol` | Fork `cloneable` agents with new parameters (chain, price, model, licenses) |
| `Warp` | `compose/warp.sol` | Import external agents with 10/10/80 royalty split and 1-year creator claim window |
| `Lease` | `compose/lease.sol` | Time-based workflow leasing with creator/leaser fee split (max 20% creator) |
| `RFA` | `compose/rfa.sol` | Request-for-agent escrow: publisher locks USDC, creators submit agents, publisher accepts one |
| `Royalties` | `compose/royalties.sol` | EIP-2981 royalty management with per-token overrides and default |
| `Distributor` | `compose/distributor.sol` | Generic fee distribution (native + ERC-20) by basis-point shares |

### Orchestration

| Contract | Path | Purpose |
|----------|------|---------|
| `AgentManager` | `compose/agentmanager.sol` | Central registry, pause switch, convenience methods for clone/warp/lease |
| `Delegation` | `compose/delegation.sol` | Routes AgentManager calls to Clone/Warp/Lease modules |

### Utilities

| Contract | Path | Purpose |
|----------|------|---------|
| `Utils` | `compose/utils.sol` | x402 pay-per-use pricing: base model cost + agent costs + x402 cost |

> The `dispenser/` directory contains a CREATE2 factory and USDC faucet for onboarding — not part of the core protocol.

All interfaces are in `compose/interfaces/`.

## Architecture

```
                 AgentFactory
               (ERC-8004 identity)
                    │
        ┌───────────┼───────────────┐
        │           │               │
   consumeLicense  mintClone    mintWarped
        │           │               │
        ▼           ▼               ▼
     Workflow     Clone           Warp
   (ERC-7401)   (forking)    (cross-chain)
        │
   ┌────┴────┐
   │         │
  RFA      Lease
 (escrow)  (rental)

  Reputation ──► AgentFactory (reads agent existence)
  Validation ──► AgentFactory (reads agent existence)

  AgentManager ──► Delegation ──► Clone / Warp / Lease
  Royalties     (standalone, EIP-2981)
  Distributor   (standalone, fee splitting)
  Utils         (pricing, reads Workflow)
```

**AgentFactory** is the root: it owns agent identity, DNA uniqueness, the licensing ledger, and the authorized-consumer allowlist. **Workflow** is the composition layer: it nests agents via `consumeLicense`, splits USDC payments on mint (10% treasury, 90% to agent creators proportionally), and integrates bidirectionally with RFA and Lease. The extension modules (Clone, Warp, Lease, RFA) are authorized consumers of AgentFactory — only they can call `mintClone`, `mintWarped`, `consumeLicense`, and `revokeLicense`.

## Key Concepts

### Agents (ERC-8004)
Agents are ERC-721 NFTs with a unique `dnaHash`, license supply/price, creator fee, cloneability flag, and an `agentCardUri` pointing to an off-chain Agent Card. Every agent gets `x402` metadata (set to `true` on mint) and a reserved `agentWallet` entry (defaults to owner, settable via EIP-712 signature, auto-cleared on transfer). DNA hashes are globally unique — no two agents share the same hash. `register()` is a lightweight entry point that auto-derives DNA; `mintAgent()` accepts full parameters.

### Workflows (ERC-7401)
Workflows are nestable NFTs that own agent NFTs. Minting a workflow pulls USDC from the minter, sends 10% to treasury, and distributes 90% proportionally to each nested agent's creator. `mintWorkflowWithAuth` does the same gaslessly via ERC-3009 `transferWithAuthorization` — one off-chain signature, no `approve` step. Workflows support a propose-accept pattern for child nesting, maintain marketplace lists (complete / has-active-RFA) with O(1) removal, and track units minted vs. total for consumption counting.

### Licensing
Each agent has a license supply (`0` = unlimited) and a per-license price. When a workflow nests an agent, `consumeLicense` increments the minted count, records the (agent, workflowContract, workflowId) tuple, and reverts if the cap is reached. Licenses can be revoked when an agent is removed. Only authorized consumers (Clone, Warp, Workflow) can consume or revoke licenses.

### Cloning
`cloneable` agents can be forked via `Clone.cloneAgent` with new parameters (chain ID, license price, model, license count). A new DNA hash is derived from the original hash + the new parameters. Clones cannot be cloned again — the hierarchy is one level deep.

### Warping
External agents (from other chains, Web2 APIs, or any external system) can be imported via `Warp.warpAgent`. The warper provides an `originalAgentHash` and optional `originalCreator` address. Royalties on warped agents: 80% warper, 10% treasury, 10% original creator. If the creator is unknown, their 10% is held with a 1-year claim window — after which it goes to treasury. Double-warping the same external hash is prevented.

### RFA (Request-For-Agent)
An escrow-based marketplace for missing capabilities. A workflow owner creates an RFA with required skills and an offer amount (USDC escrowed at creation). Agent creators submit agents. The publisher accepts one — escrow releases to the chosen agent's creator, and the workflow's RFA flag clears. Publishers can cancel to refund. One active RFA per workflow.

### Leasing
Workflows with `leaseEnabled` can be leased for a duration (in days). The workflow creator gets up to 20% of lease fees; the leaser gets the remainder. One active lease per workflow. Anyone can call `expireLeaseIfNeeded` to transition an expired lease.

### Reputation (ERC-8004)
Clients give feedback with a signed fixed-point `value` + `valueDecimals` (0-18), two filterable tags, an endpoint, and an off-chain URI/hash anchor. Self-feedback is blocked (owner or authorized operator cannot rate their own agent). Feedback can be revoked (soft-delete). Anyone can append responses. `getSummary` computes a WAD-normalized average across mixed-precision feedback, returning the result in the mode (most common) decimal precision. `readAllFeedback` supports filtering by client addresses, tags, and revoked status.

### Validation (ERC-8004)
Anyone can request validation of an agent's task (with a `validatorType`, `taskHash`, and evidence URI). Any address can submit a validation response (pass/fail + evidence hash/URI). Validation trust is off-chain / reputation-based — the registry is an open anchor layer.

### Royalties (EIP-2981)
Per-token royalty overrides with a default fallback. `royaltyInfo(tokenId, salePrice)` returns the receiver and royalty amount. Fee numerator is in basis points (max 10000 = 100%).

### Distribution
Generic fee splitter for native ETH and ERC-20 tokens. Pass an array of `(recipient, share)` pairs (shares must sum to 10000). The last recipient gets the rounding remainder. Includes convenience methods for warp royalties and lease fee splits.

### x402 Pricing
`Utils.calculateUsagePrice` computes the per-call price of a workflow: `baseModelCost + totalAgentPrice + x402Price`. Base model cost is `BASE_PRICE_PER_TOKEN × modelPriceMultiplier × estimatedTokens / 100` (multiplier scaled by 100, e.g. 663 = 6.63×). `calculateMaxPrice` uses `MAX_TOKENS_PER_CALL = 100000`.

## Build & Test

```sh
forge build          # compile
forge test           # run tests
forge fmt            # format
forge snapshot       # gas snapshots
```

## Deployment

All contracts are deployed deterministically via [Arachnid's universal CREATE2 deployer](https://github.com/Arachnid/create2deployer) (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) using versioned salts. This produces **identical contract addresses on every EVM chain** — same bytecode + same salt + same deployer = same address, regardless of network. The deployer exists on virtually every EVM chain, so no per-chain configuration is needed.

The deployment script is idempotent — safe to re-run as new chains are added. It predicts each contract's address, checks for existing code, and skips already-deployed contracts.

See the [Solana contracts](../solana) for the Solana implementation.
