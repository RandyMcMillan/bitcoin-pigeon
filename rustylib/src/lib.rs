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

#[uniffi::export(async_runtime = "tokio")]
pub async fn blast_transaction_hex(
    tx_hex: String,
) -> Result<u32, BlastTransactionError> {
    tx_pigeon::blast_transaction_hex(&tx_hex)
        .await
        .map(|count| count as u32)
        .map_err(|error| BlastTransactionError::Message {
            message: error.to_string(),
        })
}
