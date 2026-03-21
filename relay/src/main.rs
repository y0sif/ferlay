use axum::{extract::State, routing::get, Json, Router};
use serde_json::json;
use std::sync::Arc;
use tower_http::cors::CorsLayer;

use furlay_relay::{buffer, state::AppState, ws};

const VERSION: &str = env!("CARGO_PKG_VERSION");

async fn stats_handler(State(state): State<Arc<AppState>>) -> Json<serde_json::Value> {
    Json(json!({
        "version": VERSION,
        "uptime_seconds": state.start_time.elapsed().as_secs(),
        "connected_devices": state.devices.len(),
        "active_pairings": state.pairing_codes.len(),
    }))
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "furlay_relay=info".into()),
        )
        .init();

    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());

    let state = Arc::new(AppState::new());

    // Spawn TTL cleanup background task
    tokio::spawn(buffer::cleanup_task(state.clone()));

    let app = Router::new()
        .route("/ws", get(ws::ws_handler))
        .route("/health", get(|| async { "ok" }))
        .route("/stats", get(stats_handler))
        .layer(CorsLayer::permissive())
        .with_state(state);

    let addr = format!("0.0.0.0:{port}");
    let listener = tokio::net::TcpListener::bind(&addr).await.unwrap();
    tracing::info!("Relay server listening on {addr}");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .unwrap();
}

async fn shutdown_signal() {
    tokio::signal::ctrl_c()
        .await
        .expect("failed to install signal handler");
    tracing::info!("Shutting down");
}
