# Ferlay — Owner TODO List

## Placeholders to Fill

### 1. Replace `OWNER` with your GitHub username
- `scripts/install.sh` — GitHub Releases download URL
- `scripts/install.ps1` — GitHub Releases download URL
- `.github/workflows/release.yml` — Docker image name
- `.github/workflows/docker-relay.yml` — Docker image name
- `deploy/docker-compose.yml` — image reference
- `README.md` — any GitHub links

### 2. Replace `relay.ferlay.dev` once you have your domain
- `daemon/src/main.rs` — `DEFAULT_RELAY_URL` constant
- `deploy/Caddyfile` — domain placeholder
- `docs/quick-start.md` and `docs/self-hosting.md`

## Deployment Tasks

### 3. Get domain
Register `ferlay.dev` (or your preferred domain).

### 4. Deploy hosted relay
Using Fly.io or a VPS:
- Point `relay.ferlay.dev` DNS to your server
- Use `deploy/docker-compose.yml` + `deploy/Caddyfile` with your domain
- Or deploy directly on Fly.io with `relay/Dockerfile`

### 5. Create first GitHub Release
Tag with `v0.1.0` — the release workflow builds binaries for all platforms + APK automatically.

### 6. Flutter app distribution
- **APK**: Built automatically by the release workflow, attached to GitHub Release
- **Google Play**: Create developer account ($25), upload AAB from `flutter build appbundle --release`
- **iOS**: Apple Developer account ($99/yr), build with Xcode, submit to App Store

### 7. Test the three modes end-to-end
- `make local` — local mode on your machine
- Self-hosted — deploy relay on a test VPS, connect daemon with `--relay wss://your-vps/ws`
- Hosted — once relay.ferlay.dev is live, just `ferlay daemon` with default URL

## Optional Polish

### 8. App icon and splash screen
Design and set in `app/android/` and `app/ios/`.

### 9. Uptime monitoring
Set up UptimeRobot (free) for `relay.ferlay.dev/health`.

### 10. AUR package
If you want Arch Linux users to install via `yay -S ferlay`.
