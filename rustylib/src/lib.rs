uniffi::setup_scaffolding!();

#[uniffi::export(async_runtime = "tokio")]
pub async fn blast_transaction_hex(tx_hex: String) -> Result<u32, String> {
    tx_pigeon::blast_transaction_hex(&tx_hex)
        .await
        .map(|count| count as u32)
        .map_err(|error| error.to_string())
}
