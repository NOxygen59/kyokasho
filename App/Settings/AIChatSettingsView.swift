// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import GLMOCRKit
import OCRKit
import ReaderCore
import SwiftUI

/// Réglages du chat gardés par modèle dans les préférences (`ai.chat.<modèle>`, donc dans la sauvegarde).
enum AIChatSettingsStore {
    static let models: [ModelSpec] = [.qwen3vl4b, .qwen35chat4b]

    private static func key(_ modelID: String) -> String { "ai.chat.\(modelID)" }

    static func load(_ modelID: String) -> AIChatSettings {
        guard let data = UserDefaults.standard.data(forKey: key(modelID)),
              let settings = try? JSONDecoder().decode(AIChatSettings.self, from: data) else { return AIChatSettings() }
        return settings
    }

    static func save(_ settings: AIChatSettings, for modelID: String) {
        if settings == AIChatSettings() {
            UserDefaults.standard.removeObject(forKey: key(modelID))
        } else if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: key(modelID))
        }
    }

    static func name(_ modelID: String) -> String { modelID == ModelSpec.qwen35chat4b.id ? "Qwen3.5 4B" : "Qwen3-VL 4B" }
}

/// Consigne générale et paramètres de chaque modèle de chat (#37, #45), à la manière de Locally : tout est modifiable,
/// chaque réglage est expliqué, et « Revenir aux réglages de l'app » remet le comportement d'origine.
struct AIChatSettingsView: View {
    @State var modelID: String = ModelSpec.qwen3vl4b.id
    /// Modèle imposé (ouvert depuis un chat) : pas de sélecteur.
    var fixedModel = false
    @State private var settings = AIChatSettings()
    @State private var draft = ""

    var body: some View {
        Form {
            if !fixedModel {
                Picker("Modèle", selection: $modelID) {
                    ForEach(AIChatSettingsStore.models, id: \.id) { Text(AIChatSettingsStore.name($0.id)).tag($0.id) }
                }
            }
            Section {
                Menu {
                    ForEach(AIChatPreset.allCases) { preset in
                        Button { settings = preset.applied(to: settings); draft = settings.instructions ?? "" } label: {
                            Text(preset.title)
                        }
                    }
                } label: { Label("Choisir un préréglage", systemImage: "wand.and.stars") }
                ForEach(AIChatPreset.allCases) { preset in
                    Text("**\(preset.title)** : \(preset.summary)").font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Préréglages")
            } footer: {
                Text("Un préréglage remplit la consigne et règle la température et la longueur ; tout reste modifiable ensuite.")
            }
            Section {
                TextEditor(text: $draft)
                    .frame(minHeight: 140)
                    .font(Atelier.font(14))
                    .onChange(of: draft) { settings.instructions = $0 }
                if settings.instructions == nil {
                    Text("Consigne de l'app (vide ci-dessus) :\n\(QwenChat.instructions)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Consigne générale (prompt système)")
            } footer: {
                Text("Ce que le modèle doit être et faire à chaque réponse : rôle, langue, format, limites. Laisse vide pour la consigne de l'app. Dans un livre, les extraits des pages et la règle « ne rien inventer » sont toujours ajoutés.")
            }
            Section {
                Toggle("Température automatique", isOn: Binding(
                    get: { settings.temperature == nil },
                    set: { settings.temperature = $0 ? nil : settings.effectiveTemperature(grounded: false) }))
                if let t = settings.temperature {
                    slider("Température", value: Binding(get: { t }, set: { settings.temperature = $0 }),
                           range: AIChatSettings.temperatureRange, format: "%.2f")
                }
                Text("Créativité. 0 : toujours la réponse la plus probable (fiable, répétitive) ; 0,7 et plus : plus varié mais plus d'erreurs. Automatique : 0 sur un livre, 0,3 en discussion libre.")
                    .font(.caption).foregroundStyle(.secondary)
                slider("Top-p", value: $settings.topP, range: AIChatSettings.topPRange, format: "%.2f")
                Text("Ne garde que les mots les plus probables dont la somme atteint cette part. 1 : aucun filtre ; 0,9 : écarte les choix improbables.")
                    .font(.caption).foregroundStyle(.secondary)
                Stepper("Top-k : \(settings.topK == 0 ? "sans limite" : "\(settings.topK)")", value: $settings.topK,
                        in: AIChatSettings.topKRange, step: 10)
                Text("Nombre de mots candidats à chaque pas. 0 : sans limite ; 40 : réponses plus sages.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Génération")
            }
            Section {
                Stepper("Longueur maximale : \(settings.maxTokens) jetons", value: $settings.maxTokens,
                        in: AIChatSettings.maxTokensRange, step: 128)
                Text("Environ 1 jeton = 1 caractère japonais ou ¾ de mot français. Plus long = plus de mémoire et de batterie ; au-delà de 2 048, risque de manque de mémoire sur l'iPad.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Pénalité de répétition", isOn: Binding(
                    get: { settings.repetitionPenalty != nil },
                    set: { settings.repetitionPenalty = $0 ? 1.1 : nil }))
                if let r = settings.repetitionPenalty {
                    slider("Force", value: Binding(get: { r }, set: { settings.repetitionPenalty = $0 }),
                           range: AIChatSettings.repetitionRange, format: "%.2f")
                }
                Text("Évite qu'il boucle sur la même phrase. 1,1 suffit en général ; trop fort, il évite aussi les mots utiles.")
                    .font(.caption).foregroundStyle(.secondary)
                if modelID == ModelSpec.qwen35chat4b.id {
                    Toggle("Réflexion avant de répondre", isOn: $settings.thinking)
                    Text("Qwen3.5 réfléchit d'abord (la réflexion s'affiche dans la réponse). Souvent plus juste en maths, mais 2 à 5 fois plus long.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } header: {
                Text("Longueur et répétitions")
            }
            Section {
                Button("Revenir aux réglages de l'app", role: .destructive) { settings = AIChatSettings(); draft = "" }
                    .disabled(settings == AIChatSettings())
            } footer: {
                Text("Appliqué à la prochaine conversation ou au prochain chargement du modèle. Tout reste sur l'iPad.")
            }
        }
        .navigationTitle("Chat \(AIChatSettingsStore.name(modelID))")
        .onAppear(perform: load)
        .onChange(of: modelID) { _ in load() }
        .onChange(of: settings) { AIChatSettingsStore.save($0, for: modelID) }
    }

    private func load() {
        settings = AIChatSettingsStore.load(modelID)
        draft = settings.instructions ?? ""
    }

    private func slider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(title); Spacer(); Text(String(format: format, value.wrappedValue)).monospacedDigit().foregroundStyle(.secondary) }
            Slider(value: value, in: range)
        }
    }
}
