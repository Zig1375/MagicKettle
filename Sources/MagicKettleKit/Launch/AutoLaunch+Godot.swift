extension AutoLaunch {
    /// Godot can use OpenGL when its Direct3D 12 renderer fails, as in Nightmare Erosion.
    func retryGodot(_ ran: Ran, game: inout GameRecord, tried: inout Bool,
                    at position: (number: Int, total: Int), context: Context) async throws -> Ran? {
        guard ran.attempt.failure == .godotDirect3D12, !tried, context.control.retrying,
              game.godotOpenGL != true, game.store == nil, !game.hasRendererArguments else { return nil }
        let backend = ran.attempt.backend
        tried = true
        game.godotOpenGL = true
        context.events(.retrying(ran.attempt, next: backend, attempt: position.number, total: position.total))
        let retry = try await attempt(backend, of: game, number: position.number, of: position.total, context: context)
        if !retry.worked { game.godotOpenGL = nil }
        return retry
    }
}
