.PHONY: local build build-relay build-daemon relay daemon clean

build:
	cargo build --release -p ferlay-relay -p ferlay-daemon

build-relay:
	cargo build --release -p ferlay-relay

build-daemon:
	cargo build --release -p ferlay-daemon

relay:
	cargo run --release -p ferlay-relay

daemon:
	cargo run --release -p ferlay-daemon -- daemon --relay ws://127.0.0.1:8080/ws

local: build
	./scripts/ferlay-local.sh

clean:
	cargo clean
