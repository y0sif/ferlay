use serde::{Deserialize, Serialize};

/// Application-level messages exchanged between daemon and mobile app (via relay).
/// These are wrapped inside `ControlMessage::Relay { payload }`.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AppMessage {
    #[serde(rename = "start_session")]
    StartSession { directory: String, name: String },

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
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SessionInfo {
    pub id: String,
    pub name: String,
    pub directory: String,
    pub status: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}
