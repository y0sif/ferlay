# Stage 1: Chef base
FROM rust:1.93-slim AS chef
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*
RUN cargo install cargo-chef --locked
WORKDIR /build

# Stage 2: Planner — generate dependency recipe
FROM chef AS planner
COPY Cargo.toml Cargo.lock ./
COPY shared/ shared/
COPY relay/ relay/
COPY daemon/Cargo.toml daemon/
RUN mkdir -p daemon/src && echo "fn main() {}" > daemon/src/main.rs
RUN cargo chef prepare --recipe-path recipe.json

# Stage 3: Builder — cache deps, then build relay
FROM chef AS builder
COPY --from=planner /build/recipe.json recipe.json
COPY Cargo.toml Cargo.lock ./
COPY shared/Cargo.toml shared/
COPY relay/Cargo.toml relay/
COPY daemon/Cargo.toml daemon/
RUN mkdir -p shared/src relay/src daemon/src \
    && echo "" > shared/src/lib.rs \
    && echo "fn main() {}" > relay/src/main.rs \
    && echo "fn main() {}" > daemon/src/main.rs
RUN cargo chef cook --release -p furlay-relay --recipe-path recipe.json

COPY shared/ shared/
COPY relay/ relay/
RUN touch relay/src/main.rs && cargo build --release -p furlay-relay

# Stage 4: Runtime (~30MB)
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -r -s /bin/false ferlay
COPY --from=builder /build/target/release/furlay-relay /usr/local/bin/
USER ferlay
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/health || exit 1
ENV RUST_LOG=furlay_relay=info
CMD ["furlay-relay"]
