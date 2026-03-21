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
    PairWithCode {
        code: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        public_key: Option<String>,
    },

    #[serde(rename = "paired")]
    Paired {
        paired_with: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        public_key: Option<String>,
    },

    #[serde(rename = "relay")]
    Relay { payload: serde_json::Value },

    #[serde(rename = "key_exchange")]
    KeyExchange { public_key: String },

    #[serde(rename = "error")]
    Error { message: String },
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn register_serialization() {
        let msg = ControlMessage::Register {
            device_id: "dev-1".to_string(),
            fcm_token: None,
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["type"], "register");
        assert_eq!(json["device_id"], "dev-1");
    }

    #[test]
    fn relay_with_json_payload() {
        let msg = ControlMessage::Relay {
            payload: serde_json::json!({"type": "start_session", "directory": "/tmp"}),
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["type"], "relay");
        assert_eq!(json["payload"]["directory"], "/tmp");
    }

    #[test]
    fn relay_with_string_payload_for_encrypted() {
        let msg = ControlMessage::Relay {
            payload: serde_json::Value::String("base64blob==".to_string()),
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["payload"], "base64blob==");
    }

    #[test]
    fn deserialize_roundtrip() {
        let msg = ControlMessage::Paired {
            paired_with: "other-dev".to_string(),
            public_key: Some("test-key".to_string()),
        };
        let json_str = serde_json::to_string(&msg).unwrap();
        let deserialized: ControlMessage = serde_json::from_str(&json_str).unwrap();
        match deserialized {
            ControlMessage::Paired { paired_with, public_key } => {
                assert_eq!(paired_with, "other-dev");
                assert_eq!(public_key.unwrap(), "test-key");
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn error_message_roundtrip() {
        let json = r#"{"type":"error","message":"something failed"}"#;
        let msg: ControlMessage = serde_json::from_str(json).unwrap();
        match msg {
            ControlMessage::Error { message } => assert_eq!(message, "something failed"),
            _ => panic!("wrong variant"),
        }
    }
}
