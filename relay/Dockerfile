# Stage 1: Build
FROM rust:1.87-slim AS builder
WORKDIR /build

# Cache dependencies by copying manifests first
COPY Cargo.toml Cargo.lock ./
COPY shared/Cargo.toml shared/
COPY relay/Cargo.toml relay/
COPY daemon/Cargo.toml daemon/

# Create dummy source files to build dependencies
RUN mkdir -p shared/src relay/src daemon/src \
    && echo "fn main() {}" > relay/src/main.rs \
    && echo "" > shared/src/lib.rs \
    && echo "fn main() {}" > daemon/src/main.rs \
    && cargo build --release -p furlay-relay 2>/dev/null || true

# Copy real source and build
COPY shared/ shared/
COPY relay/ relay/
RUN touch relay/src/main.rs && cargo build --release -p furlay-relay

# Stage 2: Runtime (~30MB)
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /bin/false ferlay
COPY --from=builder /build/target/release/furlay-relay /usr/local/bin/
USER ferlay
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s \
    CMD curl -f http://localhost:8080/health || exit 1
ENV RUST_LOG=furlay_relay=info
CMD ["furlay-relay"]
