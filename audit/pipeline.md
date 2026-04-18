# CkredBSD AI Audit Pipeline

Every commit to the CkredBSD base system passes through this pipeline
before it can be merged. No exceptions.

## Pipeline stages

```
New commit
    │
    ▼
1. Static analysis (CodeQL + clang analyzer)
    │   Fast, catches known patterns
    │
    ▼
2. AI audit (local model via Ollama)
    │   Contextual analysis across subsystems
    │   Detects semantic vulnerabilities
    │   Generates test cases
    │
    ▼
3. AI escalation (cloud model for complex cases)
    │   For findings that require deeper reasoning
    │   Triggered automatically by severity threshold
    │
    ▼
4. Human review
    │   Required for all Capa 0 changes
    │   AI findings are presented with context
    │   Human makes final decision
    │
    ▼
5. Merge + public audit log entry
```

## What the AI looks for

- Buffer overflows and memory safety violations
- Use-after-free patterns
- Race conditions in concurrent code
- Integer overflow in size calculations
- Privilege escalation paths
- Network stack vulnerabilities
- Input parsing weaknesses
- Interaction bugs between subsystems (hardest for static tools)

## Audit log

Every audit run produces a public log entry:
- Commit hash
- Files analyzed
- Findings (severity, description, location)
- Disposition (fixed, false positive, accepted risk)
- Human reviewer

All logs are stored in `audit/logs/` and are immutable once committed.

## Running the pipeline locally

```bash
# Install dependencies
./tools/audit-setup.sh

# Run full pipeline on a diff
./audit/run.sh --diff HEAD~1..HEAD

# Run on a specific subsystem
./audit/run.sh --path sys/netinet/
```

### Strict parsing behavior

The audit runner now treats unparseable model output as a hard failure.
If the model output doesn't match either:

- `NO_FINDINGS`, or
- a structured finding with all required fields

the run exits non-zero and appends a parser-error section to the report.

Use `--allow-parse-errors` only for exploratory debugging.

## Model quality benchmarking

Use the ground-truth dataset in `audit/benchmark/` to measure detection quality:

```bash
./audit/benchmark/run.sh
```

The benchmark writes a report in `audit/logs/` with:
- confusion-matrix counts (TP/TN/FP/FN)
- precision, recall, F1, and accuracy
- parse-error diagnostics

## Hardware requirements

The local AI stage requires:
- GPU with 8GB+ VRAM (AMD RDNA4 / NVIDIA RTX 3000+)
- ROCm or CUDA support
- Ollama installed and configured

Recommended model: `qwen2.5-coder:14b` or `codestral:22b`
