import Foundation
import Network
import ISCSIProtocol

/// Manages a single TCP connection to an iSCSI target
public actor ISCSIConnection {

    public enum ConnectionState: Sendable, Equatable {
        case disconnected
        case connecting
        case connected
        case failed(String)

        public static func == (lhs: ConnectionState, rhs: ConnectionState) -> Bool {
            switch (lhs, rhs) {
            case (.disconnected, .disconnected),
                 (.connecting, .connecting),
                 (.connected, .connected):
                return true
            case (.failed(let a), .failed(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    public let host: String
    public let port: UInt16

    private var connection: NWConnection?
    private(set) public var currentState: ConnectionState = .disconnected
    private var receiveQueue: AsyncStream<Data>?
    private var receiveContinuation: AsyncStream<Data>.Continuation?

    public init(host: String, port: UInt16 = 3260) {
        self.host = host
        self.port = port
    }

    /// Connect to target
    public func connect() async throws {
        switch currentState {
        case .disconnected, .failed:
            break
        default:
            throw ISCSIError.alreadyConnected
        }

        currentState = .connecting

        // Create TCP parameters
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        tcpOptions.connectionTimeout = 30

        let parameters = NWParameters(tls: nil, tcp: tcpOptions)

        // Create connection
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: port)
        )

        let newConnection = NWConnection(to: endpoint, using: parameters)

        // State handler
        newConnection.stateUpdateHandler = { [weak self] newState in
            Task {
                await self?.handleStateChange(newState)
            }
        }

        // Start connection
        let queue = DispatchQueue(label: "com.opensource.iscsi.connection.\(host):\(port)")
        newConnection.start(queue: queue)

        self.connection = newConnection

        // Wait for connection (10 second timeout)
        for _ in 0..<100 {
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            if case .connected = currentState {
                setupReceive()
                return
            }
            if case .failed(let msg) = currentState {
                throw ISCSIError.connectionFailed(NSError(
                    domain: "ISCSIConnection",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: msg]
                ))
            }
        }

        throw ISCSIError.connectionTimeout
    }

    /// Disconnect
    public func disconnect() {
        connection?.cancel()
        connection = nil
        currentState = .disconnected
        receiveContinuation?.finish()
    }

    /// Send data
    public func send(_ data: Data) async throws {
        guard let connection = connection, case .connected = currentState else {
            throw ISCSIError.notConnected
        }

        return try await withCheckedThrowingContinuation { continuation in
            connection.send(
                content: data,
                completion: .contentProcessed { error in
                    if let error = error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume()
                    }
                }
            )
        }
    }

    /// Receive stream
    public func receiveStream() -> AsyncStream<Data> {
        if let existing = receiveQueue {
            return existing
        }

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        self.receiveQueue = stream
        self.receiveContinuation = continuation
        return stream
    }

    // MARK: - Private

    private func handleStateChange(_ newState: NWConnection.State) {
        switch newState {
        case .ready:
            currentState = .connected

        case .failed(let error):
            currentState = .failed(error.localizedDescription)

        case .cancelled:
            currentState = .disconnected

        default:
            break
        }
    }

    private func setupReceive() {
        guard let connection = connection else { return }

        connection.receiveMessage { [weak self] content, _, _, error in
            Task {
                if let content = content, !content.isEmpty {
                    await self?.receiveContinuation?.yield(content)
                }

                if error != nil {
                    await self?.receiveContinuation?.finish()
                    return
                }

                // Continue receiving
                await self?.setupReceive()
            }
        }
    }
}
