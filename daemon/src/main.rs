mod capture;
mod config;
mod daemon;
mod messages;
mod pairing;
mod relay;
mod session;

use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(name = "ferlay", about = "Remote session manager for Claude Code")]
struct Cli {
    #[command(subcommand)]
    command: Commands,

    /// Relay server URL (overrides config)
    #[arg(long, global = true)]
    relay: Option<String>,
}

#[derive(Subcommand)]
enum Commands {
    /// Start the daemon (connects to relay, listens for commands)
    Daemon,

    /// Display QR code for mobile pairing
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
    /// Reset config to defaults
    Reset,
}

#[derive(Subcommand)]
enum ConfigSetting {
    /// Set the relay server URL
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
                .unwrap_or_else(|_| "furlay_daemon=info".into()),
        )
        .init();

    let cli = Cli::parse();
    let cfg = config::load();
    let relay_url = cli.relay.unwrap_or_else(|| cfg.relay_url.clone());

    match cli.command {
        Commands::Daemon => {
            tracing::info!(relay = %relay_url, device_id = %cfg.device_id, "Starting daemon");
            daemon::run(cfg, relay_url).await;
        }
        Commands::Pair => {
            daemon::run_pair(cfg, relay_url).await;
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
                    config::set_relay_url(&url);
                    println!("Relay URL set to: {url}");
                }
            },
            ConfigAction::Get { setting } => match setting {
                ConfigGetSetting::RelayUrl => {
                    println!("{}", config::get_relay_url());
                }
            },
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
