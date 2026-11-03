import Foundation
@testable import MagicKettleKit
import Testing

@Suite struct ProcessRunnerTests {
    /// A Wine helper that is the first in its bottle starts `wineserver`, which keeps the helper's output open for as
    /// long as the bottle runs. Waiting for the end of that output hung Magic Kettle's store checks for good.
    @Test func returnsWhileAChildKeepsTheOutputOpen() async throws {
        let started = Date()
        let result = try await ProcessRunner.run("/bin/sh", ["-c", "echo hello; sleep 30 & echo $!"])
        #expect(Date().timeIntervalSince(started) < 5)
        #expect(result.status == 0)
        #expect(result.output.hasPrefix("hello\n"))
        if let pid = Int32(result.output.split(separator: "\n").last ?? "") { kill(pid, SIGKILL) }
    }

    @Test func keepsAllTheOutput() async throws {
        let result = try await ProcessRunner.run("/bin/sh", ["-c", "head -c 300000 /dev/zero | tr '\\0' x"])
        #expect(result.output.count == 300_000)
    }
}
