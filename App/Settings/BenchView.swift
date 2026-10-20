// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import PhotosUI
import ReaderCore
import SwiftUI
import UniformTypeIdentifiers

/// Banc d'essai OCR : des images avec leur texte de référence ; chaque moteur est mesuré
/// (taux d'erreur de caractères, temps). Sert à choisir le moteur (V5 : NDLOCR-Lite, PP-OCR).
struct BenchView: View {
    @EnvironmentObject private var model: AppModel
    @State private var samples: [BenchSample] = []
    @State private var runs: [BenchRun] = []
    @State private var photo: PhotosPickerItem?
    @State private var showFiles = false
    @State private var running: (done: Int, total: Int)?
    @State private var editing: BenchSample?

    /// Moteurs qui lisent une image (le texte intégré au PDF n'a pas de sens ici).
    private let engines: [any OCREngine] = [VisionOCREngine()]

    var body: some View {
        List {
            Section("Résultats") {
                if runs.isEmpty {
                    Text("Ajoute des images puis lance le test.").foregroundStyle(.secondary)
                }
                ForEach(engines, id: \.id) { engine in
                    let mine = runs.filter { $0.engine == engine.id }
                    if !mine.isEmpty {
                        let cer = mine.map(\.cer).reduce(0, +) / Double(mine.count)
                        let time = mine.map(\.durationMs).reduce(0, +) / mine.count
                        LabeledContent(OCREngineID.displayName(engine.id),
                                       value: "erreur \(percent(cer)) · \(time) ms · \(mine.count) image(s)")
                    }
                }
                Button {
                    runAll()
                } label: {
                    if let running {
                        HStack { ProgressView(); Text("Test \(running.done)/\(running.total)…") }
                    } else {
                        Label("Lancer le test", systemImage: "play.fill")
                    }
                }
                .disabled(samples.isEmpty || running != nil)
            }
            Section {
                ForEach(samples) { sample in
                    Button { editing = sample } label: { row(sample) }.buttonStyle(.plain)
                }
                .onDelete(perform: delete)
                PhotosPicker(selection: $photo, matching: .images) { Label("Ajouter depuis Photos", systemImage: "photo") }
                Button { showFiles = true } label: { Label("Ajouter depuis Fichiers", systemImage: "folder") }
            } header: {
                Text("Images (\(samples.count))")
            } footer: {
                Text("Tu peux aussi ajouter une page depuis le lecteur : bouton « Texte » → icône jauge. Corrige ensuite le texte de référence.")
            }
        }
        .navigationTitle("Banc d'essai")
        .onAppear(perform: reload)
        .onChange(of: photo) { item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) { addImage(data, title: "Photo") }
                photo = nil
            }
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                if let data = try? Data(contentsOf: url) { addImage(data, title: url.deletingPathExtension().lastPathComponent) }
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
        }
        .sheet(item: $editing, onDismiss: reload) { sample in
            BenchSampleEditor(sample: sample).environmentObject(model).environmentObject(model.dictionary)
        }
    }

    private func row(_ sample: BenchSample) -> some View {
        HStack(spacing: 12) {
            BenchThumbnail(url: model.benchDirectory.appendingPathComponent(sample.imageFile))
                .frame(width: 56, height: 72)
            VStack(alignment: .leading, spacing: 4) {
                Text(sample.title).lineLimit(1)
                if sample.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Texte de référence manquant").font(.caption).foregroundStyle(.orange)
                }
                ForEach(runs.filter { $0.sampleId == sample.id }) { run in
                    Text("\(OCREngineID.displayName(run.engine)) : erreur \(percent(run.cer)) · \(run.durationMs) ms")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func percent(_ v: Double) -> String { String(format: "%.1f %%", v * 100) }

    private func reload() {
        samples = (try? model.database.benchSamples()) ?? []
        runs = (try? model.database.latestBenchRuns()) ?? []
    }

    private func addImage(_ data: Data, title: String) {
        // Normalisé en PNG (HEIC, JPEG… acceptés en entrée).
        guard let image = UIImage(data: data), let png = image.pngData() else { return }
        let file = UUID().uuidString + ".png"
        do {
            try png.write(to: model.benchDirectory.appendingPathComponent(file))
            let sample = BenchSample(title: title, imageFile: file, referenceText: "")
            try model.database.save(sample)
            reload()
            editing = sample
        } catch {
            model.lastError = error.localizedDescription
        }
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets {
            let sample = samples[i]
            try? FileManager.default.removeItem(at: model.benchDirectory.appendingPathComponent(sample.imageFile))
            try? model.database.deleteBenchSample(id: sample.id)
        }
        reload()
    }

    private func runAll() {
        let todo = samples.filter { !$0.referenceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !todo.isEmpty else {
            model.lastError = "Ajoute d'abord le texte de référence des images."
            return
        }
        running = (0, todo.count * engines.count)
        let directory = model.benchDirectory
        let database = model.database
        let engines = engines
        Task.detached(priority: .userInitiated) {
            var done = 0
            for sample in todo {
                guard let cg = UIImage(contentsOfFile: directory.appendingPathComponent(sample.imageFile).path)?.cgImage else { continue }
                for engine in engines {
                    if let page = try? await engine.recognize(.image(cg)) {
                        let cer = CharacterErrorRate.cer(reference: sample.referenceText, hypothesis: page.text)
                        try? database.save(BenchRun(sampleId: sample.id, engine: engine.id, cer: cer,
                                                    durationMs: page.durationMs, text: page.text))
                    }
                    done += 1
                    let progress = done
                    await MainActor.run { running = (progress, todo.count * engines.count) }
                }
            }
            await MainActor.run {
                running = nil
                reload()
            }
        }
    }
}

struct BenchSampleEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var sample: BenchSample
    @State private var runs: [BenchRun] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Titre") { TextField("Titre", text: $sample.title) }
                Section("Image") {
                    BenchThumbnail(url: model.benchDirectory.appendingPathComponent(sample.imageFile)).frame(height: 260)
                }
                Section {
                    TextEditor(text: $sample.referenceText).frame(minHeight: 160).font(.body)
                } header: {
                    Text("Texte de référence")
                } footer: {
                    Text("Le texte exact de l'image. Espaces et retours à la ligne ne comptent pas dans l'erreur.")
                }
                if !runs.isEmpty {
                    Section("Derniers essais") {
                        ForEach(runs) { run in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(OCREngineID.displayName(run.engine)) — erreur \(String(format: "%.1f %%", run.cer * 100)) · \(run.durationMs) ms")
                                    .font(.subheadline.bold())
                                Text(run.text).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Échantillon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") {
                        try? model.database.save(sample)
                        dismiss()
                    }
                }
            }
            .onAppear { runs = (try? model.database.benchRuns(sampleId: sample.id)) ?? [] }
        }
    }
}

struct BenchThumbnail: View {
    let url: URL
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(Color(white: 0.15))
            if let image { Image(uiImage: image).resizable().scaledToFit() }
        }
        .task(id: url) {
            let url = url
            image = await Task.detached { UIImage(contentsOfFile: url.path)?.preparingThumbnail(of: CGSize(width: 600, height: 600)) }.value
        }
    }
}
