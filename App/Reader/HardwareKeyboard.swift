// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Combine
import GameController

/// Clavier physique branché (Magic Keyboard…) : le lecteur affiche alors des flèches pour tourner.
@MainActor
final class HardwareKeyboard: ObservableObject {
    static let shared = HardwareKeyboard()
    @Published private(set) var connected = GCKeyboard.coalesced != nil
    private var observers: [NSObjectProtocol] = []

    private init() {
        for name in [NSNotification.Name.GCKeyboardDidConnect, .GCKeyboardDidDisconnect] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { self.connected = GCKeyboard.coalesced != nil }
            })
        }
    }
}

/// Touche Maj d'un clavier physique, lue par GameController : l'état est connu quel que soit le premier
/// répondeur (la vue web du texte OCR n'a pas forcément le focus clavier). Sert au survol « tant que Maj est
/// appuyée » de la bulle du dictionnaire (Issue #13). Objet séparé de `HardwareKeyboard` pour ne pas redessiner
/// tout le lecteur à chaque appui.
@MainActor
final class ShiftKey: ObservableObject {
    static let shared = ShiftKey()
    @Published private(set) var pressed = false
    private var observers: [NSObjectProtocol] = []

    private init() {
        observers.append(NotificationCenter.default.addObserver(forName: .GCKeyboardDidConnect, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { self.attach() }
        })
        attach()
    }

    private func attach() {
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return }
        input.keyChangedHandler = { [weak self] _, _, code, _ in
            guard code == .leftShift || code == .rightShift else { return }
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    private func refresh() {
        let input = GCKeyboard.coalesced?.keyboardInput
        pressed = input?.button(forKeyCode: .leftShift)?.isPressed == true
            || input?.button(forKeyCode: .rightShift)?.isPressed == true
    }
}
