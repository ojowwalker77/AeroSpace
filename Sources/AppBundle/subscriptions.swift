import Common
import Foundation
import Network

actor ConnectionWriter {
    private let connection: NWConnection

    init(_ connection: NWConnection) {
        self.connection = connection
    }

    func write(_ event: ServerEvent) async -> Bool {
        // Encode and combine header + payload BEFORE any await to prevent actor reentrancy issues
        let payload: Data
        do {
            payload = try JSONEncoder().encode(event)
        } catch {
            return true
        }
        var data = withUnsafeBytes(of: UInt32(payload.count)) { Data($0) }
        data.append(payload)

        // Single atomic send - no intermediate await points
        let error: NWError? = await withCheckedContinuation { cont in
            connection.send(content: data, completion: .contentProcessed { error in
                cont.resume(returning: error)
            })
        }
        return error != nil
    }
}

struct Subscriber: Sendable {
    let writer: ConnectionWriter
    let events: Set<ServerEventType>
}

@MainActor private var subscribers: [ObjectIdentifier: Subscriber] = [:]

@MainActor func addSubscriber(_ connection: NWConnection, events: [ServerEventType]) -> ConnectionWriter {
    let id = ObjectIdentifier(connection)
    let writer = ConnectionWriter(connection)
    subscribers[id] = Subscriber(writer: writer, events: Set(events))
    return writer
}

@MainActor func removeSubscriber(_ connection: NWConnection) {
    let id = ObjectIdentifier(connection)
    subscribers.removeValue(forKey: id)
}

@MainActor func broadcastEvent(_ event: ServerEvent) {
    for (id, subscriber) in subscribers {
        guard subscriber.events.contains(event.event) else { continue }
        Task {
            if await subscriber.writer.write(event) {
                await MainActor.run {
                    _ = subscribers.removeValue(forKey: id)
                }
            }
        }
    }
}
