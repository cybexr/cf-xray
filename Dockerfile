# Use official Xray image as base
FROM ghcr.io/xtls/xray:latest AS xray-base

# Build arguments for version tracking
ARG XRAY_VERSION=v26.3.27
ARG CLOUDFLARED_VERSION=2024.4.0

# Stage 1: Get cloudflared
FROM alpine:latest AS cloudflared-builder

RUN apk add --no-cache curl && \
    curl -L -o /usr/local/bin/cloudflared \
        "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64" && \
    chmod +x /usr/local/bin/cloudflared

# Stage 2: Final image
FROM ghcr.io/xtls/xray:latest

# Copy cloudflared from builder
COPY --from=cloudflared-builder /usr/local/bin/cloudflared /usr/local/bin/cloudflared

# Copy configuration files
COPY config/ /etc/xray/
COPY entrypoint.sh /entrypoint.sh

# Set permissions
RUN chmod +x /entrypoint.sh /usr/local/bin/cloudflared

# Set version labels
LABEL maintainer="cf-xray" \
      xray.version="${XRAY_VERSION}" \
      cloudflared.version="${CLOUDFLARED_VERSION}" \
      description="Xray-core + cloudflared for Cloudflare Tunnel with VLESS/XHTTP" \
      version.source="upstream-ver.ini"

# Create working directory
WORKDIR /home/xray

# Expose ports
EXPOSE 10000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep xray || exit 1

# Entry point
ENTRYPOINT ["/entrypoint.sh"]
