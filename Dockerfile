# Multi-stage build with separate download stage
FROM alpine:latest AS downloader

RUN apk add --no-cache curl tar

# Download Xray-core (retry logic for reliability)
RUN echo "Downloading Xray-core..." && \
    for i in 1 2 3 4 5; do \
        curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 180 \
            -o /tmp/xray.zip \
            "https://github.com/XTLS/Xray-core/releases/download/v26.3.27/Xray-linux-64.zip" && \
        unzip /tmp/xray.zip -d /tmp && \
        rm /tmp/xray.zip && \
        echo "Xray download successful" && \
        break || \
        (echo "Xray download attempt $i failed, retrying..." && sleep 10); \
    done

# Download cloudflared (retry logic for reliability)
RUN echo "Downloading cloudflared..." && \
    for i in 1 2 3 4 5; do \
        curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 180 \
            -o /tmp/cloudflared \
            "https://github.com/cloudflare/cloudflared/releases/download/2024.4.0/cloudflared-linux-amd64" && \
        chmod +x /tmp/cloudflared && \
        echo "Cloudflared download successful" && \
        break || \
        (echo "Cloudflared download attempt $i failed, retrying..." && sleep 10); \
    done

# Final stage
FROM alpine:latest

RUN apk add --no-cache ca-certificates tzdata && \
    addgroup -g 1000 xray && \
    adduser -D -u 1000 -G xray xray

# Copy binaries from downloader
COPY --from=downloader /tmp/xray /usr/local/bin/
COPY --from=downloader /tmp/cloudflared /usr/local/bin/

# Copy configuration files
COPY config/ /etc/xray/
COPY entrypoint.sh /entrypoint.sh

# Set permissions
RUN chmod +x /entrypoint.sh /usr/local/bin/xray /usr/local/bin/cloudflared && \
    chown -R xray:xray /etc/xray

WORKDIR /home/xray
USER xray

EXPOSE 10000

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD pgrep xray || exit 1

ENTRYPOINT ["/entrypoint.sh"]
