// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import OCRKit
import SwiftUI

/// Même choix de langue dans les réglages du livre et avant son analyse complète.
struct DocumentLanguagePicker: View {
    let documentId: String
    @State private var language: OCRTargetLanguage = .japanese

    var body: some View {
        Picker("Langue ciblée", selection: $language) {
            ForEach(OCRTargetLanguage.allCases, id: \.self) { choice in
                Text(choice.title).tag(choice)
            }
        }
        .disabled(AITaskCenter.shared.isRunning(DocumentScan.key(documentId))
                  || DocumentAnalysisService.shared.progress?.documentId == documentId)
        .onAppear { language = OCRTargetLanguage.forDocument(documentId) }
        .onChange(of: language) { OCRTargetLanguage.set($0, forDocument: documentId) }
    }
}
