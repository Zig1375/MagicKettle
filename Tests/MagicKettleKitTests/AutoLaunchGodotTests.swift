@testable import MagicKettleKit
import Testing

extension AutoLaunchTests {
    @Test(arguments: [
        "ERROR: D3D12CreateDevice failed with error 0x80004002.",
        "ERROR: Create(Compute)PipelineState failed with error 0x80004005.",
    ])
    mutating func godotRetriesWithOpenGLOnRememberedBackend(_ error: String) async throws {
        game.backend = .dxvk
        let starter = try FakeStarter([.dxvk: .init(windowAt: 0, log: "Godot Engine v4.5.stable\r\n\(error)\r\n")],
                                      logs: logs(), openGL: .works)
        let result = try await play(starter)
        #expect(starter.started.first?.1.stopped == true)
        #expect(result.attempts.map(\.failure) == [.godotDirect3D12, nil])
        #expect(starter.startedGames.map(\.launchArguments) == [
            [], ["--rendering-method", "gl_compatibility", "--rendering-driver", "opengl3"],
        ])
        #expect(result.working == .dxvk)
        #expect(try GameLibrary.load(from: paths.library)[game.id]?.godotOpenGL == true)
    }

    @Test func failedOpenGLIsNotRemembered() async throws {
        let broken = Script(windowAt: 0, log: "Godot Engine v4.5.stable\nERROR: D3D12CreateDevice failed\n")
        let starter = try FakeStarter([.dxvk: broken, .dxmt: .works], logs: logs(), openGL: .crashes())
        let result = try await play(starter)
        #expect(starter.startedGames.map { $0.godotOpenGL == true } == [false, true, false])
        #expect(result.working == .dxmt)
        #expect(try GameLibrary.load(from: paths.library)[game.id]?.godotOpenGL == nil)
    }
}
