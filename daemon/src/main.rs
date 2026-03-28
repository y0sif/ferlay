mod capture;
mod config;
mod crypto;
mod daemon;
mod messages;
mod pairing;
mod relay;
mod session;
mod setup;

use clap::{Parser, Subcommand};

/// Default hosted relay URL. Override with --relay or `ferlay config set relay-url <url>`.
pub const DEFAULT_RELAY_URL: &str = "wss://relay.ferlay.dev/ws";

#[derive(Parser)]
#[command(name = "ferlay", version, about = "Remote session manager for Claude Code")]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Relay server URL (overrides config)
    #[arg(long, global = true)]
    relay: Option<String>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the daemon (pairs if needed, then connects to relay and listens for commands)
    Daemon {
        /// Force new pairing even if a saved encryption key exists
        #[arg(long)]
        re_pair: bool,

        /// Run in local mode (relay defaults to ws://127.0.0.1:8080/ws)
        #[arg(long)]
        local: bool,
    },

    /// Interactive setup: configure relay, pair with phone, enable auto-start
    Setup,

    /// Re-pair with a new phone (stops service, pairs, restarts)
    Pair,

    /// Show daemon status + active sessions
    Status,

    /// Manage configuration
    Config {
        #[command(subcommand)]
        action: ConfigAction,
    },
}

#[derive(Subcommand)]
enum ConfigAction {
    /// Set a config value
    Set {
        #[command(subcommand)]
        setting: ConfigSetting,
    },
    /// Get a config value
    Get {
        #[command(subcommand)]
        setting: ConfigGetSetting,
    },
    /// Show all configuration and pairing status
    Show,
    /// Reset config to defaults
    Reset,
}

#[derive(Subcommand)]
enum ConfigSetting {
    /// Set the relay server URL (use "default" to reset to hosted relay)
    RelayUrl { url: String },
}

#[derive(Subcommand)]
enum ConfigGetSetting {
    /// Show the current relay server URL
    RelayUrl,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "ferlay_daemon=info".into()),
        )
        .init();

    let cli = Cli::parse();
    let cfg = config::load();

    match cli.command {
        Commands::Daemon { re_pair, local } => {
            let relay_url = if local {
                let local_url = "ws://127.0.0.1:8080/ws".to_string();
                let url = cli.relay.unwrap_or(local_url);
                tracing::info!("Running in local mode (relay: {})", url);
                url
            } else {
                let url = cli.relay.unwrap_or_else(|| cfg.relay_url.clone());
                tracing::info!("Using relay: {url}");
                url
            };
            tracing::info!(relay = %relay_url, device_id = %cfg.device_id, re_pair = re_pair, "Starting daemon");
            daemon::run(cfg, relay_url, re_pair).await;
        }
        Commands::Setup => {
            setup::run_setup().await;
        }
        Commands::Pair => {
            setup::run_pair().await;
        }
        Commands::Status => {
            // Check health endpoint
            match reqwest_status().await {
                Ok(resp) => println!("{resp}"),
                Err(_) => println!("Daemon is not running (health endpoint unreachable)"),
            }
        }
        Commands::Config { action } => match action {
            ConfigAction::Set { setting } => match setting {
                ConfigSetting::RelayUrl { url } => {
                    let actual_url = if url == "default" {
                        DEFAULT_RELAY_URL.to_string()
                    } else {
                        url
                    };
                    config::set_relay_url(&actual_url);
                    println!("Relay URL set to: {actual_url}");
                }
            },
            ConfigAction::Get { setting } => match setting {
                ConfigGetSetting::RelayUrl => {
                    println!("{}", config::get_relay_url());
                }
            },
            ConfigAction::Show => {
                let c = config::load();
                println!("relay_url: {}", c.relay_url);
                println!("device_id: {}", c.device_id);
                let keys_exist = dirs::config_dir()
                    .map(|d| d.join("ferlay/keys").exists())
                    .unwrap_or(false);
                println!("paired: {}", keys_exist);
                println!("version: {}", env!("CARGO_PKG_VERSION"));
            }
            ConfigAction::Reset => {
                config::reset();
                println!("Config reset to defaults");
            }
        },
    }
}

async fn reqwest_status() -> Result<String, Box<dyn std::error::Error>> {
    let health: String = reqwest::get("http://127.0.0.1:9876/health")
        .await?
        .text()
        .await?;
    let sessions: serde_json::Value = reqwest::get("http://127.0.0.1:9876/sessions")
        .await?
        .json()
        .await?;

    Ok(format!(
        "Daemon: {health}\nSessions: {}",
        serde_json::to_string_pretty(&sessions)?
    ))
}
