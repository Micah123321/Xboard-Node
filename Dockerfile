# Build stage
FROM golang:1.26-alpine AS builder

RUN apk add --no-cache git

WORKDIR /build

COPY go.mod go.sum ./
RUN go mod download

COPY . .

RUN CGO_ENABLED=0 go build -ldflags "-s -w \
    -X main.version=$(git describe --tags --always --dirty 2>/dev/null || echo dev) \
    -X main.buildTime=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    -tags "with_quic with_utls with_wireguard with_clash_api" \
    -o mi-node ./cmd/mi-node

# Runtime stage — sing-box & xray-core are embedded as Go libraries
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata iputils

COPY --from=builder /build/mi-node /usr/local/bin/mi-node

RUN mkdir -p /etc/mi-node

WORKDIR /etc/mi-node

# Config can be provided via file mount OR environment variables.
# Env var mode (no config file needed):
#   docker run -d --network=host \
#     -e apiHost=https://panel.example.com \
#     -e apiKey=YOUR_TOKEN \
#     -e nodeID=1 \
#     ghcr.io/micah123321/mi-node:latest
#
# Supported env vars:
#   apiHost  / API_HOST    → panel URL
#   apiKey   / API_KEY     → server token
#   nodeID   / NODE_ID     → node ID
#   nodeType / NODE_TYPE   → node type (optional)
#   kernel   / KERNEL_TYPE → singbox (default) or xray
#   domain   / DOMAIN      → TLS domain (enables auto_tls)
#   certFile / CERT_FILE   → TLS cert path
#   keyFile  / KEY_FILE    → TLS key path
#   logLevel / LOG_LEVEL   → log level

ENTRYPOINT ["mi-node"]
CMD ["-c", "/etc/mi-node/config.yml"]
