// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReaderCore
import SwiftUI
import UIKit

/// Prépare des rotations réversibles. Par défaut rien n'est perdu ; relire les pages est un choix explicite.
struct PageOrientationView: View {
    let document: LibraryDocument
    let apply: ([Int: Int], Bool) async throws -> Void
    @EnvironmentObject private var model: AppModel
    // Observés pour que l'alerte apparaisse et disparaisse avec l'analyse, sans attendre « Appliquer ».
    @ObservedObject private var tasks = AITaskCenter.shared
    @ObservedObject private var analysis = DocumentAnalysisService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<Int>
    @State private var rotations: [Int: Int]
    private let original: [Int: Int]
    private let currentPage: Int
    @State private var from = ""
    @State private var to = ""
    @State private var confirming = false
    @State private var working = false
    @State private var error: String?

    init(document: LibraryDocument, selectedPage: Int, rotations: [Int: Int],
         apply: @escaping ([Int: Int], Bool) async throws -> Void) {
        self.document = document
        currentPage = max(0, min(document.pageCount - 1, selectedPage))
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
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("L'aperçu ne modifie pas le PDF original.").font(.footnote).foregroundStyle(.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 12) {
                            ForEach(0..<document.pageCount, id: \.self) { page in
                                OrientationPageChoice(document: document, page: page,
                                                      rotation: rotations[page, default: 0],
                                                      selected: selected.contains(page)) {
                                    if selected.contains(page) { selected.remove(page) } else { selected.insert(page) }
                                }
                                .id(page)
                            }
                        }
                    }
                    .padding(16)
                }
                .onAppear {
                    // Après la première mise en page : la grille paresseuse connaît alors la position demandée.
                    DispatchQueue.main.async { proxy.scrollTo(currentPage, anchor: .center) }
                }
            }
            // Fixes au-dessus de la grille : toujours accessibles, même sur un long document.
            .safeAreaInset(edge: .top, spacing: 0) { controls }
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
                    ProgressView("Application de l'orientation…").padding(24)
                        .background(Atelier.material(.regularMaterial),
                                    in: RoundedRectangle(cornerRadius: Atelier.corner(14)))
                }
            }
            .confirmationDialog("Appliquer l'orientation ?", isPresented: $confirming) {
                Button("Tourner et tout garder") { commit(rereading: false) }
                Button("Tourner et relire ces pages", role: .destructive) { commit(rereading: true) }
                Button("Annuler", role: .cancel) {}
            } message: {
                Text("\(changes.count) page(s). « Tout garder » conserve l'OCR, les lectures IA et les traductions. « Relire », seulement pour une page lue de travers, efface ces lectures et traductions et refait l'OCR ; les corrections manuelles restent.")
            }
            .interactiveDismissDisabled(working)
        }
    }

    private var controls: some View {
        VStack(spacing: 12) {
            if let blocked = model.pageRotationBlockReason(for: document), !working {
                Label(blocked, systemImage: "hourglass").foregroundStyle(.orange).font(.footnote)
                    .multilineTextAlignment(.center)
            }
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).font(.footnote)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 10) {
                Button { rotate(-90) } label: { Label("À gauche", systemImage: "rotate.left") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.annotate))
                Button { rotate(90) } label: { Label("À droite", systemImage: "rotate.right") }
                    .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.annotate))
                Button { for page in selected { rotations[page] = 0 } } label: {
                    Label("Réinitialiser", systemImage: "arrow.uturn.backward")
                }
                .buttonStyle(OrientationChipStyle())
            }
            .disabled(selected.isEmpty || working)
            .opacity(selected.isEmpty ? 0.45 : 1)
            HStack(spacing: 8) {
                Button("Tout") { selected = Set(0..<document.pageCount) }.buttonStyle(OrientationChipStyle())
                Button("Aucune") { selected.removeAll() }.buttonStyle(OrientationChipStyle())
                Divider().frame(height: 22).padding(.horizontal, 6)
                Text("De").foregroundStyle(Atelier.textSecondary)
                TextField("1", text: $from).keyboardType(.numberPad).multilineTextAlignment(.center)
                    .frame(width: 52).textFieldStyle(.roundedBorder)
                Text("à").foregroundStyle(Atelier.textSecondary)
                TextField("1", text: $to).keyboardType(.numberPad).multilineTextAlignment(.center)
                    .frame(width: 52).textFieldStyle(.roundedBorder)
                Button("Sélectionner") { selectRange() }.buttonStyle(OrientationChipStyle()).disabled(from.isEmpty)
            }
            .font(.subheadline)
            .disabled(working)
            Text(selected.count == 1 ? String(localized: "1 page sélectionnée") : String(localized: "\(selected.count) pages sélectionnées"))
                .font(.footnote).foregroundStyle(Atelier.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Atelier.material(.regularMaterial))
        .overlay(alignment: .bottom) { Rectangle().fill(Atelier.hairline).frame(height: 1) }
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

    private func commit(rereading: Bool) {
        let pending = changes
        working = true
        error = nil
        Task {
            do {
                try await apply(pending, rereading)
                dismiss()
            } catch {
                self.error = error.localizedDescription
                working = false
            }
        }
    }
}

/// Bouton secondaire des commandes d'orientation, discret à côté des deux boutons de rotation.
private struct OrientationChipStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Atelier.font(14, weight: .medium))
            .padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(Atelier.textPrimary)
            .background(Atelier.surface, in: RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Atelier.smallRadius, style: .continuous).stroke(Atelier.hairline))
            .opacity(configuration.isPressed ? 0.7 : 1)
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
