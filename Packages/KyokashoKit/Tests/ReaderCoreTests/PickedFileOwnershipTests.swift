// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import XCTest

final class PickedFileOwnershipTests: XCTestCase {
    private let tmp = URL(fileURLWithPath: "/private/tmp/app-tmp", isDirectory: true)

    func testOnlyAUUIDFolderDirectlyInTheTemporaryDirectoryIsOwned() {
        let id = UUID().uuidString
        XCTAssertTrue(PickedFileOwnership.isPrivateCopy(tmp.appendingPathComponent("Picked-\(id)/a.pdf"), privateRoot: tmp))
        // Dossier de l'utilisateur au nom voisin : ses originaux et leurs voisins ne doivent jamais être effacés.
        for path in ["/Users/x/Documents/Picked-Manuels/a.pdf", "/Users/x/Documents/Picked-\(id)/a.pdf",
                     tmp.path + "/Picked-Manuels/a.pdf", tmp.path + "/sous/Picked-\(id)/a.pdf",
                     tmp.path + "/Picked-\(id)/sous/a.pdf", tmp.path + "/Picked-\(id)/../Picked-Manuels/a.pdf"] {
            XCTAssertFalse(PickedFileOwnership.isPrivateCopy(URL(fileURLWithPath: path), privateRoot: tmp), path)
        }
    }
}
