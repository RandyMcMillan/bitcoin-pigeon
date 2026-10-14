import Foundation
import RustyLib

private struct RecentTransaction: Decodable {
    let txid: String
}

enum MempoolSource: String, CaseIterable {
    case clearnet
    case bitcoinGobSV
    case tor

    var label: String {
        switch self {
        case .clearnet:
            return "mempool.space"
        case .bitcoinGobSV:
            return "bitcoin.gob.sv"
        case .tor:
            return "mempool onion"
        }
    }

    var baseURL: URL {
        switch self {
        case .clearnet:
            return URL(string: "https://mempool.space")!
        case .bitcoinGobSV:
            return URL(string: "https://bitcoin.gob.sv")!
        case .tor:
            return URL(string: "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion")!
        }
    }
}

private let duckDuckGoOnionURL = URL(string: "http://duckduckgogg42xjoc72x3sjasowoarfbgcmvfimaftt6twagswzczad.onion")!

struct MempoolBroadcastResult {
    let source: MempoolSource
    let txid: String
    let nodeCount: UInt32
}

enum MempoolBroadcastError: LocalizedError {
    case emptyRecentTransactions(source: MempoolSource)
    case noAvailableSources
    case unexpectedNonHTTPResponse
    case unexpectedHTTPStatus(Int)
    case unexpectedContentType(expected: String, actual: String)
    case emptyTxHex(txid: String)

    var errorDescription: String? {
        switch self {
        case let .emptyRecentTransactions(source):
            return "\(source.label) returned no recent transactions"
        case .noAvailableSources:
            return "No mempool sources are available"
        case .unexpectedNonHTTPResponse:
            return "Unexpected non-HTTP response from mempool"
        case let .unexpectedHTTPStatus(statusCode):
            return "mempool returned HTTP \(statusCode)"
        case let .unexpectedContentType(expected, actual):
            return "expected content type to include \(expected), got \(actual)"
        case let .emptyTxHex(txid):
            return "mempool returned an empty tx hex for \(txid)"
        }
    }
}

func broadcastRandomRecentTransaction(
    torOnly: Bool,
    relay: Bool,
    logger: ((String) -> Void)? = nil
) async throws -> MempoolBroadcastResult {
    if torOnly {
        _ = await probeTorConnectivity(logger: logger)
    }

    let sources: [MempoolSource]
    if torOnly {
        sources = [.tor]
    } else {
        sources = MempoolSource.allCases.shuffled()
    }

    logger?("Auto-broadcast: selected sources \(sources.map(\.label).joined(separator: ", "))")

    var lastError: Error?

    for source in sources {
        do {
            logger?("Auto-broadcast: fetching recent transactions from \(source.label)")
            let recent = try await fetchRecentTransactions(from: source)
            guard let tx = recent.randomElement() else {
                throw MempoolBroadcastError.emptyRecentTransactions(source: source)
            }

            logger?("Auto-broadcast: selected txid \(tx.txid) from \(source.label)")
            logger?("Auto-broadcast: fetching raw hex for \(tx.txid) from \(source.label)")
            let txHex = try await fetchRawTransactionHex(txid: tx.txid, source: source)
            logger?("Auto-broadcast: blasting \(tx.txid) torOnly=\(torOnly) relay=\(relay)")
            logger?("Auto-broadcast: relay mode is \(relay ? "enabled" : "disabled"); connecting to Libra relays.")
            defer {
                for line in drainBlastLogs() {
                    logger?(line)
                }
            }
            let nodeCount = try await blastTransactionHex(txHex: txHex, torOnly: torOnly, relay: relay)
            logger?("Auto-broadcast: blasted \(tx.txid) to \(nodeCount) nodes from \(source.label)")
            logger?("Auto-broadcast: relay connection cycle completed for \(tx.txid).")
            return MempoolBroadcastResult(source: source, txid: tx.txid, nodeCount: nodeCount)
        } catch {
            logger?("Auto-broadcast: source \(source.label) failed with \(error.localizedDescription)")
            lastError = error
        }
    }

    if let lastError {
        throw lastError
    }
    throw MempoolBroadcastError.noAvailableSources
}

private func probeTorConnectivity(logger: ((String) -> Void)? = nil) async -> Bool {
    logger?("Tor probe: checking DuckDuckGo onion reachability.")
    NSLog("AUTO GET \(duckDuckGoOnionURL.absoluteString)")

    do {
        let (data, response) = try await URLSession.shared.data(from: duckDuckGoOnionURL)
        try validateHTTPResponse(response, expectedContentType: nil)
        logger?("Tor probe: DuckDuckGo onion reachable (\(data.count) bytes).")
        return true
    } catch {
        logger?("Tor probe: DuckDuckGo onion failed with \(error.localizedDescription)")
        return false
    }
}

private func fetchRecentTransactions(from source: MempoolSource) async throws -> [RecentTransaction] {
    let url = source.baseURL.appendingPathComponent("api/mempool/recent")
    NSLog("AUTO GET \(url.absoluteString)")
    let (data, response) = try await URLSession.shared.data(from: url)
    try validateHTTPResponse(response, expectedContentType: nil)
    return try JSONDecoder().decode([RecentTransaction].self, from: data)
}

private func fetchRawTransactionHex(txid: String, source: MempoolSource) async throws -> String {
    let url = source.baseURL.appendingPathComponent("api/tx/\(txid)/hex")
    NSLog("AUTO GET \(url.absoluteString)")
    let (data, response) = try await URLSession.shared.data(from: url)
    try validateHTTPResponse(response, expectedContentType: "text/plain")
    guard let txHex = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !txHex.isEmpty else {
        throw MempoolBroadcastError.emptyTxHex(txid: txid)
    }
    return txHex
}

private func validateHTTPResponse(_ response: URLResponse, expectedContentType: String?) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw MempoolBroadcastError.unexpectedNonHTTPResponse
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
        throw MempoolBroadcastError.unexpectedHTTPStatus(httpResponse.statusCode)
    }
    if let expectedContentType, let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
        guard contentType.contains(expectedContentType) else {
            throw MempoolBroadcastError.unexpectedContentType(expected: expectedContentType, actual: contentType)
        }
    }
}
