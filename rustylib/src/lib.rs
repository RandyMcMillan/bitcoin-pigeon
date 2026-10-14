use std::collections::VecDeque;
use std::io::{self, Write};
use std::sync::{Mutex, OnceLock};

use rand::prelude::IndexedRandom;
use tracing::info;
use tx_pigeon::topic::{
    compose_protocol_id, spawn_gossip_client, spawn_topic_network, TopicConfig as RustTopicConfig,
    TopicEvent as RustTopicEvent, TopicRelayHandle,
};

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

#[uniffi::export(async_runtime = "tokio")]
pub async fn auto_broadcast_recent_transaction(
    tor_only: bool,
    relay: bool,
) -> Result<u32, BlastTransactionError> {
    ensure_log_capture();
    let txs = tx_pigeon::mempool::fetch_recent_tx_hexes(20, tor_only)
        .await
        .map_err(|error| BlastTransactionError::Message {
            message: error.to_string(),
        })?;

    let (txid, tx_hex) = txs
        .choose(&mut rand::rng())
        .cloned()
        .ok_or_else(|| BlastTransactionError::Message {
            message: "no recent transactions were available for auto-broadcast".to_string(),
        })?;

    info!(%txid, "Rust auto-broadcast selected recent transaction");

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

#[derive(Debug, uniffi::Error)]
#[uniffi(flat_error)]
pub enum PigeonError {
    Message { message: String },
}

impl std::fmt::Display for PigeonError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Message { message } => f.write_str(message),
        }
    }
}

impl std::error::Error for PigeonError {}

fn pigeon_error(error: impl std::fmt::Display) -> PigeonError {
    PigeonError::Message {
        message: error.to_string(),
    }
}

/// FFI-friendly configuration for a bitcoin-pigeon topic node.
#[derive(uniffi::Record)]
pub struct TopicConfig {
    pub bootstrap_peers: Vec<String>,
    pub listen_addr: String,
    pub mdns: bool,
    pub relay_server: bool,
    pub flood_publish: bool,
    pub protocol: Option<String>,
    pub protocol_version: Option<String>,
}

impl TopicConfig {
    fn into_rust(self) -> Result<RustTopicConfig, PigeonError> {
        let mut bootstrap_peers = Vec::with_capacity(self.bootstrap_peers.len());
        for addr in self.bootstrap_peers {
            bootstrap_peers.push(addr.parse().map_err(pigeon_error)?);
        }
        Ok(RustTopicConfig {
            bootstrap_peers,
            listen_addr: self.listen_addr.parse().map_err(pigeon_error)?,
            mdns: self.mdns,
            relay_server: self.relay_server,
            flood_publish: self.flood_publish,
            protocol: self.protocol,
            protocol_version: self.protocol_version,
        })
    }
}

/// FFI-friendly event emitted by a topic node.
#[derive(uniffi::Enum)]
pub enum TopicEvent {
    Message { txid: String, hex: String },
    Subscribed { peer_id: String },
    Unsubscribed { peer_id: String },
    PeerDiscovered { peer_id: String, addr: String },
    PeerExpired { peer_id: String },
    Listening { address: String },
    Identified { peer_id: String, agent_version: String },
}

impl From<RustTopicEvent> for TopicEvent {
    fn from(event: RustTopicEvent) -> Self {
        match event {
            RustTopicEvent::Message { txid, hex } => TopicEvent::Message { txid, hex },
            RustTopicEvent::Subscribed { peer_id } => TopicEvent::Subscribed { peer_id },
            RustTopicEvent::Unsubscribed { peer_id } => TopicEvent::Unsubscribed { peer_id },
            RustTopicEvent::PeerDiscovered { peer_id, addr } => {
                TopicEvent::PeerDiscovered { peer_id, addr }
            }
            RustTopicEvent::PeerExpired { peer_id } => TopicEvent::PeerExpired { peer_id },
            RustTopicEvent::Listening { address } => TopicEvent::Listening { address },
            RustTopicEvent::Identified {
                peer_id,
                agent_version,
            } => TopicEvent::Identified {
                peer_id,
                agent_version,
            },
        }
    }
}

/// Handle to a spawned topic network. Keeps the swarm alive and exposes a
/// non-blocking event channel.
#[derive(uniffi::Object)]
pub struct TopicNetwork {
    handle: Option<TopicRelayHandle>,
    events: Mutex<Option<tokio::sync::mpsc::Receiver<RustTopicEvent>>>,
}

#[uniffi::export(async_runtime = "tokio")]
impl TopicNetwork {
    /// Publish a transaction (hex) to the topic.
    pub async fn publish(&self, tx_hex: String) -> Result<(), PigeonError> {
        match &self.handle {
            Some(handle) => handle.publish(tx_hex).await.map_err(pigeon_error),
            None => Err(PigeonError::Message {
                message: "observer topic network cannot publish".to_string(),
            }),
        }
    }

    /// Local peer id as a base58 string.
    pub fn local_peer_id(&self) -> Option<String> {
        self.handle.as_ref().map(|h| h.local_peer_id().to_string())
    }

    /// Poll for the next event, returning immediately if none is available.
    pub fn try_next_event(&self) -> Option<TopicEvent> {
        let mut guard = self.events.lock().ok()?;
        let rx = guard.as_mut()?;
        match rx.try_recv() {
            Ok(event) => Some(event.into()),
            Err(_) => None,
        }
    }
}

/// Spawn a topic node that publishes and rebroadcasts received transactions.
#[uniffi::export(async_runtime = "tokio")]
pub async fn spawn_topic_network_ffi(
    label: String,
    tor_only: bool,
    config: TopicConfig,
) -> Result<std::sync::Arc<TopicNetwork>, PigeonError> {
    let config = config.into_rust()?;
    let (handle, events) = spawn_topic_network(label, tor_only, config)
        .await
        .map_err(pigeon_error)?;
    Ok(std::sync::Arc::new(TopicNetwork {
        handle: Some(handle),
        events: Mutex::new(Some(events)),
    }))
}

/// Spawn a passive gossip observer.
#[uniffi::export(async_runtime = "tokio")]
pub async fn spawn_gossip_client_ffi(
    label: String,
    tor_only: bool,
    show_local: bool,
    show_remote: bool,
    config: TopicConfig,
) -> Result<std::sync::Arc<TopicNetwork>, PigeonError> {
    let config = config.into_rust()?;
    let events = spawn_gossip_client(label, tor_only, show_local, show_remote, config)
        .await
        .map_err(pigeon_error)?;
    Ok(std::sync::Arc::new(TopicNetwork {
        handle: None,
        events: Mutex::new(Some(events)),
    }))
}

/// A recent mempool entry returned by public mempool APIs.
#[derive(uniffi::Record)]
pub struct MempoolTx {
    pub txid: String,
    pub hex: String,
}

/// Fetch recent transactions from public mempool APIs.
#[uniffi::export(async_runtime = "tokio")]
pub async fn fetch_recent_mempool_txs(
    limit: u32,
    tor_only: bool,
) -> Result<Vec<MempoolTx>, PigeonError> {
    let txs = tx_pigeon::mempool::fetch_recent_tx_hexes(limit as usize, tor_only)
        .await
        .map_err(pigeon_error)?;
    Ok(txs
        .into_iter()
        .map(|(txid, hex)| MempoolTx { txid, hex })
        .collect())
}

/// Return the shared bitcoin-pigeon consensus mempool accumulated from
/// gossipsub messages received by this process.
#[uniffi::export]
pub fn get_shared_mempool_txs() -> Vec<MempoolTx> {
    tx_pigeon::topic::get_shared_mempool_txs()
        .into_iter()
        .map(|(txid, hex)| MempoolTx { txid, hex })
        .collect()
}

/// Compose a gossipsub protocol id from a prefix and version.
#[uniffi::export]
pub fn compose_protocol_id_ffi(prefix: String, version: String) -> String {
    compose_protocol_id(&prefix, &version)
}

/// Fetch recent transactions from libre relay peers, returning their hex.
#[uniffi::export(async_runtime = "tokio")]
pub async fn fetch_transaction_hexes(
    limit: u32,
    tor_only: bool,
    relay: bool,
) -> Result<Vec<String>, PigeonError> {
    let txs = tx_pigeon::fetch_transactions(limit as usize, tor_only, relay)
        .await
        .map_err(pigeon_error)?;
    Ok(txs.into_iter().map(|tx| bitcoin::consensus::encode::serialize_hex(&tx)).collect())
}

/// Continuously fetch and rebroadcast transactions from libre relay peers.
#[uniffi::export(async_runtime = "tokio")]
pub async fn relay_transactions_ffi(
    limit: u32,
    tor_only: bool,
    relay: bool,
    interval_secs: u64,
) -> Result<(), PigeonError> {
    tx_pigeon::relay_transactions(limit as usize, tor_only, relay, interval_secs)
        .await
        .map_err(pigeon_error)
}

/// Fetch the current Bitcoin blockheight from public mempool APIs.
#[uniffi::export(async_runtime = "tokio")]
pub async fn fetch_blockheight(tor_only: bool) -> Result<u64, PigeonError> {
    tx_pigeon::mempool::fetch_blockheight(tor_only)
        .await
        .map_err(pigeon_error)
}

/// Metrics for the bitcoin-pigeon BFT logical clock.
#[derive(uniffi::Record)]
pub struct ClockMetrics {
    pub slew_rate: f64,
    pub offset_ms: i64,
    pub status: String,
    pub last_sync_secs_ago: u64,
}

impl From<tx_pigeon::time::ClockMetrics> for ClockMetrics {
    fn from(m: tx_pigeon::time::ClockMetrics) -> Self {
        Self {
            slew_rate: m.slew_rate,
            offset_ms: m.offset_ms,
            status: format!("{:?}", m.status),
            last_sync_secs_ago: m.last_sync_secs_ago,
        }
    }
}

/// Start the P2P BFT time synchronization daemon.
///
/// Spawns the long-running daemon on the Tokio runtime and returns immediately
/// so callers can treat it as an on/off toggle.
#[uniffi::export(async_runtime = "tokio")]
pub async fn start_time_sync_daemon(storage_path: Option<String>) -> Result<(), PigeonError> {
    tokio::spawn(async move {
        if let Err(err) = tx_pigeon::time::run_time_sync_daemon(storage_path).await {
            eprintln!("bitcoin-pigeon time sync daemon exited: {err}");
        }
    });
    Ok(())
}

/// Return the current logical UTC time according to the shared clock.
#[uniffi::export]
pub fn get_logical_utc() -> String {
    tx_pigeon::time::get_logical_utc()
}

/// Return the current clock metrics.
#[uniffi::export]
pub fn get_clock_metrics() -> ClockMetrics {
    tx_pigeon::time::get_clock_metrics().into()
}
