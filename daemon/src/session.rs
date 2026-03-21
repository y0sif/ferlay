use std::collections::HashMap;
use std::process::Stdio;
use std::sync::Arc;
use tokio::process::{Child, Command};
use tokio::sync::mpsc;

use crate::capture;
use crate::crypto::CryptoState;
use crate::messages::{AppMessage, SessionInfo};

#[derive(Debug, Clone, PartialEq)]
pub enum SessionStatus {
    Starting,
    Ready,
    #[allow(dead_code)]
    Active,
    Finished,
    Crashed,
}

impl SessionStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Starting => "starting",
            Self::Ready => "ready",
            Self::Active => "active",
            Self::Finished => "finished",
            Self::Crashed => "crashed",
        }
    }
}

struct Session {
    id: String,
    name: String,
    directory: String,
    status: SessionStatus,
    url: Option<String>,
    child: Option<Child>,
}

pub struct SessionManager {
    sessions: HashMap<String, Session>,
    relay_tx: mpsc::UnboundedSender<String>,
    crypto: Option<Arc<CryptoState>>,
}

impl SessionManager {
    pub fn new(
        relay_tx: mpsc::UnboundedSender<String>,
        crypto: Option<Arc<CryptoState>>,
    ) -> Self {
        Self {
            sessions: HashMap::new(),
            relay_tx,
            crypto,
        }
    }

    pub async fn start(&mut self, directory: String, name: String) {
        let session_id = uuid::Uuid::new_v4().to_string();
        tracing::info!(session_id = %session_id, name = %name, dir = %directory, "Starting session");

        // Expand ~ in directory path
        let expanded_dir = shellexpand_tilde(&directory);

        let child_result = Command::new("claude")
            .args(["remote-control", "--name", &name, "--verbose", "--spawn=same-dir"])
            .current_dir(&expanded_dir)
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true)
            .spawn();

        let mut child = match child_result {
            Ok(c) => c,
            Err(e) => {
                tracing::error!(error = %e, "Failed to spawn claude");
                self.send_status(&session_id, "crashed", Some(format!("spawn failed: {e}")));
                return;
            }
        };

        let session = Session {
            id: session_id.clone(),
            name: name.clone(),
            directory: directory.clone(),
            status: SessionStatus::Starting,
            url: None,
            child: None,
        };
        self.sessions.insert(session_id.clone(), session);
        self.send_status(&session_id, "starting", None);

        // Capture URL from stdout
        match capture::wait_for_url(&mut child).await {
            Ok(capture_result) => {
                tracing::info!(session_id = %session_id, url = %capture_result.url, "URL captured");

                let url = capture_result.url.clone();

                if let Some(s) = self.sessions.get_mut(&session_id) {
                    s.status = SessionStatus::Ready;
                    s.url = Some(url.clone());
                    s.child = Some(child);
                }

                self.send_relay(&AppMessage::SessionReady {
                    session_id: session_id.clone(),
                    url,
                    name,
                });

                // Monitor process in background (keeps stdout alive)
                self.monitor_process(session_id, capture_result.stdout_lines);
            }
            Err(e) => {
                tracing::error!(session_id = %session_id, error = %e, "Failed to capture URL");
                if let Some(s) = self.sessions.get_mut(&session_id) {
                    s.status = SessionStatus::Crashed;
                }
                self.send_status(&session_id, "crashed", Some(e));
            }
        }
    }

    pub async fn stop(&mut self, session_id: &str) {
        if let Some(session) = self.sessions.get_mut(session_id) {
            tracing::info!(session_id = %session_id, "Stopping session");
            if let Some(mut child) = session.child.take() {
                let _ = child.kill().await;
                let _ = child.wait().await;
            }
            session.status = SessionStatus::Finished;
            self.send_status(session_id, "finished", None);
        } else {
            tracing::warn!(session_id = %session_id, "Session not found");
        }
    }

    pub fn list(&self) -> Vec<SessionInfo> {
        self.sessions
            .values()
            .map(|s| SessionInfo {
                id: s.id.clone(),
                name: s.name.clone(),
                directory: s.directory.clone(),
                status: s.status.as_str().to_string(),
                url: s.url.clone(),
            })
            .collect()
    }

    /// Marks a session as finished/crashed when its process exits.
    fn monitor_process(
        &mut self,
        session_id: String,
        stdout_lines: tokio::io::Lines<tokio::io::BufReader<tokio::process::ChildStdout>>,
    ) {
        let Some(session) = self.sessions.get_mut(&session_id) else {
            return;
        };
        let Some(child) = session.child.take() else {
            return;
        };

        let relay_tx = self.relay_tx.clone();
        let crypto = self.crypto.clone();
        tokio::spawn(async move {
            monitor_child(child, session_id, relay_tx, crypto, stdout_lines).await;
        });
    }

    pub fn send_sessions_list(&self, sessions: Vec<SessionInfo>) {
        self.send_relay(&AppMessage::SessionsList { sessions });
    }

    /// Sends an arbitrary AppMessage back to the app (used for ping/pong etc.).
    pub fn send_message(&self, msg: &AppMessage) {
        self.send_relay(msg);
    }

    fn send_status(&self, session_id: &str, status: &str, error: Option<String>) {
        self.send_relay(&AppMessage::SessionStatus {
            session_id: session_id.to_string(),
            status: status.to_string(),
            error,
        });
    }

    fn send_relay(&self, msg: &AppMessage) {
        if let Some(json) = send_encrypted_relay(msg, self.crypto.as_deref()) {
            let _ = self.relay_tx.send(json);
        }
    }
}

/// Encrypts an AppMessage and wraps it in a ControlMessage::Relay.
/// Encryption is mandatory — returns None if crypto is unavailable or encryption fails.
fn send_encrypted_relay(msg: &AppMessage, crypto: Option<&CryptoState>) -> Option<String> {
    let Some(crypto) = crypto else {
        tracing::error!("Cannot send relay message: no encryption key established");
        return None;
    };

    let plaintext = serde_json::to_string(msg).unwrap();
    match crypto.encrypt(plaintext.as_bytes()) {
        Ok(encrypted) => {
            let payload = serde_json::Value::String(encrypted);
            let control = furlay_shared::messages::ControlMessage::Relay { payload };
            Some(serde_json::to_string(&control).unwrap())
        }
        Err(e) => {
            tracing::error!(error = %e, "Encryption failed, dropping message");
            None
        }
    }
}

async fn monitor_child(
    mut child: Child,
    session_id: String,
    relay_tx: mpsc::UnboundedSender<String>,
    crypto: Option<Arc<CryptoState>>,
    mut stdout_lines: tokio::io::Lines<tokio::io::BufReader<tokio::process::ChildStdout>>,
) {
    // Keep draining stdout to avoid blocking the process and to keep the pipe open
    let status = loop {
        tokio::select! {
            line = stdout_lines.next_line() => {
                match line {
                    Ok(Some(line)) => {
                        tracing::debug!(session_id = %session_id, line = %line, "claude stdout");
                    }
                    Ok(None) | Err(_) => {
                        // stdout closed, wait for process to exit
                        break child.wait().await;
                    }
                }
            }
            status = child.wait() => {
                break status;
            }
        }
    };
    let (status_str, error) = match status {
        Ok(s) if s.success() => ("finished", None),
        Ok(s) => (
            "crashed",
            Some(format!(
                "process exited with code {}",
                s.code().unwrap_or(-1)
            )),
        ),
        Err(e) => ("crashed", Some(format!("wait error: {e}"))),
    };

    tracing::info!(session_id = %session_id, status = status_str, "Session process exited");

    let msg = AppMessage::SessionStatus {
        session_id,
        status: status_str.to_string(),
        error,
    };
    if let Some(json) = send_encrypted_relay(&msg, crypto.as_deref()) {
        let _ = relay_tx.send(json);
    }
}

fn shellexpand_tilde(path: &str) -> String {
    if let Some(rest) = path.strip_prefix("~/") {
        if let Some(home) = dirs::home_dir() {
            return home.join(rest).to_string_lossy().to_string();
        }
    }
    path.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn session_status_as_str() {
        assert_eq!(SessionStatus::Starting.as_str(), "starting");
        assert_eq!(SessionStatus::Ready.as_str(), "ready");
        assert_eq!(SessionStatus::Active.as_str(), "active");
        assert_eq!(SessionStatus::Finished.as_str(), "finished");
        assert_eq!(SessionStatus::Crashed.as_str(), "crashed");
    }

    #[test]
    fn tilde_expansion() {
        let expanded = shellexpand_tilde("~/Projects/ferlay");
        let home = dirs::home_dir().unwrap();
        assert_eq!(
            expanded,
            home.join("Projects/ferlay").to_string_lossy().to_string()
        );
    }

    #[test]
    fn absolute_path_unchanged() {
        assert_eq!(shellexpand_tilde("/usr/local/bin"), "/usr/local/bin");
    }

    #[test]
    fn relative_path_unchanged() {
        assert_eq!(shellexpand_tilde("relative/path"), "relative/path");
    }

    #[test]
    fn bare_tilde_unchanged() {
        // "~" without trailing "/" is not expanded
        assert_eq!(shellexpand_tilde("~"), "~");
    }

    #[test]
    fn tilde_in_middle_unchanged() {
        assert_eq!(shellexpand_tilde("/home/~/test"), "/home/~/test");
    }
}
