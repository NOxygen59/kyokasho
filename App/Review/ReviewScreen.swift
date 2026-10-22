// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import ReviewKit
import SwiftUI

/// Séance de révision plein écran. Paysage : carte au centre, réponses à droite.
/// Clavier : Espace = montrer / Bien, 1–4 = réponses, ⌘Z = annuler, Échap = fermer.
struct ReviewScreen: View {
    @EnvironmentObject private var review: ReviewModel
    @Environment(\.dismiss) private var dismiss

    private struct Undo { let before: StudyCard; let logId: Int64; let grade: Grade }

    @State private var current: StudyCard?
    @State private var showAnswer = false
    @State private var later: Date?
    @State private var shownAt = Date()
    @State private var undoStack: [Undo] = []
    @State private var reviewed = 0
    @State private var again = 0
    @State private var error: String?
    @State private var showBrowser = false

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: Atelier.gap) {
                header
                if landscape {
                    HStack(spacing: Atelier.gap) {
                        cardArea
                        answerColumn.frame(width: 250)
                    }
                } else {
                    cardArea
                    answerColumn.frame(height: current == nil ? 0 : 150)
                }
            }
            .padding(Atelier.gap)
        }
        .background(Atelier.canvas.ignoresSafeArea())
        .onAppear { advance(excluding: nil) }
        .task(id: later) {
            // Une carte en apprentissage revient : on l'affiche dès qu'elle est due.
            guard let later else { return }
            let wait = later.timeIntervalSinceNow
            if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000)) }
            if !Task.isCancelled { advance(excluding: nil) }
        }
        .sheet(isPresented: $showBrowser, onDismiss: { advance(excluding: nil) }) {
            CardBrowserView().environmentObject(review).preferredColorScheme(.dark)
        }
        .alert("Erreur", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 12) {
            CapsuleButton(icon: "xmark", label: "Fermer") { dismiss() }
                .keyboardShortcut(.escape, modifiers: [])
            AtelierLabel("Révisions", tint: Atelier.Tint.japanese)
            Spacer()
            countsView
            CapsuleButton(icon: "arrow.uturn.backward", label: "Annuler") { undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(undoStack.isEmpty)
                .opacity(undoStack.isEmpty ? 0.4 : 1)
            CapsuleButton(icon: "rectangle.stack", label: "Cartes") { showBrowser = true }
        }
    }

    private var countsView: some View {
        HStack(spacing: 14) {
            count(review.counts.new, "nouvelles", Atelier.Tint.cloud)
            count(review.counts.learning, "en cours", Atelier.Tint.japanese)
            count(review.counts.review, "à revoir", Atelier.Tint.read)
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .atelierPanel(radius: 20)
    }

    private func count(_ n: Int, _ label: String, _ tint: Color) -> some View {
        HStack(spacing: 5) {
            Text("\(n)").font(Atelier.mono).foregroundStyle(tint)
            Text(label).font(.system(size: 12)).foregroundStyle(Atelier.textTertiary)
        }
    }

    // MARK: Carte

    @ViewBuilder
    private var cardArea: some View {
        Group {
            if let card = current, let template = template(for: card) {
                let sides = template.render(card.fields)
                let html = CardHTML.page(css: template.css, body: showAnswer ? sides.back : sides.front)
                let frontSounds = CardHTML.sounds(in: sides.front)
                CardWebView(html: html, mediaRoot: review.store.mediaRoot,
                            autoplay: showAnswer ? CardHTML.sounds(in: sides.back).filter { !frontSounds.contains($0) } : frontSounds,
                            onTap: { if !showAnswer { reveal() } })
                    .id(card.id)
            } else {
                finished
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .atelierPanel()
    }

    private var finished: some View {
        VStack(spacing: 14) {
            Text(later == nil ? "終" : "待").font(.custom("HiraMinProN-W6", size: 64))
                .foregroundStyle(Atelier.Tint.japanese.opacity(0.85))
            if let later {
                Text("Reviens à \(later.formatted(date: .omitted, time: .shortened))")
                    .font(Atelier.display(26)).foregroundStyle(Atelier.textPrimary)
                Text("Une carte en apprentissage revient bientôt. Tu peux laisser cet écran ouvert.")
                    .foregroundStyle(Atelier.textSecondary)
            } else {
                Text(reviewed == 0 ? "Rien à réviser pour l'instant" : "Séance finie")
                    .font(Atelier.display(26)).foregroundStyle(Atelier.textPrimary)
                if reviewed == 0 {
                    Text("Ajoute des cartes avec ＋ dans le popup du dictionnaire.").foregroundStyle(Atelier.textSecondary)
                }
            }
            if reviewed > 0 {
                Text("\(reviewed) réponse\(reviewed > 1 ? "s" : "") · \(Int((Double(reviewed - again) / Double(reviewed) * 100).rounded())) % retenues")
                    .font(Atelier.mono).foregroundStyle(Atelier.textSecondary)
            }
            Button { dismiss() } label: { Label("Retour à la bibliothèque", systemImage: "books.vertical") }
                .buttonStyle(AtelierButtonStyle(tint: Atelier.Tint.read))
                .padding(.top, 8)
        }
        .padding(30)
    }

    // MARK: Réponses

    @ViewBuilder
    private var answerColumn: some View {
        if let card = current {
            if showAnswer {
                let preview = ReviewScheduler(settings: review.settings).preview(card)
                let now = Date()
                VStack(spacing: 10) {
                    ForEach(Grade.allCases) { grade in
                        Button { answer(grade) } label: {
                            VStack(spacing: 3) {
                                Text(grade.label).font(.system(size: 17, weight: .semibold))
                                Text(preview[grade].map { ReviewScheduler.intervalLabel(from: now, to: $0) } ?? "—")
                                    .font(Atelier.mono).opacity(0.75)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .foregroundStyle(Color.black.opacity(0.85))
                            .background(tint(grade), in: RoundedRectangle(cornerRadius: Atelier.radius, style: .continuous))
                        }
                        .buttonStyle(PressScale())
                        .keyboardShortcut(KeyEquivalent(Character(String(grade.rawValue))), modifiers: [])
                    }
                    // Espace = Bien.
                    Button("") { answer(.good) }.keyboardShortcut(.space, modifiers: []).opacity(0).frame(height: 0)
                }
            } else {
                Button { reveal() } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "eye").font(.system(size: 22, weight: .semibold))
                        Text("Montrer la réponse").font(.system(size: 17, weight: .semibold))
                        Text("ou touche la carte · Espace").font(.system(size: 12)).opacity(0.6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .foregroundStyle(Atelier.textPrimary)
                    .atelierPanel()
                }
                .buttonStyle(PressScale())
                .keyboardShortcut(.space, modifiers: [])
            }
        }
    }

    private func tint(_ grade: Grade) -> Color {
        switch grade {
        case .again: return Atelier.Tint.japanese
        case .hard: return Atelier.Tint.annotate
        case .good: return Atelier.Tint.read
        case .easy: return Atelier.Tint.cloud
        }
    }

    // MARK: Logique

    private func template(for card: StudyCard) -> NoteTemplate? {
        review.templates.first { $0.id == card.templateId } ?? review.defaultTemplate
    }

    private func reveal() {
        withAnimation(.easeOut(duration: 0.15)) { showAnswer = true }
    }

    // FDR-6.4 : accès base sur le fil principal → tâche de fond (aussi `answer`). Voir § 6 étape 6.
    private func advance(excluding: Int64?) {
        review.refresh()
        do {
            switch try review.store.next(settings: review.settings, now: Date(), excluding: excluding) {
            case .card(let card):
                current = card
                later = nil
            case .later(let date):
                current = nil
                later = date
            case .done:
                current = nil
                later = nil
            }
        } catch {
            self.error = error.localizedDescription
            current = nil
        }
        showAnswer = false
        shownAt = Date()
    }

    private func answer(_ grade: Grade) {
        guard let card = current, showAnswer else { return }
        let now = Date()
        // Durée plafonnée à 60 s (une pause ne fausse pas les stats), comme Anki.
        let duration = min(60, now.timeIntervalSince(shownAt))
        do {
            let (updated, log) = try ReviewScheduler(settings: review.settings).review(card, grade: grade, now: now, duration: duration)
            let saved = try review.store.record(updated, log: log)
            if let id = saved.id { undoStack.append(Undo(before: card, logId: id, grade: grade)) }
            reviewed += 1
            if grade == .again { again += 1 }
            advance(excluding: card.id)
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func undo() {
        guard let last = undoStack.popLast() else { return }
        do {
            try review.store.undo(restoring: last.before, logId: last.logId)
            reviewed = max(0, reviewed - 1)
            if last.grade == .again { again = max(0, again - 1) }
            review.refresh()
            current = last.before
            later = nil
            showAnswer = false
            shownAt = Date()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
