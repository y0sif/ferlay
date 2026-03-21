# Self-Hosting the Ferlay Relay

The Ferlay relay server is a lightweight WebSocket router that connects your daemon to the mobile app. Even though all message payloads are end-to-end encrypted (the relay cannot read them), you may prefer to host your own relay for full control over availability and metadata.

## Quick Start (Docker Compose + Caddy)

This is the recommended approach. Caddy handles TLS automatically via Let's Encrypt.

### Prerequisites

- A VPS with Docker and Docker Compose installed
- A domain name with a DNS A record pointing to your VPS IP

### Steps

1. Copy the `deploy/` directory to your server (or clone the repo):
   ```sh
   scp -r deploy/ user@your-server:~/ferlay-deploy/
   cd ~/ferlay-deploy
   ```

2. Set your domain:
   ```sh
   export DOMAIN=relay.yourdomain.com
   ```
   Or edit `Caddyfile` directly and replace `relay.example.com` with your domain.

3. Start the services:
   ```sh
   docker compose up -d
   ```

4. Verify it is running:
   ```sh
   curl https://relay.yourdomain.com/health
   # Should return: ok

   curl https://relay.yourdomain.com/stats
   # Should return JSON with version, uptime, connected devices, etc.
   ```

Caddy will automatically obtain and renew TLS certificates from Let's Encrypt.

## Manual Setup (Binary + Reverse Proxy)

For users who prefer running the relay binary directly without Docker.

### Install the binary

Download from GitHub Releases, or build from source:
```sh
cargo install furlay-relay
```

### Run as a systemd service

1. Create a dedicated user:
   ```sh
   sudo useradd -r -s /bin/false ferlay
   ```

2. Copy the binary:
   ```sh
   sudo cp target/release/furlay-relay /usr/local/bin/
   ```

3. Install the service file:
   ```sh
   sudo cp deploy/ferlay-relay.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now ferlay-relay
   ```

4. Check status:
   ```sh
   sudo systemctl status ferlay-relay
   ```

### Reverse proxy with nginx

Copy `deploy/nginx.conf` to your nginx configuration directory and adjust `server_name` and SSL certificate paths. The key settings for WebSocket support are:

- `proxy_set_header Upgrade $http_upgrade` and `Connection "upgrade"` -- required for WebSocket handshake
- `proxy_read_timeout 86400s` -- keeps long-lived WebSocket connections alive (24 hours)

Obtain TLS certificates with certbot:
```sh
sudo certbot --nginx -d relay.yourdomain.com
```

### Reverse proxy with Caddy (without Docker)

```
relay.yourdomain.com {
    reverse_proxy localhost:8080
}
```

Save this as `/etc/caddy/Caddyfile` and run `sudo systemctl restart caddy`.

## Connecting Your Daemon

After your relay is running, point the daemon at it:

```sh
ferlay config set relay-url wss://relay.yourdomain.com/ws
ferlay daemon --re-pair
```

The `--re-pair` flag forces a new pairing session. The QR code displayed will embed your custom relay URL, so when the mobile app scans it, the app will automatically connect to your self-hosted relay.

**Running the daemon in the background:** The daemon runs in the foreground to display the QR code during pairing. After pairing completes, it continues running to handle sessions. You can background it with:

```sh
# Using nohup
nohup ferlay daemon &

# Or as a systemd user service
# Create ~/.config/systemd/user/ferlay-daemon.service with:
# [Service]
# ExecStart=/usr/local/bin/ferlay daemon
# Restart=on-failure
# Then: systemctl --user enable --now ferlay-daemon
```

## Connecting the App

When you run `ferlay daemon --re-pair`, the QR code contains the relay URL. Simply scan it with the Ferlay app -- it will automatically use your self-hosted relay.

To switch relay URLs without re-pairing, you can manually enter the relay URL in the app settings (if supported).

## Environment Variables

| Variable   | Default              | Description                |
|------------|----------------------|----------------------------|
| `PORT`     | `8080`               | HTTP listen port           |
| `RUST_LOG` | `furlay_relay=info`  | Log level (uses env_filter syntax) |

## Resource Requirements

The relay is very lightweight since all state is in-memory:

- **RAM:** ~10 MB for 100 concurrent users
- **CPU:** Minimal -- the relay just routes WebSocket messages
- **Disk:** None (no database, no persistent storage)
- **Network:** Any $3-5/month VPS is more than sufficient

## Monitoring

### Health check

```
GET /health
```

Returns `ok` with status 200. Used by Docker HEALTHCHECK, reverse proxy health checks, and uptime monitoring tools.

### Stats

```
GET /stats
```

Returns JSON:
```json
{
  "version": "0.1.0",
  "uptime_seconds": 3600,
  "connected_devices": 4,
  "active_pairings": 1
}
```

## Updating

### Docker Compose

```sh
docker compose pull
docker compose up -d
```

### Binary

Download the new release binary, replace `/usr/local/bin/furlay-relay`, and restart:

```sh
sudo systemctl restart ferlay-relay
```

## Cross-Platform Notes

- **Relay server:** Linux only (designed for server deployment)
- **Daemon:** Works on Linux, macOS, and Windows. The daemon connects to the relay over WebSocket (`wss://`), which is handled by the `tokio-tungstenite` library with native TLS support.
