// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import SwiftUI
import UIKit

/// ←/→ du clavier physique : page précédente / suivante selon le sens de lecture (RET-050, Issue #81).
///
/// Les anciens `.keyboardShortcut` des boutons-flèches passaient **après** le système de focus clavier d'iPadOS :
/// les flèches déplaçaient le focus vers les champs de saisie (numéro de page, recherche, note) au lieu de tourner.
/// Ici, deux `UIKeyCommand` avec `wantsPriorityOverSystemBehavior` (iOS 15+) sont ajoutées au contrôleur racine de
/// la fenêtre du lecteur, donc présentes dans la chaîne de répondeurs quel que soit l'élément actif ; leur action
/// remonte jusqu'à `UIApplication` (extension plus bas).
///
/// Elles sont **retirées** pendant une saisie réelle (`UITextField` / `UITextView` en édition) et tant que le
/// navigateur est ouvert (les pages web ont leurs propres champs) : les flèches y déplacent alors le curseur.
/// En mode dessin, la toile PencilKit n'est pas une saisie : ←/→ tournent la page (décision de NOxygen59, 28/10).
///
/// ↑/↓ sont aussi captées, sans action : sinon le focus clavier d'iPadOS les utilisait pour entrer dans la bulle du
/// numéro de page, qui passait en saisie, et ←/→ ne tournaient plus les pages (recette du 28/10, RET-052).
@MainActor
final class ReaderArrowKeys {
    static let shared = ReaderArrowKeys()

    /// Lecteur affiché ; `nil` hors lecteur.
    private weak var reader: ReaderController?
    private weak var host: UIViewController?
    /// Champ en cours d'édition (notification de début d'édition), `nil` sinon.
    private weak var editingField: AnyObject?
    var webOpen = false { didSet { if webOpen != oldValue { refresh() } } }
    private var installed = false
    private var observers: [NSObjectProtocol] = []

    private let commands: [UIKeyCommand] = [
        (UIKeyCommand.inputLeftArrow, #selector(UIApplication.kyokashoArrowLeft(_:))),
        (UIKeyCommand.inputRightArrow, #selector(UIApplication.kyokashoArrowRight(_:))),
        (UIKeyCommand.inputUpArrow, #selector(UIApplication.kyokashoArrowIgnored(_:))),
        (UIKeyCommand.inputDownArrow, #selector(UIApplication.kyokashoArrowIgnored(_:))),
    ].map { input, action in
        let command = UIKeyCommand(input: input, modifierFlags: [], action: action)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }

    private init() {
        let center = NotificationCenter.default
        let begin = [UITextField.textDidBeginEditingNotification, UITextView.textDidBeginEditingNotification]
        let end = [UITextField.textDidEndEditingNotification, UITextView.textDidEndEditingNotification]
        for name in begin {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { Self.shared.editingChanged(note.object as AnyObject?, editing: true) }
            })
        }
        for name in end {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                MainActor.assumeIsolated { Self.shared.editingChanged(note.object as AnyObject?, editing: false) }
            })
        }
    }

    /// Le lecteur apparaît dans une fenêtre : les commandes vont sur son contrôleur racine.
    func attach(reader: ReaderController, window: UIWindow) {
        self.reader = reader
        if host !== window.rootViewController { remove() }
        host = window.rootViewController
        refresh()
    }

    /// Le lecteur disparaît : plus aucune commande.
    func detach(reader: ReaderController) {
        guard self.reader === reader else { return }
        remove()
        self.reader = nil
        host = nil
    }

    private func editingChanged(_ field: AnyObject?, editing: Bool) {
        if editing {
            editingField = field
        } else if editingField === field || editingField == nil {
            editingField = nil
        }
        Diagnostics.log("Saisie \(editing ? "commencée" : "terminée") (\(field.map { String(describing: type(of: $0)) } ?? "?")) : "
                        + "flèches \(editing ? "rendues au champ" : "pour les pages")", "clavier")
        refresh()
    }

    private func refresh() {
        let active = reader != nil && host != nil && editingField == nil && !webOpen
        if active && !installed, let host {
            commands.forEach(host.addKeyCommand)
            installed = true
            Diagnostics.log("Flèches clavier actives sur \(String(describing: type(of: host)))", "clavier")
        } else if !active && installed {
            remove()
            Diagnostics.log("Flèches clavier retirées (\(editingField != nil ? "saisie" : webOpen ? "navigateur" : "lecteur fermé"))", "clavier")
        }
    }

    private func remove() {
        if installed, let host { commands.forEach(host.removeKeyCommand) }
        installed = false
    }

    /// ← (`towardLeft`) ou → : même sens que les boutons-flèches à l'écran (`ReaderScreen.pageArrow`) ; en lecture de
    /// droite à gauche, ← avance.
    fileprivate func turn(towardLeft: Bool) {
        guard let reader else { return }
        let forward = reader.settings.direction == .rightToLeft ? towardLeft : !towardLeft
        Diagnostics.log("Flèche \(towardLeft ? "←" : "→") : page \(forward ? "suivante" : "précédente") ; "
                        + "premier répondeur = \(FirstResponder.name())", "clavier")
        forward ? reader.next() : reader.previous()
    }
}

/// Cible des commandes : `UIApplication` termine la chaîne de répondeurs, elle reçoit l'action quel que soit
/// l'élément actif (aucun autre répondeur n'implémente ces sélecteurs).
extension UIApplication {
    @objc func kyokashoArrowLeft(_ sender: UIKeyCommand) {
        MainActor.assumeIsolated { ReaderArrowKeys.shared.turn(towardLeft: true) }
    }

    @objc func kyokashoArrowRight(_ sender: UIKeyCommand) {
        MainActor.assumeIsolated { ReaderArrowKeys.shared.turn(towardLeft: false) }
    }

    /// ↑/↓ : rien, volontairement (voir `ReaderArrowKeys`) ; seulement pour que le focus clavier ne les reçoive pas.
    @objc func kyokashoArrowIgnored(_ sender: UIKeyCommand) {
        MainActor.assumeIsolated { Diagnostics.log("Flèche ↑/↓ ignorée (lecteur)", "clavier") }
    }
}

/// Nom du premier répondeur, pour le journal de diagnostic seulement.
@MainActor
private enum FirstResponder {
    static weak var found: UIResponder?

    static func name() -> String {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.kyokashoReportFirstResponder(_:)), to: nil, from: nil, for: nil)
        return found.map { String(describing: type(of: $0)) } ?? "aucun"
    }
}

extension UIResponder {
    @objc fileprivate func kyokashoReportFirstResponder(_ sender: Any?) {
        MainActor.assumeIsolated { FirstResponder.found = self }
    }
}

/// Vue invisible du lecteur : donne sa fenêtre à `ReaderArrowKeys` et retire les commandes à la fermeture.
struct ReaderArrowKeysHost: UIViewRepresentable {
    let reader: ReaderController

    func makeUIView(context: Context) -> HostView {
        let view = HostView()
        view.reader = reader
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: HostView, context: Context) { view.reader = reader }

    static func dismantleUIView(_ view: HostView, coordinator: ()) {
        if let reader = view.reader { ReaderArrowKeys.shared.detach(reader: reader) }
    }

    final class HostView: UIView {
        weak var reader: ReaderController?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard let reader else { return }
            if let window { ReaderArrowKeys.shared.attach(reader: reader, window: window) }
            else { ReaderArrowKeys.shared.detach(reader: reader) }
        }
    }
}
