// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59
// Transforme un PDF en « scan » (pages = images, aucun texte intégré), pour tester l'OCR :
//   swift scripts/make_scan_pdf.swift entree.pdf sortie.pdf
import CoreGraphics
import Foundation

let input = CGPDFDocument(URL(fileURLWithPath: CommandLine.arguments[1]) as CFURL)!
let output = URL(fileURLWithPath: CommandLine.arguments[2])
var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
let pdf = CGContext(output as CFURL, mediaBox: &mediaBox, nil)!
for i in 1...input.numberOfPages {
    let page = input.page(at: i)!
    var box = page.getBoxRect(.mediaBox)
    let scale: CGFloat = 200.0 / 72.0 // 200 dpi
    let w = Int(box.width * scale), h = Int(box.height * scale)
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    ctx.setFillColor(gray: 0.98, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
    ctx.scaleBy(x: scale, y: scale)
    ctx.rotate(by: 0.004) // léger biais, comme un vrai scan
    ctx.drawPDFPage(page)
    let image = ctx.makeImage()!
    pdf.beginPage(mediaBox: &box)
    pdf.draw(image, in: box)
    pdf.endPage()
}
pdf.closePDF()
print(output.path)
