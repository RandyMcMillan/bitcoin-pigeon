use std::collections::VecDeque;
use std::io::{self, Write};
use std::sync::{Mutex, OnceLock};

uniffi::setup_scaffolding!();

#[derive(Debug, uniffi::Error)]
#[uniffi(flat_error)]
pub enum BlastTransactionError {
    Message { message: String },
}

impl std::fmt::Display for BlastTransactionError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Message { message } => f.write_str(message),
        }
    }
}

impl std::error::Error for BlastTransactionError {}

static LOG_CAPTURE: OnceLock<Mutex<LogCaptureState>> = OnceLock::new();

#[derive(Default)]
struct LogCaptureState {
    pending: String,
    lines: VecDeque<String>,
}

struct CaptureWriter;

impl Write for CaptureWriter {
    fn write(&mut self, buf: &[u8]) -> io::Result<usize> {
        let capture = LOG_CAPTURE.get_or_init(|| Mutex::new(LogCaptureState::default()));
        let mut state = capture.lock().expect("log capture mutex poisoned");
        state.pending.push_str(&String::from_utf8_lossy(buf));

        while let Some(newline_index) = state.pending.find('\n') {
            let mut line = state.pending.drain(..=newline_index).collect::<String>();
            if line.ends_with('\n') {
                line.pop();
            }
            if line.ends_with('\r') {
                line.pop();
            }
            if !line.is_empty() {
                state.lines.push_back(line);
            }
        }

        Ok(buf.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

fn ensure_log_capture() {
    static LOGGER: OnceLock<()> = OnceLock::new();
    LOGGER.get_or_init(|| {
        let subscriber = tracing_subscriber::fmt()
            .with_ansi(false)
            .with_target(false)
            .without_time()
            .with_writer(|| CaptureWriter)
            .finish();

        let _ = tracing::subscriber::set_global_default(subscriber);
    });
}

#[uniffi::export]
pub fn set_tor_only(enabled: bool) {
    tx_pigeon::set_tor_only(enabled);
}

#[uniffi::export(async_runtime = "tokio")]
pub async fn blast_transaction_hex(
    tx_hex: String,
    tor_only: bool,
    relay: bool,
) -> Result<u32, BlastTransactionError> {
    ensure_log_capture();
    tx_pigeon::blast_transaction_hex(&tx_hex, tor_only, relay, None)
        .await
        .map(|count| count as u32)
        .map_err(|error| BlastTransactionError::Message {
            message: error.to_string(),
        })
}

#[uniffi::export]
pub fn drain_blast_logs() -> Vec<String> {
    let capture = LOG_CAPTURE.get_or_init(|| Mutex::new(LogCaptureState::default()));
    let mut state = capture.lock().expect("log capture mutex poisoned");
    if !state.pending.is_empty() {
        let pending = std::mem::take(&mut state.pending);
        if !pending.is_empty() {
            state.lines.push_back(pending);
        }
    }
    state.lines.drain(..).collect()
}
