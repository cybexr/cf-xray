# Build arguments for version control
# These are typically overridden by build arguments from CI/CD
# which reads versions from upstream-ver.ini
ARG XRAY_VERSION=v26.3.27
ARG CLOUDFLARED_VERSION=2024.4.0
ARG USE_LOCAL_BINARIES=false

# Stage 1: Download binaries
FROM alpine:latest AS builder

# Install build dependencies
RUN apk add --no-cache curl tar unzip

# Set version arguments
ARG XRAY_VERSION
ARG CLOUDFLARED_VERSION
ARG USE_LOCAL_BINARIES

# Download xray-core or use local copy
COPY binaries/ /tmp/binaries/ || true
RUN if [ "$USE_LOCAL_BINARIES" = "true" ] && [ -f /tmp/binaries/xray ]; then \
        cp /tmp/binaries/xray /tmp/xray && \
        echo "Using local xray binary"; \
    else \
        curl -L -o /tmp/xray.zip "https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/Xray-linux-64.zip" && \
        unzip /tmp/xray.zip -d /tmp/xray && \
        rm /tmp/xray.zip && \
        echo "Downloaded xray from releases"; \
    fi

# Download cloudflared or use local copy
RUN if [ "$USE_LOCAL_BINARIES" = "true" ] && [ -f /tmp/binaries/cloudflared ]; then \
        cp /tmp/binaries/cloudflared /tmp/cloudflared && \
        echo "Using local cloudflared binary"; \
    else \
        curl -L -o /tmp/cloudflared "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64" && \
        echo "Downloaded cloudflared from releases"; \
    fi
RUN chmod +x /tmp/cloudflared

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
