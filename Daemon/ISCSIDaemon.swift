import Foundation
import ISCSIProtocol  // Import the existing Protocol layer

/// Main daemon actor that processes SCSI commands and sends iSCSI PDUs
actor ISCSIDaemon {
    private let dextConnector: DextConnector
    private var sessionManager: ISCSISessionManager?
    private var isRunning = false

    // Task tag mapping: kernel taskTag -> iSCSI ITT
    private var taskMapping: [UInt64: UInt32] = [:]
    private var nextITT: UInt32 = 1

    init() {
        self.dextConnector = DextConnector()
    }

    /// Start the daemon
    func start() async throws {
        print("Starting iSCSI Daemon...")

        // Connect to dext
        try await dextConnector.connect()
        try await dextConnector.mapSharedMemory()

        // Check HBA status
        let status = try await dextConnector.getHBAStatus()
        print("✓ HBA Status: \(status) (1 = online)")

        // Create session with dext
        let sessionID = try await dextConnector.createSession()
        print("✓ Created dext session: \(sessionID)")

        // Initialize session manager (will be used for iSCSI connections)
        sessionManager = ISCSISessionManager(initiatorName: "iqn.2025-01.com.example:initiator")

        isRunning = true
        print("✓ iSCSI Daemon started successfully")

        // Start command processing loop
        await commandProcessingLoop()
    }

    /// Main command processing loop
    private func commandProcessingLoop() async {
        print("Starting command processing loop...")

        while isRunning {
            do {
                // Check for pending commands
                if let command = await dextConnector.readNextCommand() {
                    await processCommand(command)
                }

                // Small sleep to avoid busy-waiting
                // In production, this would use notification mechanism
                try await Task.sleep(nanoseconds: 1_000_000)  // 1ms
            } catch {
                print("Error in command processing loop: \(error)")
                // Continue running even if individual command fails
            }
        }

        print("Command processing loop stopped")
    }

    /// Process a single SCSI command
    private func processCommand(_ command: SCSICommandDescriptor) async {
        print("Processing command: taskTag=\(command.taskTag), targetID=\(command.targetID), lun=\(command.lun), CDB[0]=0x\(String(format: "%02X", command.cdbArray[0]))")

        // For Phase 5, we'll implement a stub that completes immediately
        // In Phase 6, this will send actual iSCSI PDUs via ISCSIConnection

        // Generate ITT for this task
        let itt = allocateITT(for: command.taskTag)

        // TODO: Phase 6 - Send iSCSI SCSI Command PDU
        // For now, simulate immediate completion with success

        // Create completion
        let completion = SCSICompletionDescriptor(
            taskTag: command.taskTag,
            itt: itt,
            scsiStatus: SCSIStatus.good.rawValue,
            transferCount: 0  // No data transferred in stub
        )

        // Send completion back to dext
        do {
            try await dextConnector.writeCompletion(completion)
            print("✓ Completed task \(command.taskTag) with status GOOD")
        } catch {
            print("❌ Failed to write completion for task \(command.taskTag): \(error)")
        }

        // Free ITT
        deallocateITT(command.taskTag)
    }

    /// Allocate iSCSI Initiator Task Tag for kernel task
    private func allocateITT(for taskTag: UInt64) -> UInt32 {
        let itt = nextITT
        nextITT += 1
        if nextITT == 0xFFFFFFFF {
            nextITT = 1  // Reserve 0xFFFFFFFF for special purposes
        }
        taskMapping[taskTag] = itt
        return itt
    }

    /// Deallocate ITT when task completes
    private func deallocateITT(_ taskTag: UInt64) {
        taskMapping.removeValue(forKey: taskTag)
    }

    /// Stop the daemon
    func stop() async {
        print("Stopping iSCSI Daemon...")
        isRunning = false

        // Disconnect from dext
        await dextConnector.disconnect()

        print("✓ iSCSI Daemon stopped")
    }

    /// Connect to an iSCSI target (Phase 6)
    func connectToTarget(host: String, port: Int, targetIQN: String) async throws {
        guard sessionManager != nil else {
            throw DaemonError.notInitialized
        }

        print("Connecting to iSCSI target: \(targetIQN) at \(host):\(port)")

        // TODO: Phase 6 - Use ISCSIConnection to establish session
        // This will involve:
        // 1. TCP connection
        // 2. Login phase (potentially with CHAP authentication)
        // 3. Full feature phase negotiation
        // 4. LUN discovery

        print("✓ Connected to target \(targetIQN)")
    }

    /// Disconnect from iSCSI target (Phase 6)
    func disconnectFromTarget(targetIQN: String) async throws {
        print("Disconnecting from iSCSI target: \(targetIQN)")

        // TODO: Phase 6 - Use ISCSIConnection to logout
        // This will send Logout Request PDU and close TCP connection

        print("✓ Disconnected from target \(targetIQN)")
    }

    /// Perform SendTargets discovery (Phase 6)
    func discoverTargets(host: String, port: Int) async throws -> [ISCSITarget] {
        print("Discovering iSCSI targets at \(host):\(port)")

        // TODO: Phase 6 - Use TextRequestPDU with SendTargets=All
        // Parse TextResponsePDU to extract targets

        // Stub return empty list
        return []
    }
}

/// Errors specific to daemon operation
enum DaemonError: Error {
    case notInitialized
    case targetNotFound
    case sessionEstablishmentFailed
}

/// Represents discovered iSCSI target
struct ISCSITarget {
    let iqn: String
    let portals: [ISCSIPortal]
}

/// Represents iSCSI portal (IP:port + group tag)
struct ISCSIPortal {
    let address: String
    let port: Int
    let groupTag: Int
}
