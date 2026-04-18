# Security Policy

## Reporting a Vulnerability

CkredBSD takes security seriously — it is the entire point of this project.

If you find a vulnerability in CkredBSD or in the OpenBSD codebase that we inherit:

1. **Do not open a public issue.** Public disclosure before a patch is available harms users.
2. Send a detailed report to: `ignacio.marambio_z@mail.udp.cl`
3. Include: description, reproduction steps, affected components, and your assessment of severity.
4. We will acknowledge within 48 hours and begin triage immediately.

## What happens next

- We verify the vulnerability with our AI audit pipeline + human review
- We develop and test a patch
- We coordinate disclosure timing with you
- **You receive IMMAC rewards proportional to the severity and quality of your report**

## Severity scale

| Level    | Description                                           | IMMAC reward |
|----------|-------------------------------------------------------|--------------|
| Critical | Remote code execution, privilege escalation, kernel   | Maximum      |
| High     | Local privilege escalation, data exposure             | High         |
| Medium   | Denial of service, information leakage                | Medium       |
| Low      | Minor issues, hardening improvements                  | Base         |

## Our commitment

- We will never penalize responsible disclosure
- We will never demand silence beyond what is necessary to protect users
- Every verified vulnerability report is rewarded, no exceptions
- The full history of vulnerability reports and rewards is public once patched

---

*Finding bugs makes CkredBSD more immaculate. That is worth rewarding.*
