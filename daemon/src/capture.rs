use regex::Regex;
use tokio::io::{AsyncBufReadExt, BufReader, Lines};
use tokio::process::{Child, ChildStdout};

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

    let url_regex =
        Regex::new(r"https://claude\.ai/code\?bridge=env_[a-zA-Z0-9]+").expect("valid regex");

    loop {
        tokio::select! {
            line_result = lines.next_line() => {
                match line_result {
                    Ok(Some(line)) => {
                        tracing::debug!(line = %line, "claude stdout");
                        if let Some(m) = url_regex.find(&line) {
                            return Ok(CaptureResult {
                                url: m.as_str().to_string(),
                                stdout_lines: lines,
                            });
                        }
                    }
                    Ok(None) => {
                        return Err("Process stdout closed before URL found".to_string());
                    }
                    Err(e) => {
                        return Err(format!("Error reading stdout: {e}"));
                    }
                }
            }
            status = child.wait() => {
                match status {
                    Ok(s) => return Err(format!("Process exited ({s}) before URL found")),
                    Err(e) => return Err(format!("Process wait error: {e}")),
                }
            }
        }
    }
}
