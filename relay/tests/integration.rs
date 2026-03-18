use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::time::Duration;
use tokio::net::TcpListener;
use tokio_tungstenite::{connect_async, tungstenite::Message};

/// Starts the relay server on a random port and returns the WebSocket URL.
async fn start_server() -> String {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();

    let state = std::sync::Arc::new(furlay_relay::state::AppState::new());
    tokio::spawn(furlay_relay::buffer::cleanup_task(state.clone()));

    let app = axum::Router::new()
        .route("/ws", axum::routing::get(furlay_relay::ws::ws_handler))
        .route("/health", axum::routing::get(|| async { "ok" }))
        .with_state(state);

    tokio::spawn(async move {
        axum::serve(listener, app).await.unwrap();
    });

    // Give the server a moment to start
    tokio::time::sleep(Duration::from_millis(50)).await;

    format!("ws://127.0.0.1:{port}/ws")
}

/// Connects a WebSocket client to the given URL.
async fn connect(
    url: &str,
) -> (
    futures_util::stream::SplitSink<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        Message,
    >,
    futures_util::stream::SplitStream<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    >,
) {
    let (ws_stream, _) = connect_async(url).await.expect("Failed to connect");
    ws_stream.split()
}

async fn send_json(
    sink: &mut futures_util::stream::SplitSink<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
        Message,
    >,
    msg: Value,
) {
    sink.send(Message::Text(msg.to_string().into()))
        .await
        .unwrap();
}

async fn recv_json(
    stream: &mut futures_util::stream::SplitStream<
        tokio_tungstenite::WebSocketStream<
            tokio_tungstenite::MaybeTlsStream<tokio::net::TcpStream>,
        >,
    >,
) -> Value {
    let timeout = tokio::time::timeout(Duration::from_secs(5), stream.next()).await;
    match timeout {
        Ok(Some(Ok(Message::Text(text)))) => serde_json::from_str(&text).unwrap(),
        other => panic!("Expected text message, got: {:?}", other),
    }
}

// ─── Test 1: Register → pair → relay message → receive ───

#[tokio::test]
async fn test_register_pair_relay() {
    let url = start_server().await;

    // Daemon connects and registers
    let (mut daemon_tx, mut daemon_rx) = connect(&url).await;
    send_json(
        &mut daemon_tx,
        json!({"type": "register", "device_id": "daemon-1"}),
    )
    .await;
    let resp = recv_json(&mut daemon_rx).await;
    assert_eq!(resp["type"], "registered");
    assert_eq!(resp["device_id"], "daemon-1");

    // Daemon creates pairing code
    send_json(&mut daemon_tx, json!({"type": "create_pairing_code"})).await;
    let resp = recv_json(&mut daemon_rx).await;
    assert_eq!(resp["type"], "pairing_code");
    let code = resp["code"].as_str().unwrap().to_string();
    assert_eq!(code.len(), 6);

    // App connects, registers, and pairs
    let (mut app_tx, mut app_rx) = connect(&url).await;
    send_json(
        &mut app_tx,
        json!({"type": "register", "device_id": "app-1"}),
    )
    .await;
    let resp = recv_json(&mut app_rx).await;
    assert_eq!(resp["type"], "registered");

    send_json(
        &mut app_tx,
        json!({"type": "pair_with_code", "code": code}),
    )
    .await;

    // App gets paired notification
    let resp = recv_json(&mut app_rx).await;
    assert_eq!(resp["type"], "paired");
    assert_eq!(resp["paired_with"], "daemon-1");

    // Daemon also gets paired notification
    let resp = recv_json(&mut daemon_rx).await;
    assert_eq!(resp["type"], "paired");
    assert_eq!(resp["paired_with"], "app-1");

    // Relay a message from daemon → app
    send_json(
        &mut daemon_tx,
        json!({"type": "relay", "payload": {"type": "session_ready", "url": "https://example.com"}}),
    )
    .await;
    let resp = recv_json(&mut app_rx).await;
    assert_eq!(resp["type"], "session_ready");
    assert_eq!(resp["url"], "https://example.com");

    // Relay a message from app → daemon
    send_json(
        &mut app_tx,
        json!({"type": "relay", "payload": {"type": "start_session", "directory": "~/Projects"}}),
    )
    .await;
    let resp = recv_json(&mut daemon_rx).await;
    assert_eq!(resp["type"], "start_session");
    assert_eq!(resp["directory"], "~/Projects");
}

// ─── Test 2: Invalid pairing code → error ───

#[tokio::test]
async fn test_invalid_pairing_code() {
    let url = start_server().await;

    let (mut tx, mut rx) = connect(&url).await;
    send_json(
        &mut tx,
        json!({"type": "register", "device_id": "dev-1"}),
    )
    .await;
    let _ = recv_json(&mut rx).await; // registered

    send_json(
        &mut tx,
        json!({"type": "pair_with_code", "code": "BADCODE"}),
    )
    .await;
    let resp = recv_json(&mut rx).await;
    assert_eq!(resp["type"], "error");
    assert!(resp["message"]
        .as_str()
        .unwrap()
        .contains("invalid or expired"));
}

// ─── Test 3: Unpaired device tries to relay → error ───

#[tokio::test]
async fn test_relay_without_pairing() {
    let url = start_server().await;

    let (mut tx, mut rx) = connect(&url).await;
    send_json(
        &mut tx,
        json!({"type": "register", "device_id": "lonely-dev"}),
    )
    .await;
    let _ = recv_json(&mut rx).await; // registered

    send_json(
        &mut tx,
        json!({"type": "relay", "payload": {"data": "hello"}}),
    )
    .await;
    let resp = recv_json(&mut rx).await;
    assert_eq!(resp["type"], "error");
    assert!(resp["message"]
        .as_str()
        .unwrap()
        .contains("not paired"));
}

// ─── Test 4: Not registered → error on create_pairing_code ───

#[tokio::test]
async fn test_create_pairing_code_without_register() {
    let url = start_server().await;

    let (mut tx, mut rx) = connect(&url).await;
    send_json(&mut tx, json!({"type": "create_pairing_code"})).await;
    let resp = recv_json(&mut rx).await;
    assert_eq!(resp["type"], "error");
    assert!(resp["message"].as_str().unwrap().contains("not registered"));
}

// ─── Test 5: Offline buffering → reconnect → receive buffered ───

#[tokio::test]
async fn test_offline_buffering() {
    let url = start_server().await;

    // Daemon registers and creates pairing code
    let (mut daemon_tx, mut daemon_rx) = connect(&url).await;
    send_json(
        &mut daemon_tx,
        json!({"type": "register", "device_id": "daemon-buf"}),
    )
    .await;
    let _ = recv_json(&mut daemon_rx).await;

    send_json(&mut daemon_tx, json!({"type": "create_pairing_code"})).await;
    let code_resp = recv_json(&mut daemon_rx).await;
    let code = code_resp["code"].as_str().unwrap().to_string();

    // App registers and pairs
    let (mut app_tx, mut app_rx) = connect(&url).await;
    send_json(
        &mut app_tx,
        json!({"type": "register", "device_id": "app-buf"}),
    )
    .await;
    let _ = recv_json(&mut app_rx).await;

    send_json(
        &mut app_tx,
        json!({"type": "pair_with_code", "code": code}),
    )
    .await;
    let _ = recv_json(&mut app_rx).await; // paired (app)
    let _ = recv_json(&mut daemon_rx).await; // paired (daemon)

    // App disconnects
    drop(app_tx);
    drop(app_rx);
    tokio::time::sleep(Duration::from_millis(100)).await;

    // Daemon sends messages while app is offline
    send_json(
        &mut daemon_tx,
        json!({"type": "relay", "payload": {"msg": "buffered-1"}}),
    )
    .await;
    send_json(
        &mut daemon_tx,
        json!({"type": "relay", "payload": {"msg": "buffered-2"}}),
    )
    .await;
    tokio::time::sleep(Duration::from_millis(100)).await;

    // App reconnects and re-registers with same device_id
    let (mut app_tx2, mut app_rx2) = connect(&url).await;
    send_json(
        &mut app_tx2,
        json!({"type": "register", "device_id": "app-buf"}),
    )
    .await;
    let _ = recv_json(&mut app_rx2).await; // registered

    // Should receive buffered messages
    let msg1 = recv_json(&mut app_rx2).await;
    assert_eq!(msg1["msg"], "buffered-1");
    let msg2 = recv_json(&mut app_rx2).await;
    assert_eq!(msg2["msg"], "buffered-2");

    // Cleanup
    drop(app_tx2);
    drop(daemon_tx);
}

// ─── Test 6: Multiple pairs simultaneously → no cross-talk ───

#[tokio::test]
async fn test_no_crosstalk() {
    let url = start_server().await;

    // Pair 1: daemon-a ↔ app-a
    let (mut da_tx, mut da_rx) = connect(&url).await;
    send_json(
        &mut da_tx,
        json!({"type": "register", "device_id": "daemon-a"}),
    )
    .await;
    let _ = recv_json(&mut da_rx).await;

    send_json(&mut da_tx, json!({"type": "create_pairing_code"})).await;
    let code_a = recv_json(&mut da_rx).await["code"]
        .as_str()
        .unwrap()
        .to_string();

    let (mut aa_tx, mut aa_rx) = connect(&url).await;
    send_json(
        &mut aa_tx,
        json!({"type": "register", "device_id": "app-a"}),
    )
    .await;
    let _ = recv_json(&mut aa_rx).await;
    send_json(
        &mut aa_tx,
        json!({"type": "pair_with_code", "code": code_a}),
    )
    .await;
    let _ = recv_json(&mut aa_rx).await; // paired
    let _ = recv_json(&mut da_rx).await; // paired

    // Pair 2: daemon-b ↔ app-b
    let (mut db_tx, mut db_rx) = connect(&url).await;
    send_json(
        &mut db_tx,
        json!({"type": "register", "device_id": "daemon-b"}),
    )
    .await;
    let _ = recv_json(&mut db_rx).await;

    send_json(&mut db_tx, json!({"type": "create_pairing_code"})).await;
    let code_b = recv_json(&mut db_rx).await["code"]
        .as_str()
        .unwrap()
        .to_string();

    let (mut ab_tx, mut ab_rx) = connect(&url).await;
    send_json(
        &mut ab_tx,
        json!({"type": "register", "device_id": "app-b"}),
    )
    .await;
    let _ = recv_json(&mut ab_rx).await;
    send_json(
        &mut ab_tx,
        json!({"type": "pair_with_code", "code": code_b}),
    )
    .await;
    let _ = recv_json(&mut ab_rx).await; // paired
    let _ = recv_json(&mut db_rx).await; // paired

    // Daemon-a sends message → should only reach app-a
    send_json(
        &mut da_tx,
        json!({"type": "relay", "payload": {"from": "daemon-a"}}),
    )
    .await;
    let resp = recv_json(&mut aa_rx).await;
    assert_eq!(resp["from"], "daemon-a");

    // Daemon-b sends message → should only reach app-b
    send_json(
        &mut db_tx,
        json!({"type": "relay", "payload": {"from": "daemon-b"}}),
    )
    .await;
    let resp = recv_json(&mut ab_rx).await;
    assert_eq!(resp["from"], "daemon-b");

    // Verify no cross-talk: app-b should NOT have daemon-a's message
    // (We'd time out if there was an extra message, but the correct messages
    // already arrived above, so this is implicitly verified)
}

// ─── Test 7: Invalid JSON → error response ───

#[tokio::test]
async fn test_invalid_json() {
    let url = start_server().await;

    let (mut tx, mut rx) = connect(&url).await;
    tx.send(Message::Text("not valid json".into()))
        .await
        .unwrap();
    let resp = recv_json(&mut rx).await;
    assert_eq!(resp["type"], "error");
    assert!(resp["message"].as_str().unwrap().contains("invalid message"));
}

// ─── Test 8: Health endpoint ───

#[tokio::test]
async fn test_health_endpoint() {
    let url = start_server().await;
    let http_url = url.replace("ws://", "http://").replace("/ws", "/health");
    let resp = reqwest::get(&http_url).await.unwrap();
    assert_eq!(resp.status(), 200);
    assert_eq!(resp.text().await.unwrap(), "ok");
}
