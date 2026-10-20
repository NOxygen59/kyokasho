// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
// PDF de test (texte original) : swift scripts/make_sample_pdf.swift <sortie.pdf>
// 12 pages A4 avec texte japonais et français, larges marges, une page « scan double » (paysage).
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
var a4 = CGRect(x: 0, y: 0, width: 595, height: 842)
let ctx = CGContext(out as CFURL, mediaBox: &a4, [kCGPDFContextTitle as String: "Cours de test"] as CFDictionary)!

let paragraphs = [
    "インテリアデザインの基礎",
    "空間を計画するときは、まず人の動線を考えます。家具の配置、光の入り方、素材の質感が、部屋の印象を大きく変えます。",
    "第一章：色彩計画。暖色は空間を近く感じさせ、寒色は広く感じさせます。天井を明るい色にすると、部屋が高く見えます。",
    "第二章：照明。全般照明、局部照明、装飾照明を組み合わせて、時間帯や用途に合わせた雰囲気をつくります。",
    "Notes en français : le plan de circulation passe avant le mobilier. Toujours vérifier les dégagements (90 cm minimum).",
]

func draw(_ text: String, in rect: CGRect, size: CGFloat, bold: Bool = false) {
    let font = NSFont(name: bold ? "HiraginoSans-W6" : "HiraginoSans-W3", size: size) ?? .systemFont(ofSize: size)
    let style = NSMutableParagraphStyle(); style.lineSpacing = size * 0.5
    let attr = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: style, .foregroundColor: NSColor.black])
    let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attr), CFRange(), CGPath(rect: rect, transform: nil), nil)
    CTFrameDraw(frame, ctx)
}

for page in 1...12 {
    if page == 7 {
        // Page « scan de double page » : paysage, deux colonnes.
        var wide = CGRect(x: 0, y: 0, width: 1190, height: 842)
        ctx.beginPage(mediaBox: &wide)
        ctx.setFillColor(gray: 0.97, alpha: 1); ctx.fill(wide)
        draw("見開きページ（左）\n" + paragraphs[1], in: CGRect(x: 70, y: 120, width: 460, height: 620), size: 18, bold: false)
        draw("見開きページ（右）\n" + paragraphs[2], in: CGRect(x: 660, y: 120, width: 460, height: 620), size: 18)
        ctx.setStrokeColor(gray: 0.6, alpha: 1); ctx.stroke(CGRect(x: 595, y: 40, width: 0.5, height: 762))
        ctx.endPage()
        continue
    }
    ctx.beginPage(mediaBox: &a4)
    ctx.setFillColor(gray: 1, alpha: 1); ctx.fill(a4)
    // Grande marge blanche (pour tester le rognage) : texte seulement au centre.
    draw("第\(page)回　" + paragraphs[0], in: CGRect(x: 110, y: 640, width: 375, height: 80), size: 22, bold: true)
    let body = paragraphs[1 + (page % 4)] + "\n\n" + paragraphs[1 + ((page + 1) % 4)]
    draw(body, in: CGRect(x: 110, y: 200, width: 375, height: 420), size: 15)
    draw("— \(page) —", in: CGRect(x: 270, y: 150, width: 100, height: 30), size: 11)
    ctx.endPage()
}
ctx.closePDF()
print(out.path)
