import Foundation

/// Entry point for iSCSI Daemon
@main
struct ISCSIDaemonMain {
    static func main() async {
        print("=== iSCSI Daemon ===")
        print("Connecting to iSCSIVirtualHBA dext...")

        let daemon = ISCSIDaemon()

        // TODO: Set up signal handlers for graceful shutdown
        // Note: signal() creates top-level code which conflicts with @main

        do {
            // Start the daemon
            try await daemon.start()

            // Keep running
            try await Task.sleep(for: .seconds(TimeInterval.infinity))
        } catch {
            print("Fatal error: \(error)")
            await daemon.stop()
            exit(1)
        }
    }
}
