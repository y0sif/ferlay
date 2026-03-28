# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Ferlay, please report it responsibly.

**Do not open a public issue.** Instead, use [GitHub's private security advisory feature](https://github.com/y0sif/ferlay/security/advisories/new) to report the vulnerability.

You can expect an initial response within 48 hours.

## Scope

- Daemon (authentication, pairing, session management)
- Relay server (message routing, WebSocket handling)
- Mobile app (key storage, crypto implementation)
- End-to-end encryption (X25519 + AES-256-GCM)
- Install scripts

## Out of Scope

- Vulnerabilities in upstream dependencies (report those to the upstream project)
- Social engineering attacks
- Denial of service against the hosted relay
