import Foundation
import RustyLib

@MainActor
final class MempoolManager: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let txid: String
        let hexPreview: String
    }

    @Published private(set) var entries: [Entry] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    func load(limit: Int = 20, torOnly: Bool = false) async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }

        do {
            let txs = try await fetchRecentMempoolTxs(limit: UInt32(limit), torOnly: torOnly)
            entries = txs.map { tx in
                let preview = String(tx.hex.prefix(64))
                return Entry(txid: tx.txid, hexPreview: preview)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }
}
