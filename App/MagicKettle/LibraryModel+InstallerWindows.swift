import Foundation
import MagicKettleKit

extension LibraryModel {
    /// Brings each window the installer opens to the front while it runs. Magic Kettle is the active app when
    /// "Install" is clicked, and from macOS 14 a program it starts can't take the front by itself: Vortex's
    /// installer opened behind the library, under "The installer's window is open". Each process is brought
    /// forward once, when its first window shows, so a window the player moved away from isn't pulled back.
    func raiseInstallerWindows(of id: GameID, runtime: RuntimeManifest.Runtime) {
        guard let root = RuntimeInstaller(paths: paths).installed(runtime) else { return }
        let prefix = paths.bottle(forGame: id).path(percentEncoded: false)
        Task { [weak self] in
            var seen: Set<pid_t> = []
            while let self, self.install?.installID == id, case .installing? = self.install?.phase {
                let owners = await Task.detached { GameWindows.owners(under: root, prefix: prefix) }.value
                let new = owners.filter { !seen.contains($0) }
                seen.formUnion(owners)
                if let front = new.first { GameWindows.bringForward(front) }
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
