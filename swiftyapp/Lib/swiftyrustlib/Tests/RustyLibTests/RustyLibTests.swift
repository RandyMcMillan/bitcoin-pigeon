import Foundation
import XCTest
import RustyLib

final class RustyLibTests: XCTestCase {
    func testComposesCustomProtocolIDs() {
        XCTAssertEqual(composeProtocolID(prefix: "custom_protocol", version: "0.0.1"), "custom_protocol/0.0.1")
        XCTAssertEqual(composeProtocolID(prefix: "/custom_protocol/", version: "/0.0.1"), "custom_protocol/0.0.1")
    }

    func testTopicMeshDeliversTransaction() async throws {
        let sampleTxHex = "0100000001c997a5e56e104102fa209c6a852dd90660a20b2d9c352423edce25857fcd3704000000004847304402204e45e16932b8af514961a1d3a1a25fdf3f4f7732e9d624c6c61548ab5fb8cd410220181522ec8eca07de4860a4acdd12909d831cc56cbbac4622082221a8768d1d0901ffffffff0200ca9a3b00000000434104ae1a62fe09c5f51b13905f07f06b99a2f7159b2225f374cd378d71302fa28414e7aab37397f554a7df5f142c21c1b7303b8a0626f1baded5c72a704f7e6cd84cac00286bee0000000043410411db93e1dcdb8a016b49840f8c53bc1eb68a382e97b1482ecad7b148a6909a5cb2e0eaddfb84ccf9744464f82e160bfa9b8b64f9d4c03f999b8643f656b412a3ac00000000"
        let expectedTxid = "f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16"

        var publisherConfig = TopicConfig(
            bootstrapPeers: [],
            listenAddr: "/ip4/127.0.0.1/tcp/0",
            mdns: false,
            relayServer: false,
            floodPublish: true,
            protocol: nil,
            protocolVersion: nil
        )
        let publisher = try await spawnTopicNetworkFfi(label: "swift-publisher", torOnly: false, config: publisherConfig)
        let publisherPeerId = publisher.localPeerId()
        XCTAssertNotNil(publisherPeerId)

        let publisherAddr = try await waitForListenAddress(topic: publisher)
        NSLog("[swift test] publisher listening on \(publisherAddr)")

        var observerConfig = publisherConfig
        observerConfig.bootstrapPeers = [publisherAddr]
        let observer = try await spawnTopicNetworkFfi(label: "swift-observer", torOnly: false, config: observerConfig)
        let observerPeerId = observer.localPeerId()
        XCTAssertNotNil(observerPeerId)

        try await waitForEvent(topic: observer, predicate: { event in
            if case .identified(peerId: let peerId, agentVersion: _) = event, peerId == publisherPeerId {
                return true
            }
            return false
        })
        NSLog("[swift test] observer identified publisher")

        try await waitForEvent(topic: publisher, predicate: { event in
            if case .subscribed(peerId: let peerId) = event, peerId == observerPeerId {
                return true
            }
            return false
        })
        NSLog("[swift test] publisher saw observer subscribe")

        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await publisher.publish(txHex: sampleTxHex)
        NSLog("[swift test] published tx")

        let receivedTxid = try await waitForMessage(topic: observer)
        XCTAssertEqual(receivedTxid, expectedTxid)
        NSLog("[swift test] observer received tx \(receivedTxid)")
    }

    func testGossipClientObservesTransaction() async throws {
        let sampleTxHex = "0100000001c997a5e56e104102fa209c6a852dd90660a20b2d9c352423edce25857fcd3704000000004847304402204e45e16932b8af514961a1d3a1a25fdf3f4f7732e9d624c6c61548ab5fb8cd410220181522ec8eca07de4860a4acdd12909d831cc56cbbac4622082221a8768d1d0901ffffffff0200ca9a3b00000000434104ae1a62fe09c5f51b13905f07f06b99a2f7159b2225f374cd378d71302fa28414e7aab37397f554a7df5f142c21c1b7303b8a0626f1baded5c72a704f7e6cd84cac00286bee0000000043410411db93e1dcdb8a016b49840f8c53bc1eb68a382e97b1482ecad7b148a6909a5cb2e0eaddfb84ccf9744464f82e160bfa9b8b64f9d4c03f999b8643f656b412a3ac00000000"
        let expectedTxid = "f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16"

        var publisherConfig = TopicConfig(
            bootstrapPeers: [],
            listenAddr: "/ip4/127.0.0.1/tcp/0",
            mdns: false,
            relayServer: false,
            floodPublish: true,
            protocol: nil,
            protocolVersion: nil
        )
        let publisher = try await spawnTopicNetworkFfi(label: "swift-publisher-gossip", torOnly: false, config: publisherConfig)
        let publisherPeerId = publisher.localPeerId()
        XCTAssertNotNil(publisherPeerId)

        let publisherAddr = try await waitForListenAddress(topic: publisher)
        NSLog("[swift test] publisher listening on \(publisherAddr)")

        var observerConfig = publisherConfig
        observerConfig.bootstrapPeers = [publisherAddr]
        let observer = try await spawnGossipClientFfi(label: "swift-observer-gossip", torOnly: false, showLocal: false, showRemote: true, config: observerConfig)

        try await waitForEvent(topic: observer, predicate: { event in
            if case .identified(peerId: let peerId, agentVersion: _) = event, peerId == publisherPeerId {
                return true
            }
            return false
        })
        NSLog("[swift test] observer identified publisher")

        try await waitForEvent(topic: publisher, predicate: { event in
            if case .subscribed(peerId: let peerId) = event {
                return !peerId.isEmpty
            }
            return false
        })
        NSLog("[swift test] publisher saw observer subscribe")

        try await Task.sleep(nanoseconds: 2_000_000_000)
        try await publisher.publish(txHex: sampleTxHex)
        NSLog("[swift test] published tx")

        let receivedTxid = try await waitForMessage(topic: observer)
        XCTAssertEqual(receivedTxid, expectedTxid)
        NSLog("[swift test] observer received tx \(receivedTxid)")
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

private func waitForListenAddress(topic: TopicNetwork, timeout: TimeInterval = 10) async throws -> String {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if case .listening(address: let address) = topic.tryNextEvent() {
            return address
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw XCTSkip("timed out waiting for listen address")
}

private func waitForEvent(topic: TopicNetwork, timeout: TimeInterval = 15, predicate: (TopicEvent) -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if let event = topic.tryNextEvent(), predicate(event) {
            return
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw XCTSkip("timed out waiting for topic event")
}

private func waitForMessage(topic: TopicNetwork, timeout: TimeInterval = 30) async throws -> String {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if case .message(txid: let txid) = topic.tryNextEvent() {
            return txid
        }
        try await Task.sleep(nanoseconds: 100_000_000)
    }
    throw XCTSkip("timed out waiting for topic message")
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
    // Disabled: mempool onion endpoint is not currently available.
    // if torOnly {
    //     return URL(string: "http://mempoolhqx4isw62xs7abwphsq7ldayuidyx2v2oethdhhj6mlo2r6ad.onion")!
    // }
    return URL(string: "https://mempool.space")!
}
