// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Charts
import ReaderCore
import ReviewKit
import SwiftUI

/// Tableau de bord, ouvert depuis le temps de lecture de l'accueil : lecture, révision, bibliothèque, performances.
/// Les calculs sont dans `ReadingStats` et `PerformanceLog` ; cette vue ne fait que les montrer.
///
/// Mise en page « Bento » (demande de NOxygen59 après la recette iPad 1.5.0 : l'ancienne liste de cases n'était pas
/// lisible) : une grille de tuiles de tailles différentes, un chiffre clé par tuile, et les courbes dans les grandes
/// tuiles. Large (iPad en paysage), une grande tuile occupe deux colonnes sur deux rangées à côté de quatre petites ;
/// étroit, tout s'empile sur deux colonnes.
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
    /// Fenêtre posée sur l'accueil : c'est elle qui se ferme. Sans valeur (feuille), `dismiss`.
    var onClose: (() -> Void)?

    /// Écart entre les tuiles ; la hauteur d'une petite tuile en découle pour la grande (deux rangées).
    private static let gap: CGFloat = 12
    private static let smallHeight: CGFloat = 132
    /// Traits des courbes et des anneaux : ce sont des données, pas des bordures d'interface. Ils ne suivent donc pas
    /// `Atelier.border` (un style à bordures épaisses rendrait les courbes illisibles).
    private static let curveWidth: CGFloat = 2.5
    private static let ringWidth: CGFloat = 7

    var body: some View {
        NavigationStack {
            GeometryReader { area in
                let wide = area.size.width >= 640
                ScrollView {
                    VStack(alignment: .leading, spacing: Self.gap) {
                        Picker("", selection: $section) {
                            ForEach(Section.allCases) { Text(ui: $0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .padding(.bottom, 6)
                        switch section {
                        case .reading: readingSection(wide: wide)
                        case .review: reviewSection(wide: wide)
                        case .library: librarySection(wide: wide)
                        case .performance: performanceSection(wide: wide)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 980)
                    .frame(maxWidth: .infinity)
                }
            }
            .background(Atelier.canvas.ignoresSafeArea())
            .navigationTitle(Text("Tableau de bord"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("OK") { if let onClose { onClose() } else { dismiss() } } } }
        }
        .task { reviewStats = try? review.store.stats(settings: review.settings) }
    }

    // MARK: Lecture

    @ViewBuilder
    private func readingSection(wide: Bool) -> some View {
        let stats = ReadingStats(sessions: readingTime.log.sessions, period: period, filter: filter)
        let retired = readingTime.log.retired
        let archived = filter == .everything ? retired.total : filter == .manga ? retired.manga : retired.total - retired.manga
        VStack(alignment: .leading, spacing: Self.gap) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { periodPicker; filterPicker }
                VStack(alignment: .leading, spacing: 8) { periodPicker; filterPicker }
            }
            if period == .all, archived > 0 {
                Text(verbatim: String(format: String(localized: "Plus %@ de séances anciennes, comptées au total de l'accueil sans détail."),
                                      ReadingClock.format(archived)))
                    .font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
            }
            if stats.sessionCount == 0 {
                emptyNote(String(localized: "Rien sur cette période. Le compteur est reparti de zéro : seules les lectures faites depuis comptent."))
            } else {
                heroRow(wide: wide,
                        hero: BentoTile(icon: "clock.fill", title: String(localized: "Temps de lecture"),
                                        value: ReadingClock.format(stats.total), tint: Atelier.Tint.read,
                                        caption: String(localized: "Séances") + " · \(stats.sessionCount)") {
                            timeChart(stats)
                        },
                        small: [
                            BentoTile(icon: "flame.fill", title: String(localized: "Série en cours"),
                                      value: String(localized: "\(stats.currentStreak) j"), tint: Atelier.Tint.japanese,
                                      caption: String(localized: "Meilleure série") + " · " + String(localized: "\(stats.bestStreak) j")),
                            BentoTile(icon: "calendar", title: String(localized: "Jours lus"),
                                      value: "\(stats.activeDays)", tint: Atelier.Tint.cloud),
                            BentoTile(icon: "chart.line.uptrend.xyaxis", title: String(localized: "Par jour lu"),
                                      value: ReadingClock.format(stats.averagePerActiveDay), tint: Atelier.Tint.read),
                            BentoTile(icon: "timer", title: String(localized: "Séance moyenne"),
                                      value: ReadingClock.format(stats.averageSession), tint: Atelier.Tint.ai,
                                      caption: String(localized: "Plus longue séance") + " · " + ReadingClock.format(stats.longestSession)),
                        ])
                pairRow(wide: wide,
                        BentoTile(icon: "sun.and.horizon.fill", title: String(localized: "Heures de lecture"), tint: Atelier.Tint.annotate) {
                            hoursChart(stats)
                        },
                        BentoTile(icon: "calendar.day.timeline.left", title: String(localized: "Jours de la semaine"), tint: Atelier.Tint.cloud) {
                            weekdayChart(stats)
                        })
                smallRow(wide: wide, [
                    BentoTile(icon: "doc.text.fill", title: String(localized: "Pages vues"), value: "\(stats.pages)", tint: Atelier.Tint.read),
                    BentoTile(icon: "character.book.closed.ja", title: String(localized: "Mots cherchés"), value: "\(stats.lookups)",
                              tint: Atelier.Tint.japanese),
                ])
                BentoTile(icon: "books.vertical.fill", title: String(localized: "Documents les plus lus"), tint: Atelier.Tint.read) {
                    documentList(stats)
                }
            }
        }
    }

    private var periodPicker: some View {
        Picker("", selection: $period) {
            Text("7 jours").tag(ReadingStats.Period.week)
            Text("30 jours").tag(ReadingStats.Period.month)
            Text("12 mois").tag(ReadingStats.Period.year)
            Text("Tout").tag(ReadingStats.Period.all)
        }
        .pickerStyle(.segmented)
    }

    private var filterPicker: some View {
        Picker("", selection: $filter) {
            Text("Tout").tag(ReadingStats.Filter.everything)
            Text("Livres & Manuels").tag(ReadingStats.Filter.study)
            Text("Manga").tag(ReadingStats.Filter.manga)
        }
        .pickerStyle(.segmented)
    }

    private func minutes(_ seconds: TimeInterval) -> Double { seconds / 60 }

    /// Courbes empilées des deux espaces, remplies d'un dégradé : la forme de la période se lit d'un coup d'œil.
    private func timeChart(_ stats: ReadingStats) -> some View {
        let study = String(localized: "Livres & Manuels"), manga = String(localized: "Manga")
        let unit: Calendar.Component = stats.bucketsAreMonths ? .month : .day
        return Chart {
            ForEach(stats.buckets) { bucket in
                AreaMark(x: .value("date", bucket.start, unit: unit), y: .value("min", minutes(bucket.study)))
                    .foregroundStyle(by: .value("espace", study))
                    .interpolationMethod(.catmullRom)
                AreaMark(x: .value("date", bucket.start, unit: unit), y: .value("min", minutes(bucket.manga)))
                    .foregroundStyle(by: .value("espace", manga))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartForegroundStyleScale([study: Atelier.Tint.read.opacity(0.75), manga: Atelier.Tint.japanese.opacity(0.75)])
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Atelier.hairline); AxisValueLabel() } }
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 5)) { _ in AxisValueLabel() } }
        .chartYAxisLabel(String(localized: "min"))
    }

    /// Courbe des heures, pointe la plus haute marquée.
    private func hoursChart(_ stats: ReadingStats) -> some View {
        let points = Array(stats.hours.enumerated())
        let peak = points.max { $0.element < $1.element }
        return Chart {
            ForEach(points, id: \.offset) { hour, seconds in
                AreaMark(x: .value("h", hour), y: .value("min", minutes(seconds)))
                    .foregroundStyle(LinearGradient(colors: [Atelier.Tint.annotate.opacity(0.45), Atelier.Tint.annotate.opacity(0.02)],
                                                    startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("h", hour), y: .value("min", minutes(seconds)))
                    .foregroundStyle(Atelier.Tint.annotate)
                    .lineStyle(StrokeStyle(lineWidth: Self.curveWidth, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
            if let peak, peak.element > 0 {
                PointMark(x: .value("h", peak.offset), y: .value("min", minutes(peak.element)))
                    .foregroundStyle(Atelier.Tint.annotate)
                    .symbolSize(70)
                    .annotation(position: .top) {
                        Text(verbatim: "\(peak.offset) h").font(Atelier.font(11, weight: .semibold)).foregroundStyle(Atelier.textSecondary)
                    }
            }
        }
        .chartXScale(domain: 0...23)
        .chartXAxis { AxisMarks(values: [0, 6, 12, 18, 23]) { AxisValueLabel() } }
        .chartYAxis(.hidden)
    }

    private func weekdayChart(_ stats: ReadingStats) -> some View {
        let calendar = Calendar.current
        let symbols = calendar.shortWeekdaySymbols
        // Le premier jour de la semaine suit la région de l'appareil.
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
        let best = order.max { stats.weekdays[$0] < stats.weekdays[$1] }
        return Chart(order, id: \.self) { day in
            BarMark(x: .value("jour", symbols[day]), y: .value("min", minutes(stats.weekdays[day])), width: .ratio(0.6))
                .foregroundStyle(day == best ? Atelier.Tint.cloud : Atelier.Tint.cloud.opacity(0.35))
                .cornerRadius(6)
        }
        .chartXScale(domain: order.map { symbols[$0] })
        .chartYAxis(.hidden)
    }

    private func documentList(_ stats: ReadingStats) -> some View {
        let titles = Dictionary((model.documents + model.trashedDocuments).map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let top = Array(stats.documents.prefix(6))
        let longest = top.first?.seconds ?? 1
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(top.enumerated()), id: \.element.documentId) { rank, row in
                HStack(spacing: 12) {
                    Text(verbatim: "\(rank + 1)").font(Atelier.display(18)).foregroundStyle(Atelier.textTertiary).frame(width: 22)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(ui: titles[row.documentId] ?? String(localized: "Document supprimé")).lineLimit(1)
                            Spacer()
                            Text(ui: ReadingClock.format(row.seconds)).foregroundStyle(Atelier.textSecondary)
                        }
                        .font(Atelier.font(13, weight: .medium))
                        meter(row.seconds / max(longest, 1), tint: Atelier.Tint.read)
                    }
                }
            }
        }
    }

    // MARK: Révision

    @ViewBuilder
    private func reviewSection(wide: Bool) -> some View {
        if let stats = reviewStats {
            let days = stats.reviewsPerDay.sorted { $0.key < $1.key }
            let total = days.reduce(0) { $0 + $1.value }
            heroRow(wide: wide,
                    hero: BentoTile(icon: "rectangle.stack.badge.play.fill", title: String(localized: "Révisions, 30 derniers jours"),
                                    value: "\(total)", tint: Atelier.Tint.japanese) {
                        Chart {
                            ForEach(days, id: \.key) { day, count in
                                AreaMark(x: .value("date", day, unit: .day), y: .value("n", count))
                                    .foregroundStyle(LinearGradient(colors: [Atelier.Tint.japanese.opacity(0.45), Atelier.Tint.japanese.opacity(0.02)],
                                                                    startPoint: .top, endPoint: .bottom))
                                    .interpolationMethod(.catmullRom)
                                LineMark(x: .value("date", day, unit: .day), y: .value("n", count))
                                    .foregroundStyle(Atelier.Tint.japanese)
                                    .lineStyle(StrokeStyle(lineWidth: Self.curveWidth, lineCap: .round))
                                    .interpolationMethod(.catmullRom)
                            }
                        }
                        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Atelier.hairline); AxisValueLabel() } }
                    },
                    small: [
                        .detailed(icon: "brain.head.profile", title: String(localized: "Mémorisation"),
                                  value: stats.retention.map { String(format: "%.0f %%", $0 * 100) } ?? "—", tint: Atelier.Tint.read, detail: {
                            if let retention = stats.retention { ring(retention, tint: Atelier.Tint.read) }
                        }),
                        BentoTile(icon: "tray.full.fill", title: String(localized: "À réviser"), value: "\(review.counts.total)",
                                  tint: Atelier.Tint.annotate),
                        BentoTile(icon: "square.stack.3d.up.fill", title: String(localized: "Cartes"), value: "\(stats.totalCards)",
                                  tint: Atelier.Tint.cloud),
                        .detailed(icon: "leaf.fill", title: String(localized: "Cartes mûres"), value: "\(stats.matureCards)",
                                  tint: Atelier.Tint.japanese, detail: {
                            if stats.totalCards > 0 { ring(Double(stats.matureCards) / Double(stats.totalCards), tint: Atelier.Tint.japanese) }
                        }),
                    ])
        } else {
            emptyNote(String(localized: "Pas encore de révision à montrer."))
        }
    }

    // MARK: Bibliothèque

    @ViewBuilder
    private func librarySection(wide: Bool) -> some View {
        let documents = model.documents
        let manga = documents.filter(\.isInMangaSpace)
        let study = documents.filter { !$0.isInMangaSpace }
        let opened = documents.filter { $0.lastOpenedAt != nil }
        let pages = documents.reduce(0) { $0 + $1.pageCount }
        // Documents ouverts seulement : un document neuf est à l'index 0 sans avoir été lu. C'est la position de reprise.
        let openedPages = opened.reduce(0) { $0 + $1.pageCount }
        let reached = opened.reduce(0) { $0 + min($1.lastPageIndex + 1, $1.pageCount) }
        let progress = openedPages > 0 ? Double(reached) / Double(openedPages) : nil
        let size = documents.reduce(Int64(0)) { $0 + $1.fileSize } + model.trashedDocuments.reduce(Int64(0)) { $0 + $1.fileSize }
        VStack(alignment: .leading, spacing: Self.gap) {
            heroRow(wide: wide,
                    hero: BentoTile(icon: "books.vertical.fill", title: String(localized: "Bibliothèque"), value: "\(documents.count)",
                                    tint: Atelier.Tint.read) {
                        spaceSplit(study: study.count, manga: manga.count)
                    },
                    small: [
                        .detailed(icon: "bookmark.fill", title: String(localized: "Position de reprise, documents ouverts"),
                                  value: progress.map { String(format: "%.0f %%", $0 * 100) } ?? "—", tint: Atelier.Tint.annotate, detail: {
                            if let progress { ring(progress, tint: Atelier.Tint.annotate) }
                        }),
                        BentoTile(icon: "doc.on.doc.fill", title: String(localized: "Pages"), value: "\(pages)", tint: Atelier.Tint.cloud),
                        BentoTile(icon: "sparkles", title: String(localized: "Jamais ouverts"), value: "\(documents.count - opened.count)",
                                  tint: Atelier.Tint.ai),
                        BentoTile(icon: "internaldrive.fill", title: String(localized: "Place occupée"),
                                  value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file), tint: Atelier.Tint.japanese,
                                  caption: String(localized: "À la corbeille") + " · \(model.trashedDocuments.count)"),
                    ])
            BentoTile(icon: "chart.bar.doc.horizontal.fill", title: String(localized: "Avancement des documents ouverts"), tint: Atelier.Tint.read) {
                let recent = opened.sorted { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }.prefix(8)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(recent), id: \.id) { document in
                        let reachedPage = min(document.lastPageIndex + 1, document.pageCount)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(ui: document.title).lineLimit(1)
                                Spacer()
                                Text(verbatim: "\(reachedPage) / \(document.pageCount)").foregroundStyle(Atelier.textSecondary)
                            }
                            .font(Atelier.font(13, weight: .medium))
                            meter(Double(reachedPage) / Double(max(document.pageCount, 1)),
                                  tint: document.isInMangaSpace ? Atelier.Tint.japanese : Atelier.Tint.read)
                        }
                    }
                }
            }
        }
    }

    /// Part des deux espaces : une barre partagée et les deux nombres en grand.
    private func spaceSplit(study: Int, manga: Int) -> some View {
        let total = max(study + manga, 1)
        return VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 0)
            GeometryReader { area in
                HStack(spacing: 4) {
                    Capsule().fill(Atelier.Tint.read).frame(width: max(6, (area.size.width - 4) * Double(study) / Double(total)))
                    Capsule().fill(Atelier.Tint.japanese)
                }
            }
            .frame(height: 16)
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                splitLegend(String(localized: "Livres & Manuels"), study, Atelier.Tint.read)
                splitLegend(String(localized: "Manga"), manga, Atelier.Tint.japanese)
            }
        }
    }

    private func splitLegend(_ title: String, _ count: Int, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(count)").font(Atelier.display(30)).foregroundStyle(tint)
            Text(ui: title).font(Atelier.font(12, weight: .medium)).foregroundStyle(Atelier.textSecondary)
        }
    }

    // MARK: Performances

    @ViewBuilder
    private func performanceSection(wide: Bool) -> some View {
        let log = ResourceMonitor.shared.log
        VStack(alignment: .leading, spacing: Self.gap) {
            Text("Relevé seulement quand le moniteur est affiché. Ce sont les mesures de Kyōkasho, pas celles de tout l'iPad.")
                .font(Atelier.font(13)).foregroundStyle(Atelier.textSecondary)
            if log.days.isEmpty {
                emptyNote(String(localized: "Aucune mesure pour l'instant : affiche le moniteur pendant que tu lis."))
            } else {
                let maxCPU = log.days.map(\.maxCPU).max() ?? 0
                let maxRAM = log.days.map(\.maxRAM).max() ?? 0
                pairRow(wide: wide,
                        BentoTile(icon: "cpu", title: String(localized: "Processeur, maximum par jour (100 % = un cœur)"),
                                  value: String(format: "%.0f %%", maxCPU), tint: Atelier.Tint.read) {
                            dailyCurve(log.days.map { ($0.day, $0.maxCPU) }, tint: Atelier.Tint.read)
                        },
                        BentoTile(icon: "memorychip", title: String(localized: "Mémoire, maximum par jour (Mo)"),
                                  value: String(format: String(localized: "%.0f Mo"), maxRAM), tint: Atelier.Tint.ai) {
                            dailyCurve(log.days.map { ($0.day, $0.maxRAM) }, tint: Atelier.Tint.ai)
                        })
                BentoTile(icon: "bolt.fill", title: String(localized: "Derniers pics de processeur"), tint: Atelier.Tint.japanese) {
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

    private func dailyCurve(_ points: [(Date, Double)], tint: Color) -> some View {
        Chart {
            ForEach(points, id: \.0) { day, value in
                AreaMark(x: .value("date", day, unit: .day), y: .value("v", value))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.4), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("date", day, unit: .day), y: .value("v", value))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: Self.curveWidth, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("date", day, unit: .day), y: .value("v", value))
                    .foregroundStyle(tint)
                    .symbolSize(points.count > 14 ? 0 : 24)
            }
        }
        .chartYAxis { AxisMarks(position: .trailing) { _ in AxisGridLine().foregroundStyle(Atelier.hairline); AxisValueLabel() } }
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

    // MARK: Grille Bento

    /// Grande tuile (deux colonnes, deux rangées) et quatre petites. Étroit : la grande en haut, puis les petites par deux.
    @ViewBuilder
    private func heroRow<Hero: View>(wide: Bool, hero: Hero, small: [BentoTile<AnyView>]) -> some View {
        let heroHeight = Self.smallHeight * 2 + Self.gap
        if wide {
            HStack(alignment: .top, spacing: Self.gap) {
                hero.frame(height: heroHeight)
                smallGrid(small)
            }
        } else {
            VStack(spacing: Self.gap) {
                hero.frame(height: heroHeight)
                smallGrid(small)
            }
        }
    }

    private func smallGrid(_ tiles: [BentoTile<AnyView>]) -> some View {
        VStack(spacing: Self.gap) {
            ForEach(Array(stride(from: 0, to: tiles.count, by: 2)), id: \.self) { start in
                HStack(spacing: Self.gap) {
                    ForEach(start..<min(start + 2, tiles.count), id: \.self) { tiles[$0].frame(height: Self.smallHeight) }
                }
            }
        }
    }

    /// Deux tuiles moyennes côte à côte (une colonne double chacune) ; étroit, l'une sous l'autre.
    @ViewBuilder
    private func pairRow<A: View, B: View>(wide: Bool, _ a: A, _ b: B) -> some View {
        if wide {
            HStack(spacing: Self.gap) { a.frame(height: 230); b.frame(height: 230) }
        } else {
            VStack(spacing: Self.gap) { a.frame(height: 230); b.frame(height: 230) }
        }
    }

    /// Rangée de petites tuiles chiffrées, sur toute la largeur.
    private func smallRow(wide: Bool, _ tiles: [BentoTile<AnyView>]) -> some View {
        HStack(spacing: Self.gap) {
            ForEach(tiles.indices, id: \.self) { tiles[$0].frame(height: Self.smallHeight) }
        }
    }

    // MARK: Éléments

    private func meter(_ fraction: Double, tint: Color) -> some View {
        GeometryReader { area in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.15))
                Capsule().fill(tint).frame(width: max(4, area.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }

    /// Anneau de progression (iOS 16 n'a pas les secteurs de Swift Charts).
    private func ring(_ fraction: Double, tint: Color) -> some View {
        HStack {
            Spacer(minLength: 0)
            ZStack {
                Circle().stroke(tint.opacity(0.18), lineWidth: Self.ringWidth)
                Circle().trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: Self.ringWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 40, height: 40)
        }
        .accessibilityHidden(true)
    }

    private func emptyNote(_ text: String) -> some View {
        Text(ui: text).font(Atelier.font(14)).foregroundStyle(Atelier.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center).padding(.vertical, 40)
    }
}

/// Tuile du tableau de bord : pastille d'icône et titre en haut, chiffre clé en grand, détail, puis le contenu
/// (courbe, anneau, liste) qui prend la place restante.
private struct BentoTile<Content: View>: View {
    let icon: String
    let title: String
    var value: String?
    let tint: Color
    var caption: String?
    let content: Content

    init(icon: String, title: String, value: String? = nil, tint: Color, caption: String? = nil,
         @ViewBuilder content: () -> Content) {
        self.icon = icon
        self.title = title
        self.value = value
        self.tint = tint
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(Atelier.font(12, weight: .bold))
                    .foregroundStyle(Atelier.onAccentInk.opacity(0.9))
                    .frame(width: 24, height: 24)
                    .background(tint, in: RoundedRectangle(cornerRadius: Atelier.corner(7), style: .continuous))
                Text(ui: title).font(Atelier.font(13, weight: .semibold)).foregroundStyle(Atelier.textSecondary)
                    .lineLimit(2).minimumScaleFactor(0.85)
                Spacer(minLength: 0)
            }
            if let value {
                Text(ui: value)
                    .font(Atelier.display(34))
                    .foregroundStyle(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .lineLimit(1).minimumScaleFactor(0.5)
            }
            if let caption {
                Text(ui: caption).font(Atelier.font(12)).foregroundStyle(Atelier.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Atelier.surface, in: RoundedRectangle(cornerRadius: Atelier.corner(22), style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Atelier.corner(22), style: .continuous)
            .strokeBorder(Atelier.hairline, lineWidth: Atelier.border(1)))
    }
}

extension BentoTile where Content == AnyView {
    /// Tuile chiffrée seule (pas de courbe), ou avec un petit contenu mis dans la grille des petites tuiles.
    init(icon: String, title: String, value: String? = nil, tint: Color, caption: String? = nil) {
        self.init(icon: icon, title: title, value: value, tint: tint, caption: caption) { AnyView(EmptyView()) }
    }

    /// Petite tuile avec un petit contenu (anneau) : fonction nommée, pour ne pas se confondre avec l'initialiseur
    /// générique quand la fermeture suit l'appel.
    static func detailed<Inner: View>(icon: String, title: String, value: String? = nil, tint: Color, caption: String? = nil,
                                      @ViewBuilder detail: () -> Inner) -> BentoTile<AnyView> {
        let inner = detail()
        return BentoTile(icon: icon, title: title, value: value, tint: tint, caption: caption) { AnyView(inner) }
    }
}
