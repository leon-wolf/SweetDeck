import Foundation

public final class SweetDeckSpinner {
    private let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]
    private let interval: TimeInterval = 0.1
    private let message: String
    private var timer: DispatchSourceTimer?
    private var index = 0

    public init(message: String) {
        self.message = message
    }

    public func start() {
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now(), repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let frame = self.frames[self.index % self.frames.count]
            self.index += 1
            FileHandle.standardError.write("\r\(frame) \(self.message)".data(using: .utf8)!)
        }
        self.timer = timer
        timer.resume()
    }

    public func stop(finalMessage: String?) {
        timer?.cancel()
        timer = nil
        let message = finalMessage ?? self.message
        FileHandle.standardError.write("\r✅ \(message)\n".data(using: .utf8)!)
    }
}
