# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-07-01

### Fixed

- Session creation failed with `Failed to capture URL`. Claude Code renamed the
  remote-control session URL query parameter from `bridge=env_...` to
  `environment=env_...` (2.1.x), so the daemon's URL matcher never matched: in a
  trusted directory the session hung until claude's stdout closed, and in an
  untrusted one claude exited before the URL appeared. The matcher now accepts
  both `bridge=` and `environment=` so it works across Claude Code versions.
- Failure to capture the session URL now surfaces claude's stderr (for example
  `Workspace not trusted`) in the error, instead of a blind
  `stdout closed before URL found`.

## [0.1.0] - 2026-03-24

### Added

- Background daemon that starts, manages, and monitors Claude Code sessions,
  installed via `curl | sh` with a guided `ferlay setup` (relay configuration,
  QR pairing, and a background service on systemd, launchd, or Task Scheduler).
- Flutter mobile app to start sessions, approve tool-use prompts, and monitor
  progress from a paired phone.
- End-to-end encryption between the daemon and the app (X25519 key exchange,
  AES-GCM), with a hosted relay by default and support for self-hosting your own.
- Session controls: start, stop, and list sessions, per-session permission modes,
  and worktree spawn mode.
