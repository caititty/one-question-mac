import Foundation
import PDFKit
import Vision
import CoreGraphics

/// Extracts locally. The original file is never sent to an AI service.
public enum PDFQuestionImporter {
    public static func load(url: URL, progress: (@Sendable (String) -> Void)? = nil) throws -> ImportDocument {
        guard let document = PDFDocument(url: url) else { throw AppFailure("无法打开 PDF，请检查文件是否完整。") }
        guard !document.isLocked else { throw AppFailure("PDF 已加密，请先用密码解锁并另存为可读取的文件。") }
        guard document.allowsCopying else { throw AppFailure("该 PDF 限制内容提取，请使用允许复制文字的版本。") }
        guard (1...200).contains(document.pageCount) else { throw AppFailure("PDF 需包含 1–200 页，请将较大的题库拆分后导入。") }
        var pages: [(number: Int, text: String)] = []
        var ocrPages = 0, failedPages: [Int] = [], totalCharacters = 0
        var lastOCRError: String?
        for index in 0..<document.pageCount {
            try Task.checkCancellation()
            let extracted: String = autoreleasepool {
                guard let page = document.page(at: index) else { failedPages.append(index + 1); return "" }
                let native = page.string?.trimmed ?? ""
                if native.unicodeScalars.filter({ CharacterSet.alphanumerics.contains($0) }).count >= 40 {
                    progress?("正在提取 PDF，第 \(index + 1) / \(document.pageCount) 页")
                    return native
                }
                progress?("正在本地识别扫描文字，第 \(index + 1) / \(document.pageCount) 页")
                do {
                    let recognized = try recognize(page)
                    if recognized.count > native.count { ocrPages += 1; return recognized }
                    return native
                } catch {
                    lastOCRError = error.localizedDescription
                    if native.isEmpty { failedPages.append(index + 1) }
                    return native
                }
            }
            try Task.checkCancellation()
            totalCharacters += extracted.count
            guard totalCharacters <= 2_000_000 else { throw AppFailure("PDF 提取文字过多，请拆分题库后重试。") }
            pages.append((index + 1, extracted))
        }
        let repeated = repeatedMargins(pages.map(\.text))
        let source = pages.map { page in
            let body = page.text.components(separatedBy: .newlines).filter { !repeated.contains($0.trimmed) }.joined(separator: "\n")
            return "【PDF第\(page.number)页】\n\(body)"
        }.joined(separator: "\n\n")
        guard pages.contains(where: { !$0.text.trimmed.isEmpty }) else {
            if let lastOCRError { throw AppFailure("本机 PDF 文字识别失败：\(lastOCRError)") }
            throw AppFailure("未能从 PDF 中识别出文字。请使用更清晰的扫描件或文字版 PDF。")
        }
        var result = try parse(text: source, name: url.deletingPathExtension().lastPathComponent)
        var notes = ["已读取 \(document.pageCount) 页，其中 \(ocrPages) 页使用本地 OCR。请检查拆题和答案。"]
        if !failedPages.isEmpty { notes.append("第 \(failedPages.map(String.init).joined(separator: "、")) 页未能完整提取，请核对原文。") }
        if result.rows.isEmpty { notes.append("未识别到清晰的题目分段，可点“调整提取文字”添加“题目：”标记。") }
        result.notice = notes.joined(separator: " ")
        return result
    }

    private static func recognize(_ page: PDFPage) throws -> String {
        guard let pdf = page.pageRef else { throw AppFailure("无法渲染 PDF 页面。") }
        let bounds = pdf.getBoxRect(.mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return "" }
        let scale = 2200 / max(bounds.width, bounds.height)
        let width = max(1, Int(bounds.width * scale)), height = max(1, Int(bounds.height * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw AppFailure("无法创建 PDF 识别图像。") }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect)
        context.concatenate(pdf.getDrawingTransform(.mediaBox, rect: rect, rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(pdf)
        guard let image = context.makeImage() else { throw AppFailure("PDF 页面渲染失败。") }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.automaticallyDetectsLanguage = true
        request.usesLanguageCorrection = true
        request.usesCPUOnly = true
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).sorted { lhs, rhs in
            if abs(lhs.boundingBox.midY - rhs.boundingBox.midY) < 0.008 { return lhs.boundingBox.minX < rhs.boundingBox.minX }
            return lhs.boundingBox.midY > rhs.boundingBox.midY
        }.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// Supports numbered questions, 题目/答案 markers, Q/A and unnumbered questions.
    /// Ambiguous documents remain editable in the preview, without inventing answers.
    public static func parse(text: String, name: String) throws -> ImportDocument {
        guard text.count <= 2_000_000 else { throw AppFailure("提取文字过多，请拆分题库。") }
        var rows: [ImportRow] = []
        var title: [String] = [], answer: [String] = [], points: [String] = []
        var mode = Section.question, page: Int?, firstPage: Int?, lastPage: Int?
        var firstLine = 1, inCode = false
        var mainNumbering = "", pendingSubquestion: String?
        func flush() {
            let heading = title.joined(separator: "\n").trimmed
            guard !heading.isEmpty else { title = []; answer = []; points = []; return }
            let reference = answer.joined(separator: "\n").trimmed
            let criteria = points.filter { !$0.trimmed.isEmpty }.prefix(50).map { point -> Criterion in
                let cleaned = point.replacingOccurrences(of: #"^\s*[-•●]\s*"#, with: "", options: .regularExpression).trimmed
                if let captures = captures(#"^(.+?)[（(]\s*([0-9]{1,3})\s*分[）)]\s*$"#, in: cleaned),
                   let weight = Int(captures[1]), (1...100).contains(weight) {
                    return Criterion(text: captures[0].trimmed, weight: weight)
                }
                return Criterion(text: cleaned)
            }
            var warning = "PDF 识别结果，请核对"
            if reference.isEmpty { warning += "；缺少参考答案，暂不支持自动评价" }
            let source: String?
            if let firstPage { source = firstPage == lastPage ? "第 \(firstPage) 页" : "第 \(firstPage)–\(lastPage ?? firstPage) 页" }
            else { source = nil }
            if heading.count > 10_000 {
                rows.append(ImportRow(line: firstLine, question: nil, issue: "题目内容过长，请在提取文字中修正分段。", source: source))
            } else {
                let q = Question(title: heading, referenceAnswer: reference, criteria: Array(criteria), deck: name,
                                 category: "PDF 导入", tags: ["PDF"], source: name + ".pdf" + (source.map { " · " + $0 } ?? ""))
                rows.append(ImportRow(line: firstLine, question: q, warning: warning, source: source))
            }
            title = []; answer = []; points = []; mode = .question; pendingSubquestion = nil
        }
        func start(_ heading: String, line: Int, numbering: String = "explicit") {
            flush(); title = heading.isEmpty ? [] : [heading]; mode = .question
            firstLine = line; firstPage = page; lastPage = page
            mainNumbering = numbering
        }
        // Keep a pending empty 题目: marker so its following line becomes the title.
        var pendingQuestion = false
        for (offset, raw) in text.components(separatedBy: .newlines).enumerated() {
            try Task.checkCancellation()
            let line = raw.trimmed
            if let match = captures(#"^【PDF第([0-9]+)页】$"#, in: line), let number = Int(match[0]) { page = number; continue }
            if !inCode, line.range(of: #"^第\s*[0-9]+\s*页$"#, options: .regularExpression) != nil { continue }
            if line.hasPrefix("```") { inCode.toggle() }
            if !inCode {
                if let heading = captures(#"^(?:题目|问题|问|Question|Q)\s*(?:[0-9]+)?\s*[:：]\s*(.*)$"#, in: line)?.first {
                    start(heading, line: offset + 1); pendingQuestion = heading.isEmpty; continue
                }
                if let heading = captures(#"^第[0-9一二三四五六七八九十百]+题\s*[:：.、]?\s*(.*)$"#, in: line)?.first {
                    start(heading, line: offset + 1, numbering: "parent"); pendingQuestion = heading.isEmpty; continue
                }
                let nested = captures(#"^([（(][0-9]{1,4}[)）]|[0-9]+\.[0-9]+(?:[.、)）])?|[①-⑳])\s*(.+)$"#, in: line)
                if let nested, !title.isEmpty, mainNumbering != "parenthesized",
                   mode == .question || looksLikeQuestion(nested[1]) {
                    title.append(line); mode = .question; pendingSubquestion = nested[0]; lastPage = page; continue
                }
                let numbered = captures(#"^(?:[0-9]{1,4}\s*[.、)）](?![0-9])\s*|[（(][0-9]{1,4}[)）]\s*|[一二三四五六七八九十]{1,3}[、.]\s*|Q[0-9]+\s*[:：.、]\s*)(.+)$"#, in: line)?.first
                if let heading = numbered, mode == .question || looksLikeQuestion(heading) {
                    if !title.isEmpty, mainNumbering == "parent" {
                        title.append(line); mode = .question
                        pendingSubquestion = captures(#"^([0-9]{1,4}\s*[.、)）]|[一二三四五六七八九十]{1,3}[、.]|Q[0-9]+\s*[:：.、])"#, in: line)?.first
                        lastPage = page; continue
                    }
                    let numbering = line.hasPrefix("(") || line.hasPrefix("（") ? "parenthesized" : "numbered"
                    start(heading, line: offset + 1, numbering: numbering); pendingQuestion = false; continue
                }
                if let content = field(["参考答案", "标准答案", "答案", "解答", "解析", "答", "Answer", "A"], line: line), !title.isEmpty {
                    mode = .answer
                    if let prefix = pendingSubquestion {
                        answer.append(prefix + (content.isEmpty ? "" : " " + content)); pendingSubquestion = nil
                    } else if !content.isEmpty { answer.append(content) }
                    lastPage = page; continue
                }
                if let content = field(["评分要点", "得分点", "要点", "Key points"], line: line), !title.isEmpty {
                    mode = .criteria; if !content.isEmpty { points.append(content) }; lastPage = page; continue
                }
                if title.isEmpty, pendingQuestion, !line.isEmpty { title.append(line); pendingQuestion = false; lastPage = page; continue }
                if title.isEmpty, looksLikeQuestion(line), line.hasSuffix("？") || line.hasSuffix("?") {
                    start(line, line: offset + 1, numbering: "unnumbered"); continue
                }
            }
            guard !title.isEmpty else { continue }
            if !line.isEmpty { lastPage = page }
            switch mode {
            case .question: if !line.isEmpty { title.append(line) }
            case .answer: answer.append(raw)
            case .criteria: if !line.isEmpty { points.append(line) }
            }
        }
        flush()
        guard rows.count <= 20_000 else { throw AppFailure("每次最多导入 20000 道题。") }
        return ImportDocument(name: name, rows: rows,
            notice: rows.isEmpty ? "未找到清晰的题目分段，请添加“题目：”和“答案：”标记后重新识别。" : "PDF 自动拆题结果，请逐题核对后确认导入。",
            sourceText: text)
    }
    private enum Section { case question, answer, criteria }
    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
    private static func field(_ names: [String], line: String) -> String? {
        let names = names.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        return captures("^(?:【(?:\(names))】\\s*|(?:\(names))\\s*[:：]\\s*)(.*)$", in: line)?.first
            ?? captures("^(?:\(names))\\s*$", in: line).map { _ in "" }
    }
    private static func looksLikeQuestion(_ line: String) -> Bool {
        line.range(of: #"[？?]|什么|为什么|如何|怎么|是否|区别|简述|解释|谈谈|介绍|说说|对比|试述|^(?:what|why|how|explain|describe)\b"#,
                   options: [.regularExpression, .caseInsensitive]) != nil
    }
    private static func repeatedMargins(_ pages: [String]) -> Set<String> {
        guard pages.count >= 2 else { return [] }
        var counts: [String: Int] = [:]
        for page in pages {
            let lines = page.components(separatedBy: .newlines).map(\.trimmed).filter { !$0.isEmpty }
            let edges = Set(Array(lines.prefix(2)) + Array(lines.suffix(2)))
            for line in edges where line.count < 100 && !looksLikeQuestion(line)
                && line.range(of: #"题库|面试题|面试宝典|学习资料|版权所有|www\.|https?://"#, options: [.regularExpression, .caseInsensitive]) != nil
                && line.range(of: #"题目|答案|解析|Question|Answer|^[0-9]+[.、]"#, options: [.regularExpression, .caseInsensitive]) == nil {
                counts[line, default: 0] += 1
            }
        }
        return Set(counts.filter { $0.value >= max(2, Int(ceil(Double(pages.count) * 0.6))) }.map(\.key))
    }
}
