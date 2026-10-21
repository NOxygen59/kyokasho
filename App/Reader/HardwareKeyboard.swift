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
