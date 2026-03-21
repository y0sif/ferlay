.PHONY: local build build-relay build-daemon relay daemon clean

build:
	cargo build --release -p furlay-relay -p furlay-daemon

build-relay:
	cargo build --release -p furlay-relay

build-daemon:
	cargo build --release -p furlay-daemon

relay:
	cargo run --release -p furlay-relay

daemon:
	cargo run --release -p furlay-daemon -- daemon --relay ws://127.0.0.1:8080/ws

local: build
	./scripts/ferlay-local.sh

clean:
	cargo clean
