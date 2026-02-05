import Foundation
import Network
@testable import ISCSIProtocol

/// Mock iSCSI target for testing
actor MockISCSITarget {

    let port: UInt16
    private var listener: NWListener?
    private var connections: [NWConnection] = []

    init(port: UInt16) {
        self.port = port
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        let listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: port))

        listener.newConnectionHandler = { [weak self] newConnection in
            Task {
                await self?.handleNewConnection(newConnection)
            }
        }

        let queue = DispatchQueue(label: "com.test.iscsi.mock.\(port)")
        listener.start(queue: queue)

        self.listener = listener

        // Wait for listener to be ready
        try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
    }

    func stop() {
        listener?.cancel()
        connections.forEach { $0.cancel() }
        connections.removeAll()
        listener = nil
    }

    private func handleNewConnection(_ connection: NWConnection) {
        connections.append(connection)

        connection.stateUpdateHandler = { [weak self] state in
            if case .ready = state {
                Task {
                    await self?.startReceiving(on: connection)
                }
            }
        }

        let queue = DispatchQueue(label: "com.test.iscsi.mock.conn")
        connection.start(queue: queue)
    }

    private func startReceiving(on connection: NWConnection) {
        connection.receiveMessage { [weak self] content, _, _, error in
            guard let self = self, let data = content, !data.isEmpty else {
                return
            }

            Task {
                await self.processRequest(data, on: connection)
                await self.startReceiving(on: connection)
            }
        }
    }

    private func processRequest(_ data: Data, on connection: NWConnection) {
        do {
            let pdu = try ISCSIPDUParser.parsePDU(data)

            switch ISCSIPDUOpcode(rawValue: pdu.bhs.opcode) {
            case .loginRequest:
                let loginReq = try ISCSIPDUParser.parseLoginRequest(pdu)
                let response = buildLoginResponse(for: loginReq)
                let responseData = try ISCSIPDUParser.encodeLoginResponse(response)
                connection.send(content: responseData, completion: .contentProcessed { _ in })

            default:
                // Ignore other PDUs for now
                break
            }
        } catch {
            // Ignore parse errors in mock
        }
    }

    private func buildLoginResponse(for request: LoginRequestPDU) -> LoginResponsePDU {
        var response = LoginResponsePDU()
        response.transit = request.transit
        response.continue = false
        response.currentStageCode = request.currentStageCode
        response.nextStageCode = request.nextStageCode
        response.versionMax = 0
        response.versionActive = 0
        response.isid = request.isid
        response.tsih = 1  // Session ID
        response.initiatorTaskTag = request.initiatorTaskTag
        response.statSN = 0
        response.expCmdSN = request.cmdSN + 1
        response.maxCmdSN = request.cmdSN + 64
        response.statusClass = 0  // Success
        response.statusDetail = 0

        response.keyValuePairs = [
            "TargetName": "iqn.2026-01.test:target",
            "AuthMethod": "None"
        ]

        return response
    }
}
