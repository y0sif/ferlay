use serde::{Deserialize, Serialize};
use std::path::PathBuf;

const DEFAULT_RELAY_URL: &str = "wss://relay.ferlay.dev/ws";

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub relay_url: String,
    pub device_id: String,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            relay_url: DEFAULT_RELAY_URL.to_string(),
            device_id: uuid::Uuid::new_v4().to_string(),
        }
    }
}

fn config_path() -> PathBuf {
    let dir = dirs::config_dir().unwrap().join("ferlay");
    std::fs::create_dir_all(&dir).ok();
    dir.join("config.json")
}

pub fn load() -> Config {
    let path = config_path();
    match std::fs::read_to_string(&path) {
        Ok(data) => serde_json::from_str(&data).unwrap_or_else(|_| {
            let config = Config::default();
            save(&config);
            config
        }),
        Err(_) => {
            let config = Config::default();
            save(&config);
            config
        }
    }
}

pub fn save(config: &Config) {
    let path = config_path();
    let json = serde_json::to_string_pretty(config).unwrap();
    std::fs::write(path, json).ok();
}

pub fn set_relay_url(url: &str) {
    let mut config = load();
    config.relay_url = url.to_string();
    save(&config);
}

pub fn get_relay_url() -> String {
    load().relay_url
}

pub fn reset() {
    let config = Config::default();
    save(&config);
}
