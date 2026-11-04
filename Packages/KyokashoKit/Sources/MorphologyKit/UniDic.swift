// SPDX-License-Identifier: MIT
// Copyright (c) 2026 NOxygen59

import Compression
import Foundation

/// Dictionnaire UniDic pour MeCab, version « lite » (UniDic 2.1.2 réduit par Paul McCann, paquet PyPI
/// `unidic-lite` 1.0.8). Licence UniDic : BSD (choisie parmi GPL / LGPL / BSD). Téléchargé à la demande
/// (≈ 47 Mo), décompressé une fois (≈ 260 Mo, lus en mémoire projetée), l'archive est ensuite effacée.
public enum UniDic {
    public static let archiveURL = URL(string: "https://files.pythonhosted.org/packages/55/2b/8cf7514cb57d028abcef625afa847d60ff1ffbf0049c36b78faa7c35046f/unidic-lite-1.0.8.tar.gz")!
    public static let archiveSHA256 = "db9d4572d9fdd4d00a97949d4b0741ec480ee05a7e7e2e32f547500dae27b245"
    public static let archiveSize: Int64 = 47_356_746
    public static let homepage = URL(string: "https://github.com/polm/unidic-lite")!
    /// Fichiers gardés (le reste de l'archive est ignoré) ; `sys.dic` en dernier : sa présence = installé.
    static let keep = ["BSD", "COPYING", "char.bin", "dicrc", "matrix.bin", "unk.dic", "rewrite.def", "sys.dic"]

    public static func isInstalled(at dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("sys.dic").path)
    }

    public enum Failure: LocalizedError {
        case notGzip, inflate, truncated
        public var errorDescription: String? {
            switch self {
            case .notGzip: return String(localized: "Archive UniDic inattendue (pas un .tar.gz).", bundle: .main)
            case .inflate: return String(localized: "Décompression d'UniDic impossible.", bundle: .main)
            case .truncated: return String(localized: "Archive UniDic incomplète : relance le téléchargement.", bundle: .main)
            }
        }
    }

    /// Décompresse `unidic_lite/dicdir/*` de l'archive dans `dir` (en flux : jamais 260 Mo en mémoire).
    /// Dans un dossier voisin d'abord, mis en place seulement si tout est arrivé (pas de dictionnaire mélangé).
    public static func extract(archive: URL, to dir: URL) throws {
        let fm = FileManager.default
        let staging = dir.deletingLastPathComponent().appendingPathComponent(dir.lastPathComponent + ".part", isDirectory: true)
        try? fm.removeItem(at: staging)
        do {
            try unpack(archive: archive, to: staging)
            try? fm.removeItem(at: dir)
            try fm.moveItem(at: staging, to: dir)
        } catch {
            try? fm.removeItem(at: staging)
            throw error
        }
    }

    private static func unpack(archive: URL, to dir: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let input = try FileHandle(forReadingFrom: archive)
        defer { try? input.close() }
        guard var head = try input.read(upToCount: 1 << 16), head.count > 18, head[0] == 0x1f, head[1] == 0x8b, head[2] == 8 else {
            throw Failure.notGzip
        }
        // En-tête gzip : 10 octets, puis champs optionnels selon les drapeaux.
        let flags = head[3]
        var offset = 10
        func byte(_ i: Int) throws -> UInt8 { guard i < head.count else { throw Failure.notGzip }; return head[i] }
        if flags & 4 != 0 { offset += 2 + Int(try byte(offset)) + Int(try byte(offset + 1)) << 8 }
        if flags & 8 != 0 { while try byte(offset) != 0 { offset += 1 }; offset += 1 }
        if flags & 16 != 0 { while try byte(offset) != 0 { offset += 1 }; offset += 1 }
        if flags & 2 != 0 { offset += 2 }
        guard offset < head.count else { throw Failure.notGzip }
        head = head.subdata(in: offset..<head.count)

        let tar = TarWriter(dir: dir, keep: Set(keep), prefix: "unidic_lite/dicdir/")
        // `sys.dic` écrit sous un nom provisoire : un arrêt en plein milieu ne laisse pas un dictionnaire « installé ».
        defer { tar.closeCurrent() }

        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw Failure.inflate
        }
        defer { compression_stream_destroy(stream) }
        let outSize = 1 << 20
        let out = UnsafeMutablePointer<UInt8>.allocate(capacity: outSize)
        defer { out.deallocate() }
        var chunk: Data? = head
        var finished = false
        while !finished {
            guard let data = chunk else { throw Failure.truncated }
            let last = data.isEmpty
            try data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
                stream.pointee.src_ptr = raw.bindMemory(to: UInt8.self).baseAddress ?? UnsafePointer(out)
                stream.pointee.src_size = data.count
                var produced = 0
                repeat {
                    stream.pointee.dst_ptr = out
                    stream.pointee.dst_size = outSize
                    let status = compression_stream_process(stream, last ? Int32(COMPRESSION_STREAM_FINALIZE.rawValue) : 0)
                    guard status != COMPRESSION_STATUS_ERROR else { throw Failure.inflate }
                    produced = outSize - stream.pointee.dst_size
                    if produced > 0 { try tar.feed(UnsafeBufferPointer(start: out, count: produced)) }
                    if status == COMPRESSION_STATUS_END { finished = true; return }
                    // Dernier appel : le décodeur rend sa réserve en plusieurs fois, jusqu'à ne plus rien produire.
                } while stream.pointee.src_size > 0 || stream.pointee.dst_size == 0 || (last && produced > 0)
            }
            if finished { break }
            // Entrée finie : le décodeur d'Apple ne signale pas toujours la fin (somme gzip derrière le flux) ;
            // l'archive est complète si `sys.dic` a été écrit jusqu'au bout (vérifié plus bas).
            if last { break }
            chunk = try input.read(upToCount: 4 << 20) ?? Data()
        }
        tar.closeCurrent()
        let temp = dir.appendingPathComponent("sys.dic.part")
        guard tar.completed.contains("sys.dic"), FileManager.default.fileExists(atPath: temp.path) else { throw Failure.truncated }
        let final = dir.appendingPathComponent("sys.dic")
        try? FileManager.default.removeItem(at: final)
        try FileManager.default.moveItem(at: temp, to: final)
    }
}

/// Lecteur tar en flux (format ustar) : n'écrit que les fichiers voulus.
private final class TarWriter {
    let dir: URL
    let keep: Set<String>
    let prefix: String
    private var header = Data()
    private var remaining = 0
    private var padding = 0
    private var file: FileHandle?
    private var current: String?
    /// Fichiers voulus écrits en entier.
    private(set) var completed: Set<String> = []

    init(dir: URL, keep: Set<String>, prefix: String) {
        self.dir = dir
        self.keep = keep
        self.prefix = prefix
    }

    func feed(_ bytes: UnsafeBufferPointer<UInt8>) throws {
        var i = 0
        while i < bytes.count {
            if remaining > 0 {
                let n = min(remaining, bytes.count - i)
                if let file { try file.write(contentsOf: UnsafeBufferPointer(rebasing: bytes[i..<(i + n)])) }
                remaining -= n
                i += n
                if remaining == 0 { finishCurrent() }
            } else if padding > 0 {
                let n = min(padding, bytes.count - i)
                padding -= n
                i += n
            } else {
                let n = min(512 - header.count, bytes.count - i)
                header.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[i..<(i + n)]))
                i += n
                if header.count == 512 { try startEntry() }
            }
        }
    }

    private func startEntry() throws {
        defer { header.removeAll(keepingCapacity: true) }
        guard header.contains(where: { $0 != 0 }) else { return }  // blocs vides de fin d'archive
        func text(_ range: Range<Int>) -> String {
            let slice = header[range].prefix { $0 != 0 }
            return String(decoding: slice, as: UTF8.self)
        }
        let name = text(345..<500).isEmpty ? text(0..<100) : text(345..<500) + "/" + text(0..<100)
        let sizeText = text(124..<136).trimmingCharacters(in: .whitespaces)
        let size = Int(sizeText, radix: 8) ?? 0
        remaining = size
        padding = (512 - size % 512) % 512
        if let range = name.range(of: prefix) {
            let base = String(name[range.upperBound...])
            if keep.contains(base), header[156] == UInt8(ascii: "0") || header[156] == 0 {
                let target = dir.appendingPathComponent(base == "sys.dic" ? "sys.dic.part" : base)
                FileManager.default.createFile(atPath: target.path, contents: nil)
                file = try FileHandle(forWritingTo: target)
                current = base
            }
        }
        if remaining == 0 { finishCurrent() }
    }

    private func finishCurrent() {
        if let current, file != nil { completed.insert(current) }
        current = nil
        closeCurrent()
    }

    func closeCurrent() {
        try? file?.close()
        file = nil
    }
}
