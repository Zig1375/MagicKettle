import MagicKettleKit
import SwiftUI

/// "Delete <game>?" from the design (Delete.dc.html): forget it in Magic Kettle, or move its folder to the Trash.
/// Saves stay either way; deleting them too needs per-game save tracking, which comes later.
struct DeleteGameSheet: View {
    enum Choice { case appOnly, fromDisk }

    let game: GameRecord
    let folderSize: Int64?
    let library: LibraryModel
    let done: (_ removed: Bool) -> Void
    @State private var choice: Choice = .appOnly
    /// Measured here when the caller didn't know it yet (the library's context menu).
    @State private var measured: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Delete \(game.name)?")
                .font(.system(size: 17, weight: .bold))
            if !canMoveToTrash {
                Text("Magic Kettle will remove this entry and its Windows setup. Saves will be kept.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            } else {
                Picker("How to delete", selection: $choice) {
                    option(title: "Only from Magic Kettle",
                           text: """
                               The game stays in \(folder). Magic Kettle forgets it and deletes its Windows setup. \
                               Double-click the exe to bring it back.
                               """)
                        .tag(Choice.appOnly)
                    Group {
                        if let program = onlyProgram {
                            // The game sits in Downloads or another shared folder: that folder stays.
                            option(title: "From disk",
                                   text: """
                                       Only \(program)\(sizeText) goes to the Trash; \(folder) stays. Until the Trash \
                                       is emptied, it can be restored.
                                       """)
                        } else {
                            option(title: "From disk",
                                   text: """
                                       The game folder\(sizeText) goes to the Trash. Until the Trash is emptied, \
                                       the game can be restored.
                                       """)
                        }
                    }
                    .tag(Choice.fromDisk)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            if canMoveToTrash {
                Text("Saves are kept either way.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondaryText)
            }
            HStack {
                Spacer()
                Button("Cancel") { done(false) }
                    .buttonStyle(.brand)
                    .keyboardShortcut(.cancelAction)
                Button(choice == .appOnly ? "Remove from Magic Kettle" : "Move to Trash") {
                    if choice == .appOnly || !canMoveToTrash {
                        library.removeFromApp(game)
                    } else {
                        library.moveToTrash(game)
                    }
                    done(true)
                }
                .buttonStyle(BrandButtonStyle(kind: .primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
        .focusEffectDisabled()
        .task { if folderSize == nil { measured = await library.folderSize(of: game) } }
    }

    /// Check the actual removal target, not its byte count: an empty file can still exist.
    private var canMoveToTrash: Bool {
        let target = GameRemover.trashTarget(for: game, identifier: GameIdentifier(paths: library.paths))
        return FileManager.default.fileExists(atPath: target.path)
    }

    private var folder: String { (game.folder as NSString).abbreviatingWithTildeInPath }

    /// The program's file name when only it goes to the Trash (`GameRemover.trashTarget`).
    private var onlyProgram: String? {
        let target = GameRemover.trashTarget(for: game, identifier: GameIdentifier(paths: library.paths))
        return target.path == URL(filePath: game.executable).path ? target.lastPathComponent : nil
    }

    private var sizeText: String {
        (folderSize ?? measured).map { " (\($0.formatted(.byteCount(style: .file))))" } ?? ""
    }

    private func option(title: LocalizedStringKey, text: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).fontWeight(.semibold)
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(Color.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
