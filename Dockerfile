# Build arguments for version control
# These are typically overridden by build arguments from CI/CD
# which reads versions from upstream-ver.ini
ARG XRAY_VERSION=v26.3.27
ARG CLOUDFLARED_VERSION=2024.4.0

# Stage 1: Download binaries
FROM alpine:latest AS builder

# Install build dependencies
RUN apk add --no-cache curl tar unzip ca-certificates

# Set version arguments
ARG XRAY_VERSION
ARG CLOUDFLARED_VERSION

# Download xray-core using GitHub API (more reliable)
RUN curl -fL "https://api.github.com/repos/XTLS/Xray-core/releases/tags/${XRAY_VERSION}" | \
    grep "browser_download_url.*Xray-linux-64.zip" | cut -d '"' -f 4 | \
    xargs curl -fL -o /tmp/xray.zip && \
    unzip /tmp/xray.zip -d /tmp/xray && \
    rm /tmp/xray.zip

# Download cloudflared using GitHub API
RUN curl -fL "https://api.github.com/repos/cloudflare/cloudflared/releases/tags/${CLOUDFLARED_VERSION}" | \
    grep "browser_download_url.*cloudflared-linux-amd64\"" | cut -d '"' -f 4 | \
    xargs curl -fL -o /tmp/cloudflared && \
    chmod +x /tmp/cloudflared

# Stage 2: Create minimal runtime image
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g 1000 xray && \
    adduser -D -u 1000 -G xray xray

# Set version labels
ARG XRAY_VERSION
ARG CLOUDFLARED_VERSION
ARG IMAGE_VERSION=${XRAY_VERSION}

LABEL maintainer="cf-xray" \
      xray.version="${XRAY_VERSION}" \
      cloudflared.version="${CLOUDFLARED_VERSION}" \
      image.version="${IMAGE_VERSION}" \
      description="Xray-core + cloudflared for Cloudflare Tunnel with VLESS/XHTTP" \
      version.source="upstream-ver.ini"

# Copy binaries from builder
COPY --from=builder /tmp/xray/xray /usr/local/bin/xray
COPY --from=builder /tmp/cloudflared /usr/local/bin/cloudflared

# Copy configuration files
COPY config/ /etc/xray/
COPY entrypoint.sh /entrypoint.sh

# Set permissions
RUN chmod +x /entrypoint.sh /usr/local/bin/xray /usr/local/bin/cloudflared && \
    chown -R xray:xray /etc/xray

# Create working directory
WORKDIR /home/xray

# Switch to non-root user
USER xray

# Expose ports
EXPOSE 10000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep xray || exit 1

# Entry point
ENTRYPOINT ["/entrypoint.sh"]
