FROM rust:1-slim AS builder
WORKDIR /app
COPY . .
RUN cargo build --release -p pocket-ai-relay

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/pocket-ai-relay /usr/local/bin/
EXPOSE 8080
CMD ["pocket-ai-relay"]
