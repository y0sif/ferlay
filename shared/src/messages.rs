use serde::{Deserialize, Serialize};

/// Control messages exchanged between clients and the relay server.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum ControlMessage {
    #[serde(rename = "register")]
    Register {
        device_id: String,
        fcm_token: Option<String>,
    },

    #[serde(rename = "registered")]
    Registered { device_id: String },

    #[serde(rename = "create_pairing_code")]
    CreatePairingCode,

    #[serde(rename = "pairing_code")]
    PairingCode { code: String },

    #[serde(rename = "pair_with_code")]
    PairWithCode { code: String },

    #[serde(rename = "paired")]
    Paired { paired_with: String },

    #[serde(rename = "relay")]
    Relay { payload: serde_json::Value },

    #[serde(rename = "error")]
    Error { message: String },
}
