# CkredBSD 🍷

> *Immaculated till the end*

CkredBSD is a security-focused fork of OpenBSD with a philosophy that goes beyond protecting the user from the system — it protects the world from the user, and the world from the system itself becoming a weapon.

**Bidirectional security. Immaculate by design.**

---

## What is CkredBSD?

CkredBSD (from *sacred*, rearranged) is:

- A **fork of OpenBSD** — starting from the most audited OS codebase in existence
- **Progressively rewritten in Rust** — eliminating entire classes of memory vulnerabilities by design
- **Continuously audited by AI** — every commit passes automated security analysis before merge
- **Economically incentivized** — the IMMAC protocol rewards any verifiable contribution to the ecosystem

## The Three Circles

```
┌─────────────────────────────────────────┐
│   Circle 3: The world outside           │
│   ┌─────────────────────────────────┐   │
│   │  Circle 2: The community        │   │
│   │  ┌───────────────────────────┐  │   │
│   │  │  Circle 1: The user       │  │   │
│   │  │       CkredBSD            │  │   │
│   │  └───────────────────────────┘  │   │
│   └─────────────────────────────────┘   │
└─────────────────────────────────────────┘
```

1. **The user is protected** — privacy is a technical guarantee, not a promise
2. **The community is protected from the user** — the system cannot be used as an attack platform
3. **The world is protected from the system** — the architecture itself prevents weaponization

## The Contract

> Between the system and the user: *I protect you, and you accept not to use that protection to harm others.*
>
> Between the user and the community: *you belong to an ecosystem that cares for you, and you commit to caring for it.*
>
> Between the community and the world: *we build security that benefits those who use the system and those who do not.*

## IMMAC — The Economic Protocol

IMMAC (from *immaculated*) is the native token of the CkredBSD ecosystem. It rewards any verifiable contribution:

- Finding and documenting a security vulnerability
- Writing the patch that fixes it
- Adding hardware or software compatibility
- Writing documentation
- Auditing and certifying an external package
- Any other contribution the community considers valuable and can verify

**If you contribute, you are rewarded. Automatically. Proportionally. Publicly.**

---

## Repository Structure

```
ckredbsd/
├── docs/           # Manifesto, architecture docs, RFCs
├── audit/          # AI audit pipeline, scripts, reports
├── src/            # Source — OpenBSD fork base + Rust components
├── tools/          # Security tooling, analysis scripts
└── IMMAC/          # Protocol specification and smart contracts
```

## Current Status

**Phase 1 — Foundations**

- [x] Manifesto v0.2 published
- [x] Repository initialized
- [ ] OpenBSD source integrated
- [ ] AI audit pipeline operational
- [ ] First Rust components

---

## How to Contribute

Read the [Manifesto](docs/MANIFESTO.md) first. Then:

1. Fork the repository
2. Make your contribution
3. Submit a pull request with a clear description of what you did and why it matters
4. The community reviews and verifies
5. If accepted, IMMAC rewards are distributed automatically

Every contribution matters. Code, documentation, audits, translations — if the community can verify it improved the system, it is rewarded.

---

## License

CkredBSD inherits the BSD license from OpenBSD. All new code is BSD-licensed unless explicitly stated otherwise. The IMMAC protocol specification is licensed under CC0.

---

*Security is not a wall. It is a contract.*
*Secure for those who use it. Secure for those who do not.*
