# ferlay — Project Conventions

Remote control for Claude Code: a background daemon plus a Flutter app that start,
manage, and approve Claude Code sessions from your phone, brokered by a relay.

## Environment

- OS: Arch Linux
- Shell: fish (no `&&` chaining, use `;`; no `export`, use `set -x`)
- Editor: nvim
- Rust: managed with `cargo`; Flutter app managed with `flutter`

## Project Structure

Cargo workspace (`relay`, `daemon`, `shared`) plus a Flutter app:

```
daemon/     # ferlay daemon + CLI (package `ferlay-daemon`, binary `ferlay`).
            #   Spawns `claude remote-control`, captures the session URL
            #   (capture.rs), relays it to the app. setup.rs = `ferlay setup`.
relay/      # WebSocket relay server that brokers daemon <-> app (Docker-deployed).
shared/     # `ferlay-shared`: message types shared by daemon and relay.
app/        # Flutter mobile app (Dart under app/lib).
scripts/    # install.sh / install.ps1 (fetch the latest GitHub release).
deploy/     # relay deployment assets.
```

## Build Commands

```fish
cargo build --release -p ferlay-daemon              # build the daemon binary
cargo test --workspace                              # run all Rust tests
cargo test -p ferlay-daemon --bin ferlay-daemon     # daemon tests (no lib target)
cargo clippy --workspace --all-targets -- -D warnings   # lint (strict)
cargo fmt --all -- --check                          # check formatting
```

## Running Locally

```fish
ferlay setup                     # interactive: relay config, QR pairing, service install
ferlay daemon                    # run the daemon in the foreground
systemctl --user status ferlay   # the installed background service
journalctl --user -u ferlay -f   # follow daemon logs (session capture errors show here)
```

To test a local build against the running service: build, stop the service, copy
`target/release/ferlay-daemon` over `~/.local/bin/ferlay`, restart the service.

## CI Checks

There is no CI workflow that gates pull requests yet (only `release.yml` and
`docker-relay.yml`), and the tree is not currently rustfmt-clean, so **run the checks
locally before pushing** rather than relying on CI:

```fish
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo build --release -p ferlay-daemon
```

**Always commit `Cargo.lock` alongside `Cargo.toml` changes.** The daemon is a binary
crate; the lock file keeps release builds reproducible.

## Releasing a New Version

The GitHub release is driven by pushing a `v*` tag: `release.yml` builds the daemon for
five targets, the Flutter APK, and the `ferlay-relay` Docker image, and publishes the
release with those assets. Steps:

1. **Bump version** in `daemon/Cargo.toml` and refresh the lock file
   (`cargo update -p ferlay-daemon --precise <VERSION>`). Bump `relay`/`shared` only if
   they changed; bump `app/pubspec.yaml` only for an app release.
2. **Add a CHANGELOG entry**: a `## [<VERSION>] - <DATE>` section in `CHANGELOG.md`
   (Keep a Changelog format).
3. **Run the CI checks locally** (see above). Include `Cargo.lock` in the bump commit.
4. **Commit** `chore(release): v<VERSION>` and land it on `main`.
5. **Tag and push**: `git tag v<VERSION>; git push origin v<VERSION>`. Watch the run with
   `gh run watch` and confirm it goes green.
6. **Add release notes** (`action-gh-release` publishes an empty body):
   `gh release edit v<VERSION> --notes-file <notes>`. House style, one bullet per change:
   - A `## Highlights` section with a bold-titled bullet per change, referencing the
     issue/PR number(s) and **crediting the reporter or author inline**
     (`Thanks @user for the report.` / `for the PR.`). Always thank whoever raised the
     issue or sent the fix.
   - An `## Install / Upgrade` block: `curl -sSL https://ferlay.dev/install.sh | sh`,
     `yay -S ferlay-bin`, `brew install y0sif/tap/ferlay`.
   - A `**Full Changelog**: https://github.com/y0sif/ferlay/compare/v<PREV>...v<VERSION>`
     link.
7. **Update the AUR package** (`~/Projects/ferlay-bin`): set `pkgver=<VERSION>`, update
   `sha256sums_x86_64` / `sha256sums_aarch64` from the new Linux tarballs
   (`sha256sum ferlay-daemon-linux-*.tar.gz`), regenerate `.SRCINFO`
   (`makepkg --printsrcinfo > .SRCINFO`), commit, and push.
8. **Update the Homebrew tap** (`~/Projects/homebrew-tap/Formula/ferlay.rb`): set
   `version "<VERSION>"` and the four `sha256` values (macOS + Linux, arm64 + x86_64),
   commit, and push.

## Packaging

Packaging files live in separate repos, not here:

- **AUR**: `ferlay-bin` (binary package that downloads the release tarball), pushed to
  `ssh://aur@aur.archlinux.org/ferlay-bin.git`.
- **Homebrew**: `y0sif/homebrew-tap`, `Formula/ferlay.rb` (macOS + Linux bottles from the
  release tarballs).
- **Installer**: `scripts/install.sh` and `install.ps1` fetch the latest GitHub release
  dynamically, so they need no per-release edit. The `gh-pages` branch serves them at
  `ferlay.dev` (via CNAME); mirror changes there manually if the scripts change.
- **crates.io**: not published (the daemon depends on `ferlay-shared` by path). No
  `flake.nix` either.
