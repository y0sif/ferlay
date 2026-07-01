use regex::Regex;
use std::sync::LazyLock;
use tokio::io::{AsyncBufReadExt, BufReader, Lines};
use tokio::process::{Child, ChildStdout};

static URL_REGEX: LazyLock<Regex> = LazyLock::new(|| {
    // Claude Code renamed the session URL query param from `bridge` to
    // `environment` (seen in 2.1.x). Accept both so we work across versions.
    Regex::new(r"https://claude\.ai/code\?(?:bridge|environment)=env_[a-zA-Z0-9]+")
        .expect("valid regex")
});

/// Extracts a Claude session URL from a line of stdout output.
pub fn extract_url(line: &str) -> Option<String> {
    URL_REGEX.find(line).map(|m| m.as_str().to_string())
}

/// Result of URL capture: the URL and the stdout reader (must be kept alive
/// to avoid closing the pipe and killing the claude process).
pub struct CaptureResult {
    pub url: String,
    pub stdout_lines: Lines<BufReader<ChildStdout>>,
}

/// Reads stdout from a claude process line by line, looking for the session URL.
/// Returns the URL and the stdout reader on success.
/// The caller MUST keep `stdout_lines` alive for the lifetime of the process.
pub async fn wait_for_url(child: &mut Child) -> Result<CaptureResult, String> {
    let stdout = child
        .stdout
        .take()
        .ok_or_else(|| "No stdout handle".to_string())?;
    let mut lines = BufReader::new(stdout).lines();

    loop {
        tokio::select! {
            line_result = lines.next_line() => {
                match line_result {
                    Ok(Some(line)) => {
                        tracing::debug!(line = %line, "claude stdout");
                        if let Some(url) = extract_url(&line) {
                            return Ok(CaptureResult {
                                url,
                                stdout_lines: lines,
                            });
                        }
                    }
                    Ok(None) => {
                        let hint = drain_stderr(child).await;
                        return Err(format!("Process stdout closed before URL found{hint}"));
                    }
                    Err(e) => {
                        return Err(format!("Error reading stdout: {e}"));
                    }
                }
            }
            status = child.wait() => {
                match status {
                    Ok(s) => {
                        let hint = drain_stderr(child).await;
                        return Err(format!("Process exited ({s}) before URL found{hint}"));
                    }
                    Err(e) => return Err(format!("Process wait error: {e}")),
                }
            }
        }
    }
}

/// Reads whatever is on the child's stderr (bounded, non-blocking-ish) so a
/// failure to capture the URL surfaces the real cause (e.g. "Workspace not
/// trusted"). Returns a "\nLast stderr:\n..." suffix, or "" if nothing useful.
async fn drain_stderr(child: &mut Child) -> String {
    let Some(stderr) = child.stderr.take() else {
        return String::new();
    };
    let mut reader = BufReader::new(stderr).lines();
    let mut collected: Vec<String> = Vec::new();
    // Cap the wait so a still-running process can't hang us here.
    let deadline = tokio::time::sleep(std::time::Duration::from_secs(2));
    tokio::pin!(deadline);
    loop {
        tokio::select! {
            line = reader.next_line() => match line {
                Ok(Some(l)) => {
                    if collected.len() >= 5 {
                        collected.remove(0);
                    }
                    collected.push(l);
                }
                _ => break,
            },
            _ = &mut deadline => break,
        }
    }
    if collected.is_empty() {
        String::new()
    } else {
        format!("\nLast stderr:\n{}", collected.join("\n"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_url_from_clean_line() {
        let line = "https://claude.ai/code?bridge=env_abc123DEF";
        assert_eq!(
            extract_url(line),
            Some("https://claude.ai/code?bridge=env_abc123DEF".to_string())
        );
    }

    #[test]
    fn extracts_url_with_environment_param() {
        // Real format printed by claude remote-control 2.1.x
        let line = "Continue coding in the Claude mobile app or https://claude.ai/code?environment=env_01CZbfW16GsUqzNvMBAL9oXQ";
        assert_eq!(
            extract_url(line),
            Some(
                "https://claude.ai/code?environment=env_01CZbfW16GsUqzNvMBAL9oXQ".to_string()
            )
        );
    }

    #[test]
    fn extracts_url_embedded_in_text() {
        let line = "Session ready: https://claude.ai/code?bridge=env_XyZ789 (click to open)";
        assert_eq!(
            extract_url(line),
            Some("https://claude.ai/code?bridge=env_XyZ789".to_string())
        );
    }

    #[test]
    fn extracts_url_with_ansi_prefix() {
        let line = "\x1b[32m[INFO]\x1b[0m https://claude.ai/code?bridge=env_test42";
        assert_eq!(
            extract_url(line),
            Some("https://claude.ai/code?bridge=env_test42".to_string())
        );
    }

    #[test]
    fn no_url_returns_none() {
        assert_eq!(extract_url("Starting claude process..."), None);
        assert_eq!(extract_url(""), None);
        assert_eq!(extract_url("https://example.com"), None);
    }

    #[test]
    fn rejects_invalid_bridge_format() {
        // Missing env_ prefix
        assert_eq!(
            extract_url("https://claude.ai/code?bridge=abc123"),
            None
        );
    }

    #[test]
    fn extracts_first_url_from_multiple() {
        let line = "https://claude.ai/code?bridge=env_FIRST https://claude.ai/code?bridge=env_SECOND";
        assert_eq!(
            extract_url(line),
            Some("https://claude.ai/code?bridge=env_FIRST".to_string())
        );
    }
}
