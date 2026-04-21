# IMMAC Protocol Specification

*IMMAC — from "immaculated" — is the economic coordination layer of CkredBSD.*

## Purpose

IMMAC aligns economic incentives with the security and quality of CkredBSD.
It rewards any verifiable contribution to the ecosystem, automatically and proportionally.

IMMAC is not a speculative cryptocurrency. It is a coordination mechanism.

## Core principles

1. **Any verifiable contribution is eligible** — the community defines and verifies what counts
2. **Rewards are automatic** — no manual approval required for verified contributions
3. **Rewards are proportional** — impact determines magnitude
4. **All transactions are public** — full history, always
5. **No single entity controls distribution** — consensus required for rule changes

## Contribution categories

| Category          | Examples                                              | Verification method        |
|-------------------|-------------------------------------------------------|---------------------------|
| Security          | CVE found, patch written, audit completed             | Human review + AI confirm |
| Compatibility     | Driver added, package certified, hardware supported   | CI pass + community vote  |
| Documentation     | Guide written, translation completed, RFC drafted     | Community review           |
| Creativity        | Architectural improvement, new tool, novel approach   | Community vote             |
| Infrastructure    | CI improvement, tooling, build system                 | Maintainer review          |
| Other             | Anything the community verifies as valuable           | Community consensus        |

## Reward calculation

```
reward = base_value × impact_multiplier × quality_factor

base_value:        defined per category by community governance
impact_multiplier: 1.00 (baseline) to 5.00 (critical) — scaled by 100 on-chain (100–500)
quality_factor:    1.00 (baseline) to 5.00 (exceptional) — scaled by 100 on-chain (100–500)
```

> Both multipliers are encoded as integers scaled by 100 in the smart contract
> (e.g. 125 = 1.25×). The maximum allowed value per factor is 500 (5×), enforced
> on-chain by `MAX_MULTIPLIER`. This cap prevents reward inflation in the event of
> a compromised verifier.

## Architecture

IMMAC logic runs in **userland**, not in the kernel.

```
Kernel layer
    └── cryptographic verification module only
         (verifies signatures, maintains integrity log)

Userland layer (dedicated jail)
    └── IMMAC daemon
         ├── contribution tracking
         ├── reward calculation
         ├── on-chain settlement (via established blockchain)
         └── public audit log
```

The kernel never executes economic logic. It only verifies.

## Blockchain layer

IMMAC uses an established, audited blockchain as settlement layer.
We do not build a new chain. The specific chain is determined by community governance
before mainnet launch.

Requirements for the settlement chain:
- Open source and audited
- Low transaction fees
- Proven track record (minimum 3 years)
- Smart contract support

## Governance

Changes to IMMAC rules require:
- Public proposal with 14-day comment period
- Supermajority approval (>2/3) from verified contributors
- 30-day delay before implementation
- All changes are permanently recorded

Founders have no special privileges over the protocol once launched.

---

*If you contribute, you are rewarded. That is the entire design.*
