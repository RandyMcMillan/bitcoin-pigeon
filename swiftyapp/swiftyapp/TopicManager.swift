import Foundation
import RustyLib

@MainActor
final class TopicManager: ObservableObject {
    struct Event: Identifiable {
        let id = UUID()
        let text: String
    }

    @Published private(set) var events: [Event] = []
    @Published private(set) var peerId: String?
    @Published private(set) var isTopicRunning = false
    @Published private(set) var isGossipRunning = false

    private var topicNetwork: TopicNetwork?
    private var gossipNetwork: TopicNetwork?
    private var topicEventTask: Task<Void, Never>?
    private var gossipEventTask: Task<Void, Never>?

    func startTopicNode(
        torOnly: Bool,
        protocolPrefix: String?,
        protocolVersion: String?
    ) async throws {
        guard !isTopicRunning else { return }
        let config = TopicConfig(
            bootstrapPeers: [],
            listenAddr: "/ip4/0.0.0.0/tcp/0",
            mdns: true,
            relayServer: true,
            floodPublish: false,
            protocol: protocolPrefix,
            protocolVersion: protocolVersion
        )
        let network = try await spawnTopicNetworkFfi(
            label: "swifty-topic",
            torOnly: torOnly,
            config: config
        )
        topicNetwork = network
        peerId = network.localPeerId()
        isTopicRunning = true
        topicEventTask = Task { [weak self] in
            await self?.pollEvents(from: network)
        }
    }

    func startGossipClient(
        torOnly: Bool,
        protocolPrefix: String?,
        protocolVersion: String?
    ) async throws {
        guard !isGossipRunning else { return }
        let config = TopicConfig(
            bootstrapPeers: [],
            listenAddr: "/ip4/0.0.0.0/tcp/0",
            mdns: true,
            relayServer: true,
            floodPublish: false,
            protocol: protocolPrefix,
            protocolVersion: protocolVersion
        )
        let network = try await spawnGossipClientFfi(
            label: "swifty-gossip",
            torOnly: torOnly,
            showLocal: false,
            showRemote: true,
            config: config
        )
        gossipNetwork = network
        isGossipRunning = true
        gossipEventTask = Task { [weak self] in
            await self?.pollEvents(from: network)
        }
    }

    func publish(txHex: String) async throws {
        guard let network = topicNetwork else {
            throw TopicManagerError.notRunning
        }
        try await network.publish(txHex: txHex)
    }

    private func pollEvents(from network: TopicNetwork) async {
        while !Task.isCancelled {
            if let event = network.tryNextEvent() {
                let text = formatEvent(event)
                await MainActor.run { [weak self] in
                    self?.events.append(Event(text: text))
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }

    private func formatEvent(_ event: TopicEvent) -> String {
        switch event {
        case .message(let txid):
            return "topic message: txid=\(txid)"
        case .subscribed(let peerId):
            return "peer subscribed: \(peerId)"
        case .unsubscribed(let peerId):
            return "peer unsubscribed: \(peerId)"
        case .peerDiscovered(let peerId, let addr):
            return "peer discovered: \(peerId) at \(addr)"
        case .peerExpired(let peerId):
            return "peer expired: \(peerId)"
        case .listening(let address):
            return "listening on \(address)"
        case .identified(let peerId, let agentVersion):
            return "identified: \(peerId) (\(agentVersion))"
        }
    }
}

enum TopicManagerError: LocalizedError {
    case notRunning

    var errorDescription: String? {
        switch self {
        case .notRunning:
            return "Topic node is not running."
        }
    }
}
