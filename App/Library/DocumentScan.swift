// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Foundation
import GLMOCRKit
import OCRKit
import ReaderCore

extension Notification.Name {
    /// Une page vient d'être lue par OvisOCR2 (`object` : `DocumentScan.PageRead`).
    static let aiPageRead = Notification.Name("kyokasho.aiPageRead")
}

/// Lecture IA (OvisOCR2) de tout le document, à l'import et à l'ouverture : seulement les pages **pas encore lues**
/// (fichier `Analysis/<id>/ovisocr2-<page>.md`, le même que l'analyse et la mise en page IA). Tâche de l'app
/// (`AITaskCenter`) : continue hors du lecteur, pastille avec progression et journal, arrêt confirmé deux fois.
/// Son texte sert aux furigana (lectures justes), à la mise en page IA et à la vérification.
@MainActor
enum DocumentScan {
    struct PageRead { let documentId: String; let page: Int }

    static func key(_ documentId: String) -> String { "scan|\(documentId)" }

    /// Réglage (page d'OvisOCR2 dans les Réglages) : lecture automatique à l'import et à l'ouverture.
    static let autoKey = "scan.auto"

    /// Lance la lecture si OvisOCR2 est installé et qu'il reste des pages ; rien si elle tourne déjà ou si l'analyse
    /// du document entier (qui lit les mêmes pages) est en cours.
    static func start(_ document: LibraryDocument, url: URL, ocr: OCRService) {
        guard UserDefaults.standard.object(forKey: autoKey) as? Bool ?? true, OvisOCR2Reader().isAvailable,
              DocumentAnalysisService.shared.progress?.documentId != document.id else { return }
        let id = document.id
        let pages = (0..<document.pageCount).filter { !FileManager.default.fileExists(atPath: file(id, $0).path) }
        guard !pages.isEmpty else { return }
        let language = OCRTargetLanguage.forDocument(id)
        AITaskCenter.shared.run(key(id), title: String(localized: "Lecture IA de « \(document.title) »"), modelId: ModelSpec.ovisocr2.id, activity: "lecture") { job in
            let center = AITaskCenter.shared
            center.log(job, "\(pages.count) page(s) à lire sur \(document.pageCount)")
            // Une lecture de document à la fois (import de plusieurs PDF) : un seul modèle, pas de va-et-vient.
            let mine = center.jobs.first { $0.id == job }?.started ?? .distantPast
            var waiting = false
            while center.jobs.contains(where: { $0.key.hasPrefix("scan|") && $0.id != job && $0.started < mine }) {
                if !waiting { center.log(job, "En attente de la lecture d'un autre document…"); waiting = true }
                try await Task.sleep(nanoseconds: 3_000_000_000)
            }
            var failures = 0
            for (k, page) in pages.enumerated() {
                center.setProgress(job, done: k, total: pages.count)
                try Task.checkCancellation()
                // L'analyse du document entier a démarré : elle lit ces pages elle-même (mêmes fichiers).
                if DocumentAnalysisService.shared.progress?.documentId == id {
                    center.log(job, "Analyse du document lancée : elle lit la suite.")
                    return
                }
                // Lue entre-temps (mise en page IA, vérification) : rien à refaire.
                guard !FileManager.default.fileExists(atPath: file(id, page).path) else { continue }
                let start = Date()
                do {
                    let budget = await budget(id, page, ocr: ocr)
                    let rotation = await ocr.additionalRotation(documentId: id, pageIndex: page)
                    let text = try await Diagnostics.measure("scan IA p. \(page)", "scan") {
                        try await OvisOCR2Reader(language: language)
                            .read(.pdfPage(url: url, index: page, additionalRotation: rotation), maxTokens: budget)
                    }
                    // Arrêtée : texte partiel, jamais gardé.
                    try Task.checkCancellation()
                    try DocumentAITextStore.write(text, documentId: id, reader: ModelSpec.ovisocr2.id, page: page)
                    DocumentAnalysisService.shared.invalidatePage(page, documentId: id)
                    center.log(job, "p. \(page + 1) : \(text.count) caractères, \(Int(Date().timeIntervalSince(start))) s")
                    NotificationCenter.default.post(name: .aiPageRead, object: PageRead(documentId: id, page: page))
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    failures += 1
                    center.log(job, "p. \(page + 1) : erreur — \(error.localizedDescription)")
                    Diagnostics.error("scan IA p. \(page) : \(error.localizedDescription)", "scan")
                    // Arrêt signalé sous une autre forme d'erreur : on s'arrête quand même.
                    try Task.checkCancellation()
                }
            }
            try Task.checkCancellation()
            center.setProgress(job, done: pages.count, total: pages.count)
            center.log(job, failures == 0 ? String(localized: "Terminé.") : String(localized: "Terminé, \(failures) page(s) en erreur (relancées à la prochaine ouverture)."))
        }
    }

    static func file(_ id: String, _ page: Int) -> URL {
        DocumentAnalysisService.rawURL(id, ModelSpec.ovisocr2.id, page)
    }

    /// Longueur de lecture : d'après l'OCR en cache s'il y en a un (un modèle qui boucle ne remplit pas la mémoire).
    private static func budget(_ id: String, _ page: Int, ocr: OCRService) async -> Int {
        for engine in [OCREngineID.ndlocr, OCREngineID.ppocr5, OCREngineID.glmocr, OCREngineID.vision, OCREngineID.pdfText] {
            if let cached = await ocr.cached(documentId: id, pageIndex: page, engine: engine), !cached.lines.isEmpty {
                return DocumentAnalysisService.tokenBudget(cached)
            }
        }
        return 3072
    }
}
