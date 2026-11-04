// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI

/// Historique des ajouts de pages, un par document, dans les préférences de l'app (donc dans la sauvegarde) ; effacé
/// avec le document (RET-033, #48).
enum PageAdditionHistory {
    private static func key(_ documentId: String) -> String { "pages.additions.\(documentId)" }

    static func load(_ documentId: String) -> PageAdditionLog {
        PageAdditionLog.decode(UserDefaults.standard.data(forKey: key(documentId)))
    }

    static func record(_ addition: PageAddition, documentId: String) {
        var log = load(documentId)
        log.record(addition)
        UserDefaults.standard.set(log.encoded(), forKey: key(documentId))
    }

    static func forget(_ documentId: String) {
        UserDefaults.standard.removeObject(forKey: key(documentId))
    }
}

/// Section « Ajouts de pages » de « Ce document ».
struct PageAdditionHistorySection: View {
    let documentId: String
    @State private var log = PageAdditionLog()

    var body: some View {
        Section {
            if log.entries.isEmpty {
                Text("Aucun ajout enregistré.").foregroundStyle(.secondary)
            }
            ForEach(Array(log.entries.enumerated().reversed()), id: \.offset) { _, entry in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(entry.summary)
                        Spacer()
                        Text(entry.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text(String(localized: "\(entry.totalAfter) pages ensuite") + (entry.sources.isEmpty ? "" : " · " + entry.sources.joined(separator: ", ")))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
        } header: {
            Text("Ajouts de pages")
        } footer: {
            Text("« Ajouter des pages… » (appui long sur le livre dans la bibliothèque). Les ajouts faits avant cette version ne sont pas listés.")
        }
        .onAppear { log = PageAdditionHistory.load(documentId) }
    }
}
