import Foundation

public enum IOServiceState {
    case stopped
    case running
    case error
}

public class MockIOService {
    public let name: String
    public private(set) var state: IOServiceState

    public init(name: String) {
        self.name = name
        self.state = .running
    }

    public func stop() {
        state = .stopped
    }

    public func start() {
        state = .running
    }

    public func setError() {
        state = .error
    }
}
