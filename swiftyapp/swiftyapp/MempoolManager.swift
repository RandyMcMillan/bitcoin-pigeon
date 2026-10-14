import Foundation
import RustyLib

@MainActor
final class MempoolManager: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let txid: String
        let hexPreview: String
        let source: String
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    func load(limit: Int = 20, torOnly: Bool = false) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let apiTxs = try await fetchRecentMempoolTxs(limit: UInt32(limit), torOnly: torOnly)
            let sharedTxs = getSharedMempoolTxs()

            var merged: [String: Entry] = [:]

            for tx in sharedTxs {
                let preview = String(tx.hex.prefix(64))
                merged[tx.txid] = Entry(txid: tx.txid, hexPreview: preview, source: "bitcoin-pigeon consensus")
            }

            for tx in apiTxs {
                if merged[tx.txid] == nil {
                    let preview = String(tx.hex.prefix(64))
                    merged[tx.txid] = Entry(txid: tx.txid, hexPreview: preview, source: "mempool API")
                }
            }

            entries = Array(merged.values)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addPeerTx(txid: String, hex: String) {
        entries.removeAll { $0.txid == txid }
        let preview = String(hex.prefix(64))
        let entry = Entry(txid: txid, hexPreview: preview, source: "bitcoin-pigeon peer")
        entries.insert(entry, at: 0)
    }
}
