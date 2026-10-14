import Foundation
import XCTest
import RustyLib

final class RustyLibTests: XCTestCase {
    func testComposesCustomProtocolIDs() {
        XCTAssertEqual(composeProtocolID(prefix: "custom_protocol", version: "0.0.1"), "custom_protocol/0.0.1")
        XCTAssertEqual(composeProtocolID(prefix: "/custom_protocol/", version: "/0.0.1"), "custom_protocol/0.0.1")
    }

    func testBlastsRecentMempoolTransactions() async throws {
        let torOnly = ProcessInfo.processInfo.environment["TOR_ONLY"] == "1"
        let relay = ProcessInfo.processInfo.environment["RELAY"] != "0"
        NSLog("============================================================")
        NSLog("TEST START: blasting recent mempool transactions")
        NSLog("CONFIG: torOnly=\(torOnly) relay=\(relay)")
        NSLog("STEP 1: fetching recent transaction list from mempool.space")
        let recent = try await fetchRecentTransactions()
        XCTAssertFalse(recent.isEmpty, "mempool recent returned no transactions")
        NSLog("STEP 1 COMPLETE: mempool recent returned \(recent.count) transactions")

        for (index, tx) in recent.enumerated() {
            NSLog("------------------------------------------------------------")
            NSLog("TX \(index + 1)/\(recent.count)")
            NSLog("TXID: \(tx.txid)")
            NSLog("STEP 2: fetching raw hex from mempool.space/api/tx/<txid>/hex")
            let txHex = try await fetchRawTransactionHex(txid: tx.txid)
            NSLog("STEP 2 COMPLETE: received \(txHex.count) hex characters for \(tx.txid)")
            NSLog("STEP 3: blasting transaction hex to peers")
            let count = try await blastTransactionHex(txHex: txHex, torOnly: torOnly, relay: relay)
            NSLog("STEP 3 COMPLETE: blasted \(tx.txid) to \(count) nodes torOnly=\(torOnly) relay=\(relay)")
        }
        NSLog("TEST COMPLETE: blasted \(recent.count) recent mempool transactions")
        NSLog("============================================================")
    }
}

private struct RecentTransaction: Decodable {
    let txid: String
}

private func fetchRecentTransactions() async throws -> [RecentTransaction] {
    let url = URL(string: "https://mempool.space/api/mempool/recent")!
    NSLog("GET \(url.absoluteString)")
    let (data, response) = try await URLSession.shared.data(from: url)
    try validateHTTPResponse(response, expectedContentType: nil)
    return try JSONDecoder().decode([RecentTransaction].self, from: data)
}

private func fetchRawTransactionHex(txid: String) async throws -> String {
    let url = URL(string: "https://mempool.space/api/tx/\(txid)/hex")!
    NSLog("GET \(url.absoluteString)")
    let (data, response) = try await URLSession.shared.data(from: url)
    try validateHTTPResponse(response, expectedContentType: "text/plain")
    guard let txHex = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !txHex.isEmpty else {
        throw XCTSkip("mempool returned an empty tx hex for \(txid)")
    }
    return txHex
}

private func validateHTTPResponse(_ response: URLResponse, expectedContentType: String?) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw XCTSkip("unexpected non-HTTP response")
    }
    guard (200..<300).contains(httpResponse.statusCode) else {
        throw XCTSkip("mempool returned HTTP \(httpResponse.statusCode)")
    }
    if let expectedContentType, let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type") {
        XCTAssertTrue(
            contentType.contains(expectedContentType),
            "expected content type to include \(expectedContentType), got \(contentType)"
        )
    }
}
