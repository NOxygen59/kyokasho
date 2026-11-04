// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics

/// Fenêtre d'ouverture de la version Mac : format 10:9 (demande de NOxygen59, 04/11/2026), pour remplacer le 4:3 que
/// Mac Catalyst donne par défaut. Centrée et jamais plus grande que l'écran, y compris sur un petit écran large.
public enum MacWindowFrame {
    public static let aspectRatio: CGFloat = 10.0 / 9.0
    /// Part de l'écran laissée à la fenêtre : elle reste fenêtrée, avec la barre des menus et le Dock visibles.
    static let screenShare: CGFloat = 0.85

    public static func initial(screen: CGRect) -> CGRect {
        let height = min(screen.height, screen.width / aspectRatio) * screenShare
        let width = height * aspectRatio
        return CGRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
    }
}
