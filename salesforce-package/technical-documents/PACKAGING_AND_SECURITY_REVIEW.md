# Packaging and Security Review Checklist (RouteLogic Enhanced v4)

## Packaging (2GP)
- Ensure `sfdx-project.json` contains a 2GP package alias (e.g., `RouteLogicEnhanced`).
- Create version via GitHub Actions workflow `Package 2GP` with inputs:
  - versionName: semantic tag (e.g., v4.0.0-build.1)
  - tag: git ref/branch (default current)
  - skipValidation: true/false
  - installKey: optional (blank to bypass)
- Dev Hub auth secrets required (choose one):
  - `DEVHUB_AUTH_URL` (SFDX auth URL)
  - OR JWT: `SFDX_CLIENT_ID`, `SFDX_USERNAME`, `SFDX_JWT_KEY`, `SFDX_LOGIN_URL`

## Security Review readiness
- CRUD/FLS enforced: `WITH SECURITY_ENFORCED`, `Security.stripInaccessible(System.AccessType, ...)`.
- Timing‑safe comparisons for signatures/hashes via `RouteLogicSecurityUtils.timingSafeEquals`.
- LWC security: no `innerHTML`, no unsafe expressions; use base components.
- External endpoints: Named Credentials/External Credentials only. No hardcoded secrets.
- Logging: PII masked; no secrets logged; Platform Events for critical alerts.
- CSP Trusted Sites: only required domains for Ada/Intercom; no wildcards.

## Submission artifacts
- Security Architecture and Data Flow diagrams.
- Endpoint inventory (domain, purpose, data exchanged).
- Installation and Post‑install guide (Named Credentials, CSP).
- Accessibility statement (WCAG 2.1 AA) and testing notes.
- Test org credentials (Security Review Login) with perms, sample data, and test script.

## CI/CD
- PR CI runs static scans (PMD via sfdx‑scanner) and LWC ESLint.
- Optional Apex tests deploy when org secrets are configured.


