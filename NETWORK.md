# bitcoin-pigeon network coverage log

This document describes how bitcoin-pigeon instances share state over the
libp2p/gossipsub topic network, and records the observed propagation behavior.

## Goal: shared consensus mempool

Every bitcoin-pigeon node that joins the same `/gnostr/<version>` topic mesh is
a peer in a single shared mempool.  When one instance sends or receives a
Bitcoin transaction, that transaction is gossiped to every other subscriber and
added to the in-memory **shared mempool**.  The Swift *Mempool* view then shows
the union of:

1. transactions received from other bitcoin-pigeon peers (consensus), and
2. transactions fetched from public mempool APIs.

The shared state is keyed by `txid`, so duplicate transactions are collapsed
into a single entry regardless of how many times or from how many peers they
arrive.

## How propagation works

### 1. Topic subscription

Each node builds a libp2p swarm with `gossipsub`, `mdns`, `identify`, `relay`,
`autonat`, and `dcutr` behaviors (`tx-pigeon/src/topic.rs`).  On startup it
subscribes to the `bitcoin-pigeon` topic and listens on `/ip4/0.0.0.0/tcp/0`.

### 2. Publishing a transaction

A transaction hex can be injected from:

- the Swift *Publish to topic* button (`TopicManager.publish`),
- the Rust `TopicRelayHandle::publish` API, or
- the CLI `run_topic_network(tx_hex=Some(...))` path.

`publish_topic_tx` decodes the hex, computes the `txid`, and calls
`gossipsub::publish`.  The message ID is derived from the `txid` so identical
transactions deduplicate naturally in gossipsub.

### 3. Receiving a transaction

When a node receives a `Gossipsub::Message`:

1. The raw bytes are hex-encoded.
2. The transaction is decoded and its `txid` is computed.
3. The `(txid, hex)` pair is inserted into the process-wide `SHARED_MEMPOOL`
   (`tx-pigeon/src/topic.rs`).
4. A `TopicEvent::Message { txid, hex }` is emitted on the local event channel.
5. In topic-node mode the transaction is also rebroadcast to the configured
   Libre Bitcoin relay peers (`blast_transaction_hex`).

Because every subscriber receives the same `Message`, every peer ends up with
identical entries in `SHARED_MEMPOOL` — this is the **consensus** view.

### 4. flood_publish = true (default)

`TopicConfig::default()` now sets `flood_publish: true`.  This is important for
small or short-lived meshes (for example two Mac Catalyst instances on the same
LAN): it forces the publisher to forward the message to *all* known subscribers
immediately instead of waiting for the gossipsub mesh heartbeat to establish
forwarding paths.  The result is reliable one-to-many propagation even with only
a handful of peers.

## FFI and UI exposure

- `rustylib/src/lib.rs` exposes `get_shared_mempool_txs() -> [MempoolTx]` to
  Swift via UniFFI.
- `MempoolManager.load()` merges `getSharedMempoolTxs()` with
  `fetchRecentMempoolTxs()`, preferring bitcoin-pigeon consensus entries.
- `MempoolManager.addPeerTx(txid:hex:)` pushes live peer events to the top of
  the list as they arrive.
- `ContentView` logs each peer transaction:
  `Consensus mempool received peer tx: <txid>`.

## Observed propagation log

### `topic_mesh` integration test

Two Rust topic nodes on localhost with `mdns=false`, connected by explicit
bootstrap address, with `flood_publish=true`:

```
[test] node-a listening on /ip4/127.0.0.1/tcp/53343
[test] node-b listening on /ip4/127.0.0.1/tcp/53344
[test] expected peer identified: 12D3KooWL8pUqatDW8MvHb9N4CMXoHuJzMHJm31CxB4R4mQQ4eYc
[test] expected peer subscribed: 12D3KooWQpoPHhxUoip59vRdXM9qPwDKNJZeHqACPFUJ1DaeZaQg
[test] publishing tx from node-a
[node-a] deserialized tx f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16 ...
[test] node-b received tx f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16 — ok
[node-b] rebroadcasting topic tx f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16 to libre relay nodes
[node-a] rebroadcasting topic tx f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16 to libre relay nodes
```

Result: the transaction published by `node-a` was received by `node-b`, and both
nodes attempted to relay it to the wider Bitcoin P2P network.

### `gossip_client` integration test

A passive gossip observer with `show_remote=true` receives the same transaction
from a publisher:

```
[test] publisher listening on /ip4/127.0.0.1/tcp/53348
[test] expected peer identified: 12D3KooWBNFiMbJMZ2ic73QKNPSyBR4iF6ZJSAxryC5yZ5Mqp8aw
[test] observer subscribed: 12D3KooWSXHsS4S9ZWcLdFuacNLrjsu45B3XvBP4BxhtZXe6uzfi
[test] publishing tx from publisher
[publisher] deserialized tx f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16 ...
[test] observer received tx f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16 — ok
[observer] observed topic tx f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16 (no rebroadcast)
```

Result: the observer correctly received the consensus transaction without
rebroadcasting it to Bitcoin P2P (observer-only mode).

## Transaction detail logging

Every transaction that flows through the topic path is fully deserialized and
logged at `info` level plus printed to stdout, including:

- version, input/output count, lock time,
- each input’s previous outpoint, sequence, script-sig length, and witness size,
- each output’s value and `script_pubkey`.

This makes it possible to inspect the actual transaction bytes moving between
peers and from peers to Libre relay nodes.

## Network time consensus

bitcoin-pigeon also shares a **Byzantine Fault Tolerant logical clock** across
peers (`tx-pigeon/src/time.rs`).  The design is adapted from gnostr-p2p's BFT
clock:

- Each node runs a small libp2p swarm on `/bitcoin-pigeon/time/1.0` that
  exchanges request/response time-sync messages with discovered peers.
- Every 10 seconds the node sends a `SyncRequest { t1 }` to each connected peer.
- The peer replies with `SyncResponse { t1, t2 }` containing its local logical
  time when the request was received.
- The requester uses the round-trip times to build `Estimation { d, a }`
  samples and applies `apply_bft_sync(estimates)` once it has at least `2*f + 1`
  samples (default `f = 1`, so 3 peers).
- The algorithm sorts the estimates, discards the `f` highest and `f` lowest
  outliers, and takes the midpoint of the remaining window as the consensus
  offset.  It then slews the local clock toward the peer median.
- If no quorum is available the clock stays in `Init`; if the estimate window is
  empty after removing outliers the clock becomes `Unreliable` and broadcasts a
  `HealthAlert` on the `bitcoin-pigeon-time-alerts` gossip topic.
- The clock checkpoint is persisted to JSON so the offset survives restarts.

The Swift *Clock* pane exposes `startTimeSyncDaemon`, `getClockMetrics`, and
`getLogicalUtc`, displaying status, slew rate, offset, last-sync age, and the
current logical UTC.

## Test commands

```bash
cd tx-pigeon
cargo test --lib
cargo test --test topic_mesh -- --nocapture
cargo test --test gossip_client -- --nocapture
```

`relay_nocapture` is marked `#[ignore]` because it runs for 60 seconds against
live network endpoints; run it manually with:

```bash
cargo test --test relay_nocapture -- --ignored --nocapture
```

## Summary

bitcoin-pigeon does not rely on a central server for mempool or time consensus.
Each instance subscribes to the same gossipsub topic, publishes transactions it
wants to share, and inserts every received transaction into a local shared
mempool.  At the same time, the BFT clock daemon keeps the node's logical time
synchronized with its peers.  With `flood_publish` enabled by default, even two
instances on a LAN share a single, deduplicated, live mempool view and a common
time base.
