import Foundation
import XCTest
@testable import swiftyapp
import RustyLib

final class SwiftyAppTests: XCTestCase {
    func testBlastsRecentMempoolTransactionsThroughRustyLib() async throws {
        let torOnly = ProcessInfo.processInfo.environment["TOR_ONLY"] == "1"
        let relay = ProcessInfo.processInfo.environment["RELAY"] != "0"
        NSLog("============================================================")
        NSLog("SWIFTYAPP TEST START: blasting recent mempool transactions")
        NSLog("CONFIG: torOnly=\(torOnly) relay=\(relay)")

        let recent = try await fetchRecentTransactions()
        XCTAssertFalse(recent.isEmpty, "mempool recent returned no transactions")
        NSLog("mempool recent returned \(recent.count) transactions")

        guard let tx = recent.first else {
            throw XCTSkip("mempool recent returned no transactions")
        }

        NSLog("------------------------------------------------------------")
        NSLog("TX 1/1")
        NSLog("TXID: \(tx.txid)")
        let txHex = try await fetchRawTransactionHex(txid: tx.txid)
        NSLog("received \(txHex.count) hex characters for \(tx.txid)")
        let count = try await blastTransactionHex(txHex: txHex, torOnly: torOnly, relay: relay)
        NSLog("blasted \(tx.txid) to \(count) nodes torOnly=\(torOnly) relay=\(relay)")

        NSLog("SWIFTYAPP TEST COMPLETE: blasted 1 recent mempool transaction")
        NSLog("============================================================")
    }
}

private struct RecentTransaction: Decodable {
    let txid: String
}

private func fetchRecentTransactions() async throws -> [RecentTransaction] {
    let url = mempoolBaseURL(torOnly: ProcessInfo.processInfo.environment["TOR_ONLY"] == "1")
        .appendingPathComponent("api/mempool/recent")
    NSLog("GET \(url.absoluteString)")
    let (data, response) = try await URLSession.shared.data(from: url)
    try validateHTTPResponse(response, expectedContentType: nil)
    return try JSONDecoder().decode([RecentTransaction].self, from: data)
}

private func fetchRawTransactionHex(txid: String) async throws -> String {
    let url = mempoolBaseURL(torOnly: ProcessInfo.processInfo.environment["TOR_ONLY"] == "1")
        .appendingPathComponent("api/tx/\(txid)/hex")
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

private func mempoolBaseURL(torOnly: Bool) -> URL {
    if torOnly {
        return URL(string: "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion")!
    }
    return URL(string: "https://mempool.space")!
}
