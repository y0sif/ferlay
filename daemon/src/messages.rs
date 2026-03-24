use serde::{Deserialize, Serialize};

/// Application-level messages exchanged between daemon and mobile app (via relay).
/// These are wrapped inside `ControlMessage::Relay { payload }`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AppMessage {
    #[serde(rename = "start_session")]
    StartSession {
        directory: String,
        name: String,
        #[serde(default)]
        #[serde(skip_serializing_if = "Option::is_none")]
        permission_mode: Option<String>,
        #[serde(default)]
        worktree: bool,
    },

    #[serde(rename = "session_ready")]
    SessionReady {
        session_id: String,
        url: String,
        name: String,
    },

    #[serde(rename = "session_status")]
    SessionStatus {
        session_id: String,
        status: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        error: Option<String>,
    },

    #[serde(rename = "stop_session")]
    StopSession { session_id: String },

    #[serde(rename = "list_sessions")]
    ListSessions,

    #[serde(rename = "sessions_list")]
    SessionsList { sessions: Vec<SessionInfo> },

    #[serde(rename = "key_exchange")]
    KeyExchange { public_key: String },

    #[serde(rename = "encryption_verify")]
    EncryptionVerify { challenge: String },

    #[serde(rename = "encryption_verify_ack")]
    EncryptionVerifyAck { challenge: String },

    #[serde(rename = "ping")]
    Ping { timestamp: u64 },

    #[serde(rename = "pong")]
    Pong { timestamp: u64 },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInfo {
    pub id: String,
    pub name: String,
    pub directory: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub permission_mode: Option<String>,
    #[serde(default)]
    pub worktree: bool,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn start_session_serialization() {
        let msg = AppMessage::StartSession {
            directory: "~/Projects".to_string(),
            name: "test".to_string(),
            permission_mode: None,
            worktree: false,
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["type"], "start_session");
        assert_eq!(json["directory"], "~/Projects");
        assert_eq!(json["name"], "test");
        assert!(json.get("permission_mode").is_none());
        assert_eq!(json["worktree"], false);
    }

    #[test]
    fn start_session_with_options_serialization() {
        let msg = AppMessage::StartSession {
            directory: "~/Projects".to_string(),
            name: "test".to_string(),
            permission_mode: Some("bypassPermissions".to_string()),
            worktree: true,
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["permission_mode"], "bypassPermissions");
        assert_eq!(json["worktree"], true);
    }

    #[test]
    fn session_ready_serialization() {
        let msg = AppMessage::SessionReady {
            session_id: "abc".to_string(),
            url: "https://claude.ai/code?bridge=env_123".to_string(),
            name: "my-session".to_string(),
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["type"], "session_ready");
        assert_eq!(json["session_id"], "abc");
        assert_eq!(json["url"], "https://claude.ai/code?bridge=env_123");
    }

    #[test]
    fn session_status_omits_none_error() {
        let msg = AppMessage::SessionStatus {
            session_id: "s1".to_string(),
            status: "ready".to_string(),
            error: None,
        };
        let json_str = serde_json::to_string(&msg).unwrap();
        assert!(!json_str.contains("error"), "None error should be omitted");
    }

    #[test]
    fn session_status_includes_error_when_present() {
        let msg = AppMessage::SessionStatus {
            session_id: "s1".to_string(),
            status: "crashed".to_string(),
            error: Some("spawn failed".to_string()),
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["error"], "spawn failed");
    }

    #[test]
    fn key_exchange_serialization() {
        let msg = AppMessage::KeyExchange {
            public_key: "base64key".to_string(),
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["type"], "key_exchange");
        assert_eq!(json["public_key"], "base64key");
    }

    #[test]
    fn deserialize_start_session() {
        let json = r#"{"type":"start_session","directory":"/tmp","name":"foo"}"#;
        let msg: AppMessage = serde_json::from_str(json).unwrap();
        match msg {
            AppMessage::StartSession { directory, name, permission_mode, worktree } => {
                assert_eq!(directory, "/tmp");
                assert_eq!(name, "foo");
                assert!(permission_mode.is_none());
                assert!(!worktree);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn deserialize_start_session_with_options() {
        let json = r#"{"type":"start_session","directory":"/tmp","name":"foo","permission_mode":"plan","worktree":true}"#;
        let msg: AppMessage = serde_json::from_str(json).unwrap();
        match msg {
            AppMessage::StartSession { permission_mode, worktree, .. } => {
                assert_eq!(permission_mode.as_deref(), Some("plan"));
                assert!(worktree);
            }
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn deserialize_stop_session() {
        let json = r#"{"type":"stop_session","session_id":"xyz"}"#;
        let msg: AppMessage = serde_json::from_str(json).unwrap();
        match msg {
            AppMessage::StopSession { session_id } => assert_eq!(session_id, "xyz"),
            _ => panic!("wrong variant"),
        }
    }

    #[test]
    fn deserialize_list_sessions() {
        let json = r#"{"type":"list_sessions"}"#;
        let msg: AppMessage = serde_json::from_str(json).unwrap();
        assert!(matches!(msg, AppMessage::ListSessions));
    }

    #[test]
    fn session_info_omits_none_url() {
        let info = SessionInfo {
            id: "1".to_string(),
            name: "test".to_string(),
            directory: "/tmp".to_string(),
            status: "starting".to_string(),
            url: None,
            permission_mode: None,
            worktree: false,
        };
        let json_str = serde_json::to_string(&info).unwrap();
        assert!(!json_str.contains("url"));
    }

    #[test]
    fn session_info_includes_url_when_present() {
        let info = SessionInfo {
            id: "1".to_string(),
            name: "test".to_string(),
            directory: "/tmp".to_string(),
            status: "ready".to_string(),
            url: Some("https://example.com".to_string()),
            permission_mode: None,
            worktree: false,
        };
        let json: serde_json::Value = serde_json::to_value(&info).unwrap();
        assert_eq!(json["url"], "https://example.com");
    }

    #[test]
    fn sessions_list_serialization() {
        let msg = AppMessage::SessionsList {
            sessions: vec![SessionInfo {
                id: "s1".to_string(),
                name: "test".to_string(),
                directory: "/tmp".to_string(),
                status: "ready".to_string(),
                url: Some("https://example.com".to_string()),
                permission_mode: Some("plan".to_string()),
                worktree: true,
            }],
        };
        let json: serde_json::Value = serde_json::to_value(&msg).unwrap();
        assert_eq!(json["type"], "sessions_list");
        assert_eq!(json["sessions"][0]["id"], "s1");
        assert_eq!(json["sessions"][0]["permission_mode"], "plan");
        assert_eq!(json["sessions"][0]["worktree"], true);
    }
}
