# Xray + cloudflared Docker Image

An optimized Docker image combining [Xray-core](https://github.com/XTLS/Xray-core) and [cloudflared](https://github.com/cloudflare/cloudflared) for Cloudflare Tunnel deployment with VLESS/XHTTP protocol support.

## Features

- **Single Image**: Combines Xray-core and cloudflared in one optimized Alpine-based image
- **Optimized for linux/amd64**: Single architecture for Cloudflare Workers/Pages compatibility
- **Environment Configuration**: Simple environment variable-based configuration
- **VLESS/XHTTP Protocol**: Next-generation protocol with Cloudflare Tunnel optimization
- **Version Management**: Versions tracked in `upstream-ver.ini` for easy updates
- **Security**: Non-root user execution and minimal attack surface
- **Health Check**: Built-in health check endpoint for container orchestration

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Container                         │
│  ┌──────────────┐         ┌──────────────┐                  │
│  │  cloudflared │────────>│  Xray-core   │                  │
│  │  (Background)│         │  (Foreground)│                  │
│  └──────────────┘         └──────────────┘                  │
│         │                        │                           │
└─────────┼────────────────────────┼───────────────────────────┘
          │                        │
          v                        v
    Cloudflare Tunnel         Client Connections
          │                        │
          └────────────────────────┘
                   Cloudflare Network
```

## Environment Variables

### Required Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `TUNNEL_TOKEN` | Cloudflare Tunnel token from Cloudflare Zero Trust dashboard | `eyJh...` |
| `VLESS_UUID` | UUID for VLESS client authentication | `12345678-1234-1234-1234-123456789abc` |
| `DOMAIN` | Your domain configured in Cloudflare Tunnel | `tunnel.example.com` |

### Optional Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `PORT` | Xray inbound port | `10000` |
| `LOG_LEVEL` | Xray log level (debug, info, warning, error, none) | `warning` |
| `ENABLE_HEALTH_CHECK` | Enable health check server on port 8080 | `true` |
| `VLESS_XHTTP_PATH` | XHTTP path for VLESS transport | `/your-secret-path` |

## Quick Start

### Local Testing

```bash
docker run -d \
  --name cf-xray \
  -e TUNNEL_TOKEN="your_cloudflare_tunnel_token" \
  -e VLESS_UUID="your_vless_uuid" \
  -e DOMAIN="your.domain.com" \
  -p 10000:10000 \
  -p 8080:8080 \
  ghcr.io/yourusername/cf-xray:latest
```

### Generate VLESS UUID

```bash
# Linux
uuidgen

# macOS
uuidgen

# Online generator
# Visit: https://www.uuidgenerator.net/
```

## Cloudflare Run Deployment

### Prerequisites

1. Cloudflare account with a domain
2. Cloudflare Tunnel created and configured
3. Container registry access (GitHub Container Registry)

### Deployment Steps

#### 1. Create Cloudflare Tunnel

```bash
# Install cloudflared
# macOS
brew install cloudflared

# Linux
wget https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb
dpkg -i cloudflared-linux-amd64.deb

# Login to Cloudflare
cloudflared tunnel login

# Create tunnel
cloudflared tunnel create my-xray-tunnel

# Note the tunnel ID from output
```

#### 2. Configure Tunnel Routing

```bash
# Configure routing (example config.yaml)
cat > config.yaml << EOF
tunnel: <your-tunnel-id>
credentials-file: /path/to/credentials.json

ingress:
  - hostname: your.domain.com
    service: http://localhost:10000
  - service: http_status:404
EOF

# Apply configuration
cloudflared tunnel route dns <your-tunnel-id> your.domain.com
```

#### 3. Deploy to Cloudflare Run

```bash
# Pull the image
docker pull ghcr.io/yourusername/cf-xray:latest

# Run with environment variables
docker run -d \
  --name cf-xray \
  --restart unless-stopped \
  -e TUNNEL_TOKEN="your_tunnel_token" \
  -e VLESS_UUID="your_vless_uuid" \
  -e DOMAIN="your.domain.com" \
  ghcr.io/yourusername/cf-xray:latest
```

### Using Docker Compose

```yaml
version: '3.8'

services:
  cf-xray:
    image: ghcr.io/yourusername/cf-xray:latest
    container_name: cf-xray
    restart: unless-stopped
    environment:
      TUNNEL_TOKEN: "your_cloudflare_tunnel_token"
      VLESS_UUID: "your_vless_uuid"
      DOMAIN: "your.domain.com"
      PORT: "10000"
      LOG_LEVEL: "warning"
      ENABLE_HEALTH_CHECK: "true"
    ports:
      - "10000:10000"
      - "8080:8080"
    healthcheck:
      test: ["CMD", "pgrep", "xray"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 5s
```

## Client Configuration

### VLESS/XHTTP Client Config (JSON)

```json
{
  "inbounds": [{
    "port": 1080,
    "protocol": "socks",
    "settings": {
      "auth": "noauth",
      "udp": true
    }
  }],
  "outbounds": [{
    "protocol": "vless",
    "settings": {
      "vnext": [{
        "address": "your.domain.com",
        "port": 443,
        "users": [{
          "id": "your_vless_uuid",
          "flow": "xtls-rprx-vision",
          "encryption": "none"
        }]
      }]
    },
    "streamSettings": {
      "network": "xhttp",
      "security": "tls",
      "tlsSettings": {
        "serverName": "your.domain.com"
      },
      "xhttpSettings": {
        "path": "/your_vless_uuid",
        "mode": "auto"
      }
    }
  }]
}
```

## Version Management

Image versions are managed through `upstream-ver.ini`:

```ini
[xray-core]
version=26.3.27

[cloudflared]
version=2024.4.0
```

To update to new versions:
1. Edit `upstream-ver.ini` with desired versions
2. Commit and push - GitHub Actions will automatically build

**Image Tags:**
- **Latest tag**: Always points to the latest build
- **Version tags**: Match Xray-core versions (e.g., `v26.3.27`)
- **SHA tags**: Include Git SHA for reproducible builds

### Available Versions

```bash
# Check available tags
curl -s https://ghcr.io/v2/repositories/yourusername/cf-xray/tags/list | jq

# Pull specific version
docker pull ghcr.io/yourusername/cf-xray:v26.3.27
```

## Building from Source

### Build Locally

```bash
# Clone repository
git clone https://github.com/yourusername/cf-xray.git
cd cf-xray

# Build for linux/amd64
docker build -t cf-xray:local .
```

### Custom Versions

```bash
# Edit upstream-ver.ini first, then build
# Or override with build args:
docker build \
  --build-arg XRAY_VERSION=v26.3.27 \
  --build-arg CLOUDFLARED_VERSION=2024.4.0 \
  -t cf-xray:custom \
  .
```

## Health Check

The container includes a health check endpoint on port 8080:

```bash
# Check health
curl http://localhost:8080

# Response
{"status":"healthy"}
```

## Troubleshooting

### Container won't start

1. Check required environment variables:
   ```bash
   docker logs cf-xray
   ```

2. Verify TUNNEL_TOKEN is valid:
   ```bash
   cloudflared tunnel run --token your_token
   ```

### Connection issues

1. Check Xray logs:
   ```bash
   docker logs cf-xray | grep xray
   ```

2. Verify cloudflared is running:
   ```bash
   docker exec cf-xray pgrep cloudflared
   ```

3. Test connectivity:
   ```bash
   docker exec cf-xray wget -O- http://localhost:10000
   ```

### Common errors

- **Missing TUNNEL_TOKEN**: Set the `TUNNEL_TOKEN` environment variable
- **Invalid UUID**: Generate a new UUID using `uuidgen`
- **Port conflicts**: Change the `PORT` environment variable
- **Permission denied**: Ensure the container runs as non-root user

## Security Considerations

1. **UUID Security**: Keep your VLESS_UUID secret and share only with trusted clients
2. **Tunnel Token**: Never expose your TUNNEL_TOKEN in public repositories
3. **Network Isolation**: Use Docker networks or firewall rules to restrict access
4. **Regular Updates**: Pull latest images for security patches
5. **Log Level**: Set `LOG_LEVEL=error` in production to reduce information leakage

## Performance Optimization

1. **CPU Pinning**: Allocate dedicated CPU cores for better performance
2. **Memory Limits**: Set appropriate memory limits in Docker
3. **Network Mode**: Use `--network host` for reduced latency (if supported)
4. **Log Reduction**: Set `LOG_LEVEL=warning` to minimize I/O overhead

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

## Acknowledgments

- [Xray-core](https://github.com/XTLS/Xray-core) - The core proxy platform
- [cloudflared](https://github.com/cloudflare/cloudflared) - Cloudflare Tunnel daemon
- [Cloudflare](https://www.cloudflare.com/) - Cloudflare Tunnel service

## Support

For issues and questions:
- Open an issue on GitHub
- Check existing issues for solutions
- Review Cloudflare Tunnel documentation

---

**Note**: This project is not affiliated with or endorsed by Cloudflare or XTLS.
