// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI
import UIKit

/// Prépare des rotations réversibles, puis invalide l'OCR seulement après confirmation.
struct PageOrientationView: View {
    let document: LibraryDocument
    let apply: ([Int: Int]) async throws -> Void
    @EnvironmentObject private var model: AppModel
    // Observés pour que l'alerte apparaisse et disparaisse avec l'analyse, sans attendre « Appliquer ».
    @ObservedObject private var tasks = AITaskCenter.shared
    @ObservedObject private var analysis = DocumentAnalysisService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int>
    @State private var rotations: [Int: Int]
    private let original: [Int: Int]
    @State private var from = ""
    @State private var to = ""
    @State private var confirming = false
    @State private var working = false
    @State private var error: String?

    init(document: LibraryDocument, selectedPage: Int, rotations: [Int: Int],
         apply: @escaping ([Int: Int]) async throws -> Void) {
        self.document = document
        self.apply = apply
        let normalized = Dictionary(uniqueKeysWithValues: (0..<document.pageCount).map {
            ($0, PageTransform.normalizedRotation(rotations[$0] ?? 0))
        })
        original = normalized
        _rotations = State(initialValue: normalized)
        _selected = State(initialValue: [max(0, min(document.pageCount - 1, selectedPage))])
    }

    private var changes: [Int: Int] {
        rotations.filter { original[$0.key, default: 0] != $0.value }
    }

    var body: some View {
        NavigationStack {
            List {
                if let blocked = model.pageRotationBlockReason(for: document), !working {
                    Label(blocked, systemImage: "hourglass").foregroundStyle(.orange)
                }
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
                Section {
                    HStack {
                        Text("De la page")
                        TextField("1", text: $from).keyboardType(.numberPad).frame(width: 60).textFieldStyle(.roundedBorder)
                        Text("à")
                        TextField("1", text: $to).keyboardType(.numberPad).frame(width: 60).textFieldStyle(.roundedBorder)
                        Spacer()
                        Button("Sélectionner") { selectRange() }.disabled(from.isEmpty)
                    }
                    HStack {
                        Button("Tout sélectionner") { selected = Set(0..<document.pageCount) }
                        Spacer()
                        Button("Aucune") { selected.removeAll() }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 12) {
                        ForEach(0..<document.pageCount, id: \.self) { page in
                            OrientationPageChoice(document: document, page: page,
                                                  rotation: rotations[page, default: 0],
                                                  selected: selected.contains(page)) {
                                if selected.contains(page) { selected.remove(page) } else { selected.insert(page) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Pages à orienter")
                } footer: {
                    Text("L'aperçu ne modifie pas le PDF original. Sélectionne une ou plusieurs pages, puis tourne-les.")
                }

                Section("Rotation de la sélection") {
                    HStack(spacing: 12) {
                        Button { rotate(-90) } label: { Label("À gauche", systemImage: "rotate.left") }
                            .buttonStyle(.bordered).disabled(selected.isEmpty || working)
                        Button { rotate(90) } label: { Label("À droite", systemImage: "rotate.right") }
                            .buttonStyle(.bordered).disabled(selected.isEmpty || working)
                        Button("Réinitialiser") {
                            for page in selected { rotations[page] = 0 }
                        }
                        .buttonStyle(.bordered).disabled(selected.isEmpty || working)
                    }
                }
            }
            .navigationTitle("Orientation des pages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() }.disabled(working) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Appliquer (\(changes.count))") { confirming = true }
                        .disabled(changes.isEmpty || working || model.pageRotationBlockReason(for: document) != nil)
                }
            }
            .overlay {
                if working {
                    ProgressView("Application et préparation de l'OCR…").padding(24)
                        .background(Atelier.material(.regularMaterial),
                                    in: RoundedRectangle(cornerRadius: Atelier.corner(14)))
                }
            }
            .confirmationDialog("Appliquer l'orientation ?", isPresented: $confirming) {
                Button("Appliquer") { commit() }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("\(changes.count) page(s) seront réorientées. Leur OCR sera refait et leurs lectures IA seront effacées puis relues si la lecture automatique est active. Leurs traductions seront effacées : à redemander. Une page corrigée à la main garde son OCR, tourné avec elle et sans relecture. Le PDF original, les notes, cartes et annotations sont conservés.")
            }
            .interactiveDismissDisabled(working)
        }
    }

    private func rotate(_ degrees: Int) {
        for page in selected {
            rotations[page] = PageTransform.normalizedRotation(rotations[page, default: 0] + degrees)
        }
    }

    private func selectRange() {
        guard let first = Int(from) else { return }
        let last = Int(to) ?? first
        let low = max(1, min(first, last)), high = min(document.pageCount, max(first, last))
        guard low <= high else { return }
        selected.formUnion((low...high).map { $0 - 1 })
    }

    private func commit() {
        let pending = changes
        working = true
        error = nil
        Task {
            do {
                try await apply(pending)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}

private struct OrientationPageChoice: View {
    let document: LibraryDocument
    let page: Int
    let rotation: Int
    let selected: Bool
    let toggle: () -> Void
    @EnvironmentObject private var model: AppModel
    @State private var image: UIImage?

    var body: some View {
        Button(action: toggle) {
            VStack(spacing: 5) {
                ZStack(alignment: .topTrailing) {
                    Group {
                        if let image {
                            Image(uiImage: image).resizable().scaledToFit()
                                .rotationEffect(.degrees(Double(rotation)))
                                .padding(rotation == 90 || rotation == 270 ? 14 : 0)
                        } else {
                            Color.secondary.opacity(0.15)
                        }
                    }
                    .frame(width: 92, height: 118)
                    .clipped()
                    .overlay(RoundedRectangle(cornerRadius: Atelier.corner(5))
                        .stroke(selected ? Atelier.Tint.annotate : Color.secondary.opacity(0.3),
                                lineWidth: selected ? 3 : 1))
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selected ? Atelier.Tint.annotate : Color.secondary)
                        .background(Circle().fill(.background)).padding(4)
                }
                Text("p. \(document.pageLabel(page)) · \(rotation)°")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            model.thumbnails.thumbnail(documentId: document.id, fileURL: model.storage.url(for: document.id),
                                       page: page, width: 184) { image = $0 }
        }
    }
}
