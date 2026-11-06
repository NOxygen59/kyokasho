// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI

// Mac Catalyst : une feuille ouverte depuis une feuille (les Réglages) les fermait toutes les deux (essais de NOxygen59
// du 30/10 et du 06/11/2026 : journal, batterie, lectures OvisOCR2, nouveautés). Sur Mac, ces écrans deviennent des
// pages de la navigation où ils sont ouverts ; sur l'iPad, rien ne change.

private struct PushedPageKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Vrai dans un écran poussé à la place d'une feuille : la navigation existante suffit.
    var pushedPage: Bool {
        get { self[PushedPageKey.self] }
        set { self[PushedPageKey.self] = newValue }
    }
}

/// `NavigationStack`, sauf dans une page poussée à la place d'une feuille (pas de pile dans la pile).
struct SheetStack<Content: View>: View {
    @Environment(\.pushedPage) private var pushed
    @ViewBuilder var content: () -> Content

    var body: some View {
        if pushed { content() } else { NavigationStack { content() } }
    }
}

extension View {
    /// Feuille sur l'iPad ; page poussée dans la navigation sur Mac. À poser hors d'une liste (pas sur une `Section`).
    func stackedSheet<Page: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                                  @ViewBuilder content: @escaping () -> Page) -> some View {
        modifier(StackedSheetModifier(isPresented: isPresented, onDismiss: onDismiss, page: content))
    }

    func stackedSheet<Item: Identifiable, Page: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                      @ViewBuilder content: @escaping (Item) -> Page) -> some View {
        stackedSheet(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
                     onDismiss: onDismiss) {
            if let value = item.wrappedValue { content(value) }
        }
    }
}

private struct StackedSheetModifier<Page: View>: ViewModifier {
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    @ViewBuilder let page: () -> Page

    func body(content: Content) -> some View {
        #if targetEnvironment(macCatalyst)
        content
            .navigationDestination(isPresented: $isPresented) { page().environment(\.pushedPage, true) }
            .onChange(of: isPresented) { if !$0 { onDismiss?() } }
        #else
        content.sheet(isPresented: $isPresented, onDismiss: onDismiss, content: page)
        #endif
    }
}
