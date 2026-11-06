// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation

/// Dit si un fichier est une copie privée de l'app, donc effaçable. Le nom du dossier ne suffit pas : un dossier de
/// l'utilisateur appelé `Picked-Manuels` contient des originaux (revue Codex du 04/11/2026). Seul un dossier
/// `Picked-<UUID>` placé directement dans le répertoire temporaire de l'app appartient à l'app.
public enum PickedFileOwnership {
    public static func isPrivateCopy(_ url: URL, privateRoot: URL) -> Bool {
        let folder = url.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent()
        let root = privateRoot.standardizedFileURL.resolvingSymlinksInPath()
        guard folder.deletingLastPathComponent().path == root.path else { return false }
        let name = folder.lastPathComponent
        return name.hasPrefix("Picked-") && UUID(uuidString: String(name.dropFirst("Picked-".count))) != nil
    }
}
