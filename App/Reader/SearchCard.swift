// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

/// Bord inférieur de la barre, sans dupliquer sa hauteur dans la carte.
struct SearchBarBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        if let next = nextValue() { value = next }
    }
}

/// La carte seule reçoit les touchers ; cette couche ne réserve aucune place au-dessus du PDF.
struct SearchCardOverlay: View {
    let reader: ReaderController
    @Binding var isPresented: Bool
    let barBounds: Anchor<CGRect>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Gardés à la réouverture, comme les résultats du moteur.
    @State private var query = ""
    @State private var submittedTerm = ""

    var body: some View {
        GeometryReader { area in
            let gap = Atelier.gap
            let top = (barBounds.map { area[$0].maxY } ?? 44) + gap
            let width = min(380, max(0, area.size.width - 2 * gap))
            let height = max(0, min(area.size.height * 0.6, area.size.height - top - gap))
            Group {
                if isPresented, width > 0, height > 0 {
                    SearchCard(reader: reader, query: $query, submittedTerm: $submittedTerm, maxHeight: height) {
                        isPresented = false
                    }
                    .frame(width: width)
                    .transition(reduceMotion ? .identity : .opacity.combined(with: .offset(y: -8)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(.top, top)
            // Proposer le plafond à la carte sans lui imposer cette hauteur quand la liste tient.
            .padding(.bottom, max(gap, area.size.height - top - height))
            .padding(.trailing, gap)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isPresented)
        }
    }
}

private struct SearchCard: View {
    @ObservedObject var reader: ReaderController
    @Binding var query: String
    @Binding var submittedTerm: String
    let maxHeight: CGFloat
    /// Fermer la carte seule : `reader.close()` libérerait le PDF et fermerait le lecteur.
    var close: () -> Void
    @Environment(\.themeRevision) private var themeRevision
    @FocusState private var fieldFocused: Bool

    var body: some View {
        let _ = themeRevision
        let shape = RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header.fixedSize(horizontal: false, vertical: true)
            // Ne mesurer que les listes qui peuvent tenir, sans remonter le champ quand les résultats arrivent.
            if CGFloat(reader.searchResults.count) * 44 <= maxHeight {
                ViewThatFits(in: .vertical) {
                    VStack(alignment: .leading, spacing: 0) { rows }
                        .fixedSize(horizontal: false, vertical: true)
                    scrollingRows
                }
            } else {
                scrollingRows
            }
        }
        .clipShape(shape)
        .background(Atelier.material(.regularMaterial), in: shape)
        // Contenu avec du texte : ombre de la forme seule (règle des jetons de style), comme l'ancienne feuille.
        .atelierShapeShadow(shape, opacity: 0.3, radius: 16, y: 6)
        .overlay { shape.strokeBorder(Atelier.hairline, lineWidth: Atelier.border(1)).allowsHitTesting(false) }
        .tint(Atelier.Tint.read)
        .atelierFontDesign()
        .onChange(of: query) { value in
            if value.isEmpty {
                submittedTerm = ""
                reader.search("")
            }
        }
    }

    private var scrollingRows: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) { rows }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 0) {
                    Button(action: submit) {
                        Image(systemName: "magnifyingglass")
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("Rechercher")
                    TextField("Rechercher dans le document", text: $query, prompt: Text("Mot ou phrase"))
                        .foregroundStyle(Atelier.textPrimary)
                        .focused($fieldFocused)
                        .submitLabel(.search)
                        .onSubmit(submit)
                    if !query.isEmpty {
                        Button { query = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Effacer la recherche")
                    }
                }
                .padding(.trailing, query.isEmpty ? 8 : 0)
                .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.smallRadius))

                Button("Fermer") { close() }
                    .font(.subheadline.weight(.semibold))
                    .frame(minHeight: 44)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .buttonStyle(.borderless)

            if !submittedTerm.isEmpty {
                HStack(spacing: 8) {
                    Text("Résultats : \(reader.searchResults.count)")
                        .accessibilityAddTraits(.isHeader)
                    if reader.isSearching {
                        ProgressView().controlSize(.small).accessibilityLabel("Recherche…")
                    }
                }
                .font(.footnote)
                .foregroundStyle(Atelier.textSecondary)
            }
        }
        .padding(Atelier.gap)
    }

    @ViewBuilder
    private var rows: some View {
        if !submittedTerm.isEmpty, reader.searchResults.isEmpty, !reader.isSearching {
            Text("Aucun résultat.")
                .font(.footnote)
                .foregroundStyle(Atelier.textSecondary)
                .padding([.horizontal, .bottom], Atelier.gap)
        }
        ForEach(reader.searchResults) { result in
            Divider().overlay(Atelier.hairline).padding(.horizontal, Atelier.gap)
            Button {
                fieldFocused = false
                reader.show(result)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Page \(reader.document.pageLabel(result.sourcePage))")
                        .font(.caption.bold()).foregroundStyle(Atelier.textSecondary)
                    Text(excerpt(result.context))
                        .font(.subheadline)
                        .foregroundStyle(Atelier.textPrimary)
                }
                .padding(.horizontal, Atelier.gap)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func submit() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        submittedTerm = term
        reader.search(term)
        fieldFocused = false
    }

    private func excerpt(_ context: String) -> AttributedString {
        var styled = AttributedString(context)
        guard !submittedTerm.isEmpty else { return styled }
        // Même comparaison que PDFKit, sans modifier le texte du document.
        var start = context.startIndex
        while start < context.endIndex,
              let match = context.range(of: submittedTerm, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                        range: start..<context.endIndex), !match.isEmpty {
            if let range = Range(match, in: styled) {
                styled[range].inlinePresentationIntent = .stronglyEmphasized
                styled[range].backgroundColor = Atelier.Tint.read.opacity(0.24)
            }
            start = match.upperBound
        }
        return styled
    }
}
