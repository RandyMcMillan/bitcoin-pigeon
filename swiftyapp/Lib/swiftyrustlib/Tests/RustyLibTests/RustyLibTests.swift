import Foundation
import XCTest
import RustyLib

final class RustyLibTests: XCTestCase {
    func testBlastsRecentMempoolTransactions() async throws {
        let recent = try await fetchRecentTransactions()
        XCTAssertFalse(recent.isEmpty, "mempool recent returned no transactions")

        for tx in recent {
            let txHex = try await fetchTransactionHex(txid: tx.txid)
            _ = try await blastTransactionHex(txHex: txHex)
        }
    }
}

private struct RecentTransaction: Decodable {
    let txid: String
}

private func fetchRecentTransactions() async throws -> [RecentTransaction] {
    let url = URL(string: "https://mempool.space/api/mempool/recent")!
    let (data, response) = try await URLSession.shared.data(from: url)
    try validateHTTPResponse(response, expectedContentType: nil)
    return try JSONDecoder().decode([RecentTransaction].self, from: data)
}

private func fetchTransactionHex(txid: String) async throws -> String {
    let url = URL(string: "https://mempool.space/api/tx/\(txid)/hex")!
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
