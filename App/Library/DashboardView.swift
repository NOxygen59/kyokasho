// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Charts
import ReaderCore
import ReviewKit
import SwiftUI

/// Tableau de bord, ouvert depuis le temps de lecture de l'accueil : lecture, révision, bibliothèque, performances.
/// Les calculs sont dans `ReadingStats` et `PerformanceLog` ; cette vue ne fait que les montrer.
struct DashboardView: View {
    private enum Section: String, CaseIterable, Identifiable {
        case reading, review, library, performance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .reading: return String(localized: "Lecture")
            case .review: return String(localized: "Révision")
            case .library: return String(localized: "Bibliothèque")
            case .performance: return String(localized: "Performances")
            }
        }
    }

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var review: ReviewModel
    @ObservedObject private var readingTime = ReadingTimeTracker.shared
    @Environment(\.dismiss) private var dismiss
    @State private var section = Section.reading
    @State private var period = ReadingStats.Period.week
    @State private var filter = ReadingStats.Filter.everything
    @State private var reviewStats: ReviewStore.Stats?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Picker("", selection: $section) {
                        ForEach(Section.allCases) { Text(ui: $0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    switch section {
                    case .reading: readingSection
                    case .review: reviewSection
                    case .library: librarySection
                    case .performance: performanceSection
                    }
                }
                .padding(20)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
            .background(Atelier.canvas.ignoresSafeArea())
            .navigationTitle(Text("Tableau de bord"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { dismiss() } } }
        }
        .task { reviewStats = try? review.store.stats(settings: review.settings) }
    }

    // MARK: Lecture

    private var readingSection: some View {
        let stats = ReadingStats(sessions: readingTime.log.sessions, period: period, filter: filter)
        let retired = readingTime.log.retired
        let archived = filter == .everything ? retired.total : filter == .manga ? retired.manga : retired.total - retired.manga
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Picker("", selection: $period) {
                    Text("7 jours").tag(ReadingStats.Period.week)
                    Text("30 jours").tag(ReadingStats.Period.month)
                    Text("12 mois").tag(ReadingStats.Period.year)
                    Text("Tout").tag(ReadingStats.Period.all)
                }
                .pickerStyle(.segmented)
                Picker("", selection: $filter) {
                    Text("Tout").tag(ReadingStats.Filter.everything)
                    Text("Livres & Manuels").tag(ReadingStats.Filter.study)
                    Text("Manga").tag(ReadingStats.Filter.manga)
                }
                .pickerStyle(.segmented)
            }
            if period == .all, archived > 0 {
                Text(verbatim: String(format: String(localized: "Plus %@ de séances anciennes, comptées au total de l'accueil sans détail."),
                                      ReadingClock.format(archived)))
                    .font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
            }
            if stats.sessionCount == 0 {
                emptyNote(String(localized: "Rien sur cette période. Le compteur est reparti de zéro : seules les lectures faites depuis comptent."))
            } else {
                tiles([
                    (String(localized: "Temps"), ReadingClock.format(stats.total)),
                    (String(localized: "Jours lus"), "\(stats.activeDays)"),
                    (String(localized: "Par jour lu"), ReadingClock.format(stats.averagePerActiveDay)),
                    (String(localized: "Séances"), "\(stats.sessionCount)"),
                    (String(localized: "Séance moyenne"), ReadingClock.format(stats.averageSession)),
                    (String(localized: "Plus longue séance"), ReadingClock.format(stats.longestSession)),
                    (String(localized: "Pages vues"), "\(stats.pages)"),
                    (String(localized: "Mots cherchés"), "\(stats.lookups)"),
                    (String(localized: "Série en cours"), String(localized: "\(stats.currentStreak) j")),
                    (String(localized: "Meilleure série"), String(localized: "\(stats.bestStreak) j")),
                ])
                card(String(localized: "Temps de lecture")) { timeChart(stats) }
                card(String(localized: "Heures de lecture")) { hoursChart(stats) }
                card(String(localized: "Jours de la semaine")) { weekdayChart(stats) }
                card(String(localized: "Documents les plus lus")) { documentList(stats) }
            }
        }
    }

    private func minutes(_ seconds: TimeInterval) -> Double { seconds / 60 }

    private func timeChart(_ stats: ReadingStats) -> some View {
        let study = String(localized: "Livres & Manuels"), manga = String(localized: "Manga")
        return Chart(stats.buckets) { bucket in
            BarMark(x: .value("date", bucket.start, unit: stats.bucketsAreMonths ? .month : .day),
                    y: .value("min", minutes(bucket.study)))
                .foregroundStyle(by: .value("espace", study))
            BarMark(x: .value("date", bucket.start, unit: stats.bucketsAreMonths ? .month : .day),
                    y: .value("min", minutes(bucket.manga)))
                .foregroundStyle(by: .value("espace", manga))
        }
        .chartForegroundStyleScale([study: Atelier.Tint.read, manga: Atelier.Tint.japanese])
        .chartYAxisLabel(String(localized: "min"))
        .frame(height: 220)
    }

    private func hoursChart(_ stats: ReadingStats) -> some View {
        Chart(Array(stats.hours.enumerated()), id: \.offset) { hour, seconds in
            BarMark(x: .value("h", hour), y: .value("min", minutes(seconds)))
                .foregroundStyle(Atelier.Tint.read)
        }
        .chartXScale(domain: 0...23)
        .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { AxisGridLine(); AxisValueLabel() } }
        .chartYAxisLabel(String(localized: "min"))
        .frame(height: 140)
    }

    private func weekdayChart(_ stats: ReadingStats) -> some View {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        // Le premier jour de la semaine suit la région de l'appareil.
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
        return Chart(order, id: \.self) { day in
            BarMark(x: .value("jour", symbols[day]), y: .value("min", minutes(stats.weekdays[day])))
                .foregroundStyle(Atelier.Tint.read)
        }
        .chartXScale(domain: order.map { symbols[$0] })
        .chartYAxisLabel(String(localized: "min"))
        .frame(height: 140)
    }

    private func documentList(_ stats: ReadingStats) -> some View {
        let titles = Dictionary((model.documents + model.trashedDocuments).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let top = Array(stats.documents.prefix(8))
        let longest = top.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            ForEach(top, id: \.documentId) { row in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(ui: titles[row.documentId] ?? String(localized: "Document supprimé")).lineLimit(1)
                        Spacer()
                        Text(ui: ReadingClock.format(row.seconds)).foregroundStyle(Atelier.textSecondary)
                    }
                    .font(Atelier.font(13))
                    GeometryReader { area in
                        Capsule().fill(Atelier.Tint.read)
                            .frame(width: max(3, area.size.width * row.seconds / max(longest, 1)))
                    }
                    .frame(height: 4)
                }
            }
        }
    }

    // MARK: Révision

    @ViewBuilder
    private var reviewSection: some View {
        if let stats = reviewStats {
            VStack(alignment: .leading, spacing: 18) {
                tiles([
                    (String(localized: "Cartes"), "\(stats.totalCards)"),
                    (String(localized: "Cartes mûres"), "\(stats.matureCards)"),
                    (String(localized: "Mémorisation"), stats.retention.map { String(format: "%.0f %%", $0 * 100) } ?? "—"),
                    (String(localized: "À réviser"), "\(review.counts.total)"),
                ])
                card(String(localized: "Révisions, 30 derniers jours")) {
                    Chart(stats.reviewsPerDay.sorted { $0.key < $1.key }, id: \.key) { day, count in
                        BarMark(x: .value("date", day, unit: .day), y: .value("n", count))
                            .foregroundStyle(Atelier.Tint.japanese)
                    }
                    .frame(height: 220)
                }
            }
        } else {
            emptyNote(String(localized: "Pas encore de révision à montrer."))
        }
    }

    // MARK: Bibliothèque

    private var librarySection: some View {
        let documents = model.documents
        let manga = documents.filter(\.isInMangaSpace)
        let study = documents.filter { !$0.isInMangaSpace }
        let opened = documents.filter { $0.lastOpenedAt != nil }
        let pages = documents.reduce(0) { $0 + $1.pageCount }
        // Documents ouverts seulement : un document neuf est à l'index 0 sans avoir été lu. C'est la position de reprise.
        let openedPages = opened.reduce(0) { $0 + $1.pageCount }
        let reached = opened.reduce(0) { $0 + min($1.lastPageIndex + 1, $1.pageCount) }
        let size = documents.reduce(Int64(0)) { $0 + $1.fileSize } + model.trashedDocuments.reduce(Int64(0)) { $0 + $1.fileSize }
        return VStack(alignment: .leading, spacing: 18) {
            tiles([
                (String(localized: "Livres & Manuels"), "\(study.count)"),
                (String(localized: "Manga"), "\(manga.count)"),
                (String(localized: "Jamais ouverts"), "\(documents.count - opened.count)"),
                (String(localized: "À la corbeille"), "\(model.trashedDocuments.count)"),
                (String(localized: "Pages"), "\(pages)"),
                (String(localized: "Position de reprise, documents ouverts"), openedPages > 0 ? String(format: "%.0f %%", Double(reached) / Double(openedPages) * 100) : "—"),
                (String(localized: "Place occupée"), ByteCountFormatter.string(fromByteCount: size, countStyle: .file)),
            ])
            card(String(localized: "Avancement des documents ouverts")) {
                let recent = opened.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }.prefix(8)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(recent), id: \.id) { document in
                        HStack {
                            Text(ui: document.title).lineLimit(1)
                            Spacer()
                            Text(verbatim: "\(min(document.lastPageIndex + 1, document.pageCount)) / \(document.pageCount)")
                                .foregroundStyle(Atelier.textSecondary)
                        }
                        .font(Atelier.font(13))
                    }
                }
            }
        }
    }

    // MARK: Performances

    private var performanceSection: some View {
        let log = ResourceMonitor.shared.log
        return VStack(alignment: .leading, spacing: 18) {
            Text("Relevé seulement quand le moniteur est affiché. Ce sont les mesures de Kyōkasho, pas celles de tout l'iPad.")
                .font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
            if log.days.isEmpty {
                emptyNote(String(localized: "Aucune mesure pour l'instant : affiche le moniteur pendant que tu lis."))
            } else {
                card(String(localized: "Processeur, maximum par jour (100 % = un cœur)")) {
                    Chart(log.days, id: \.day) { day in
                        BarMark(x: .value("date", day.day, unit: .day), y: .value("%", day.maxCPU))
                            .foregroundStyle(Atelier.Tint.read)
                    }
                    .frame(height: 170)
                }
                card(String(localized: "Mémoire, maximum par jour (Mo)")) {
                    Chart(log.days, id: \.day) { day in
                        BarMark(x: .value("date", day.day, unit: .day), y: .value("Mo", day.maxRAM))
                            .foregroundStyle(Atelier.Tint.ai)
                    }
                    .frame(height: 170)
                }
                card(String(localized: "Derniers pics de processeur")) {
                    if log.peaks.isEmpty {
                        Text(verbatim: String(format: String(localized: "Aucun pic au-dessus de %.0f %%."), PerformanceLog.peakThreshold))
                            .font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(Array(log.peaks.suffix(10).reversed()), id: \.start) { peakRow($0) }
                        }
                    }
                }
            }
        }
    }

    private func peakRow(_ peak: PerformancePeak) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(verbatim: String(format: "%.0f %%", peak.maxCPU)).font(Atelier.font(15, weight: .semibold))
                Text(verbatim: String(format: String(localized: "moyenne %.0f %%"), peak.averageCPU)).foregroundStyle(Atelier.textSecondary)
                Text(ui: peak.inReader ? String(localized: "Dans le lecteur") : String(localized: "Hors du lecteur"))
                    .foregroundStyle(Atelier.textSecondary)
                Spacer()
                Text(peak.start, format: .dateTime.day().month().hour().minute()).foregroundStyle(Atelier.textTertiary)
            }
            partLine(String(localized: "Fil principal (interface)"), peak.mainThreadCPU)
            if !peak.activitySeconds.isEmpty {
                Text("Temps processeur des travaux, crédité à leur fin, jusqu'au premier relevé après le pic :").foregroundStyle(Atelier.textTertiary)
                ForEach(peak.activitySeconds.sorted { $0.value > $1.value }, id: \.key) { kind, seconds in
                    HStack {
                        Text(ui: ActivityCenter.Kind(rawValue: kind)?.title ?? kind)
                        Spacer()
                        Text(verbatim: String(format: String(localized: "%.1f s"), seconds)).foregroundStyle(Atelier.textSecondary)
                    }
                }
            }
            Text(verbatim: String(format: String(localized: "%lld s · %.0f Mo · %.0f i/s au plus bas"), peak.seconds, peak.ramMB, peak.lowestFPS))
                .foregroundStyle(Atelier.textTertiary)
        }
        .font(Atelier.font(12))
    }

    private func partLine(_ title: String, _ value: Double) -> some View {
        HStack {
            Text(ui: title)
            Spacer()
            Text(verbatim: String(format: "%.0f %%", value)).foregroundStyle(Atelier.textSecondary)
        }
    }

    // MARK: Éléments

    private func tiles(_ items: [(String, String)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], alignment: .leading, spacing: 10) {
            ForEach(items, id: \.0) { title, value in
                VStack(alignment: .leading, spacing: 4) {
                    Text(ui: title).font(Atelier.font(12)).foregroundStyle(Atelier.textSecondary)
                    Text(ui: value).font(Atelier.display(22)).foregroundStyle(Atelier.textPrimary).lineLimit(1).minimumScaleFactor(0.6)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(12), style: .continuous))
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            AtelierLabel(title)
            content()
        }
        .padding(14)
        .background(Atelier.surfaceHigh, in: RoundedRectangle(cornerRadius: Atelier.corner(14), style: .continuous))
    }

    private func emptyNote(_ text: String) -> some View {
        Text(ui: text).font(Atelier.font(14)).foregroundStyle(Atelier.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 40)
    }
}
