// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import CoreGraphics

/// Fenêtre d'ouverture de la version Mac : rectangle 16:10, comme l'écran d'un MacBook (demande de NOxygen59 du
/// 06/11/2026, qui remplace le 10:9 du 04/11 jugé trop carré). Centrée et jamais plus grande que l'écran, y compris sur un petit écran large.
public enum MacWindowFrame {
    public static let aspectRatio: CGFloat = 16.0 / 10.0
    /// Part de l'écran laissée à la fenêtre : elle reste fenêtrée, avec la barre des menus et le Dock visibles.
    static let screenShare: CGFloat = 0.85

    public static func initial(screen: CGRect) -> CGRect {
        let height = min(screen.height, screen.width / aspectRatio) * screenShare
        let width = height * aspectRatio
        return CGRect(x: screen.midX - width / 2, y: screen.midY - height / 2, width: width, height: height)
    }
}
