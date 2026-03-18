use regex::Regex;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::Child;

/// Reads stdout from a claude process line by line, looking for the session URL.
/// Returns the URL when found, or an error if the process exits first.
pub async fn wait_for_url(child: &mut Child) -> Result<String, String> {
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
                            return Ok(m.as_str().to_string());
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
