import Foundation

public enum QuestionImporter {
    public static func load(url: URL, progress: (@Sendable (String) -> Void)? = nil) throws -> ImportDocument {
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 20_000_000 else { throw AppFailure("题库文件请控制在 20 MB 以内。") }
        let name = url.deletingPathExtension().lastPathComponent
        switch url.pathExtension.lowercased() {
        case "pdf": return try PDFQuestionImporter.load(url: url, progress: progress)
        case "json": return try parseJSON(Data(contentsOf: url), name: name)
        case "csv":
            let data = try Data(contentsOf: url)
            guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else { throw AppFailure("CSV 请使用 UTF-8 编码。") }
            return try fromTable(parseCSV(text), name: name)
        case "xlsx": return try fromTable(XLSXReader.read(url), name: name)
        default: throw AppFailure("请选择 .pdf、.xlsx、.csv 或 .json 文件。旧版 .xls 请先另存为 .xlsx。")
        }
    }

    public static func parseJSON(_ data: Data, name: String) throws -> ImportDocument {
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data) }
        catch { throw AppFailure("JSON 格式有误：\(error.localizedDescription)") }
        let objects: [Any]
        var deck = name
        if let array = root as? [Any] { objects = array }
        else if let dictionary = root as? [String: Any], let array = dictionary["questions"] as? [Any] {
            objects = array
            deck = (dictionary["deckName"] as? String) ?? (dictionary["name"] as? String) ?? name
        } else { throw AppFailure("JSON 顶层应为题目数组，或包含 questions 数组的对象。") }
        guard !objects.isEmpty, objects.count <= 20_000 else { throw AppFailure("题库应包含 1–20000 道题目。") }
        let rows = objects.enumerated().map { offset, object -> ImportRow in
            do {
                guard let dictionary = object as? [String: Any] else { throw AppFailure("题目必须是 JSON 对象。") }
                return try row(dictionary, number: offset + 1, deck: deck)
            } catch { return ImportRow(line: offset + 1, question: nil, issue: error.localizedDescription) }
        }
        return markRepeatedIDs(ImportDocument(name: deck, rows: rows))
    }

    public static func parseCSV(_ source: String) throws -> [[String]] {
        let text = source.hasPrefix("\u{feff}") ? String(source.dropFirst()) : source
        var rows: [[String]] = [], row: [String] = [], field = ""
        var quoted = false, closed = false
        let characters = Array(text)
        var i = 0
        func endField() { row.append(field); field = ""; closed = false }
        func endRow() { endField(); rows.append(row); row = [] }
        while i < characters.count {
            let c = characters[i]
            if quoted {
                if c == "\"" {
                    if i + 1 < characters.count && characters[i + 1] == "\"" { field.append("\""); i += 1 }
                    else { quoted = false; closed = true }
                } else { field.append(c) }
            } else if c == "," { endField() }
            else if c == "\n" || c == "\r" || c == "\r\n" {
                endRow()
                if c == "\r", i + 1 < characters.count, characters[i + 1] == "\n" { i += 1 }
            } else if c == "\"" {
                guard field.isEmpty && !closed else { throw AppFailure("CSV 引号位置不正确，请使用模板或从 Excel 导出。") }
                quoted = true
            } else {
                if closed {
                    guard c == " " || c == "\t" else { throw AppFailure("CSV 结束引号后存在多余字符。") }
                } else { field.append(c) }
            }
            i += 1
        }
        guard !quoted else { throw AppFailure("CSV 中有未闭合的引号。") }
        if !field.isEmpty || !row.isEmpty || closed { endRow() }
        return rows
    }

    public static func fromTable(_ table: [[String]], name: String) throws -> ImportDocument {
        guard let headerIndex = table.firstIndex(where: { $0.contains { !$0.trimmed.isEmpty } }) else { throw AppFailure("文件中没有题目。") }
        let header = table[headerIndex].map(normalize)
        guard header.contains(where: { aliases["title"]!.contains($0) }) else { throw AppFailure("首行需要包含“题目”或 title 列，请参考导入模板。") }
        guard table.count <= 20_001 else { throw AppFailure("每次最多导入 20000 道题。") }
        var result: [ImportRow] = []
        for index in (headerIndex + 1)..<table.count {
            let cells = table[index]
            if cells.allSatisfy({ $0.trimmed.isEmpty }) { continue }
            var object: [String: Any] = [:]
            for (column, key) in header.enumerated() where column < cells.count && !key.isEmpty { object[key] = cells[column] }
            do { result.append(try row(object, number: index + 1, deck: name)) }
            catch { result.append(ImportRow(line: index + 1, question: nil, issue: error.localizedDescription)) }
        }
        guard !result.isEmpty else { throw AppFailure("表头下没有可导入的题目。") }
        return markRepeatedIDs(ImportDocument(name: name, rows: result))
    }

    private static let aliases: [String: [String]] = [
        "id": ["id", "题目id", "编号"], "title": ["title", "question", "题目", "问题", "题干"],
        "referenceAnswer": ["referenceanswer", "answer", "参考答案", "答案", "标准答案"],
        "criteria": ["criteria", "keypoints", "评分要点", "要点", "得分点"],
        "deck": ["deck", "deckname", "题库", "题库名称"], "category": ["category", "分类"],
        "difficulty": ["difficulty", "难度"], "tags": ["tags", "标签"], "source": ["source", "来源"]
    ]
    private static func normalize(_ value: String) -> String { value.trimmed.lowercased().replacingOccurrences(of: "_", with: "").replacingOccurrences(of: " ", with: "") }
    private static func row(_ object: [String: Any], number: Int, deck: String) throws -> ImportRow {
        var dictionary: [String: Any] = [:]
        for (key, value) in object { dictionary[normalize(key)] = value }
        func value(_ key: String) -> Any? { aliases[key]?.compactMap { dictionary[$0] }.first }
        func string(_ key: String) -> String {
            if let s = value(key) as? String { return s.trimmed }
            if let n = value(key) as? NSNumber { return n.stringValue }
            return ""
        }
        let title = string("title")
        guard !title.isEmpty else { throw AppFailure("题目不能为空。") }
        guard title.count <= 10_000 else { throw AppFailure("题目过长，请控制在 10000 字以内。") }
        let reference = string("referenceAnswer")
        var criteria: [Criterion] = []
        if let values = value("criteria") as? [Any] {
            for item in values {
                if let text = item as? String, !text.trimmed.isEmpty { criteria.append(Criterion(text: text.trimmed)) }
                else if let item = item as? [String: Any], let text = (item["text"] ?? item["point"]) as? String, !text.trimmed.isEmpty {
                    let weight: Int
                    if let supplied = item["weight"] {
                        guard let n = supplied as? NSNumber, n.doubleValue == Double(n.intValue) else { throw AppFailure("评分权重需要是整数。") }
                        weight = n.intValue
                    } else { weight = 1 }
                    criteria.append(Criterion(id: (item["id"] as? String) ?? UUID().uuidString, text: text.trimmed, weight: weight))
                } else { throw AppFailure("评分要点需要是文字或包含 text、weight 的对象。") }
            }
        } else if let text = value("criteria") as? String {
            criteria = text.components(separatedBy: CharacterSet(charactersIn: "\n;；|")).map(\.trimmed).filter { !$0.isEmpty }.map { Criterion(text: $0) }
        } else if value("criteria") != nil { throw AppFailure("评分要点格式不正确。") }
        guard criteria.count <= 50, criteria.allSatisfy({ (1...100).contains($0.weight) && !$0.id.isEmpty }), Set(criteria.map(\.id)).count == criteria.count else { throw AppFailure("评分要点最多 50 条，权重为 1–100，且要点 ID 不得重复。") }
        let tags = (value("tags") as? [String]) ?? string("tags").components(separatedBy: CharacterSet(charactersIn: ",，;；|"))
        let question = Question(id: string("id").isEmpty ? UUID().uuidString : string("id"), title: title,
            referenceAnswer: reference, criteria: criteria, deck: string("deck").isEmpty ? deck : string("deck"),
            category: string("category").isEmpty ? "未分类" : string("category"), difficulty: string("difficulty").isEmpty ? "基础" : string("difficulty"),
            tags: tags.map(\.trimmed).filter { !$0.isEmpty }, source: string("source").isEmpty ? nil : string("source"))
        return ImportRow(line: number, question: question, warning: reference.isEmpty ? "缺少参考答案，暂不支持自动评价" : nil)
    }
    private static func markRepeatedIDs(_ document: ImportDocument) -> ImportDocument {
        var seen = Set<String>()
        let rows = document.rows.map { row -> ImportRow in
            guard let q = row.question else { return row }
            guard seen.insert(q.id).inserted else { return ImportRow(line: row.line, question: nil, issue: "文件内题目 ID 重复：\(q.id)") }
            return row
        }
        return ImportDocument(name: document.name, rows: rows)
    }
}

extension String { public var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) } }

private enum XLSXReader {
    static func read(_ url: URL) throws -> [[String]] {
        let listing = try unzip(url, arguments: ["-l"])
        guard let list = String(data: listing, encoding: .utf8) else { throw AppFailure("无法读取 Excel 文件。") }
        let lines = list.components(separatedBy: .newlines)
        var total = 0
        for line in lines {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 4, let length = Int(parts[0]), parts[1].contains("-") { total += length }
        }
        guard total < 40_000_000 else { throw AppFailure("Excel 解压后过大，请拆分题库。") }
        let workbook = try entry(url, "xl/workbook.xml")
        let relationships = try entry(url, "xl/_rels/workbook.xml.rels")
        let locator = WorkbookParser()
        try parse(workbook, delegate: locator); try parse(relationships, delegate: locator)
        guard let relation = locator.firstSheet, let target = locator.targets[relation] else { throw AppFailure("Excel 中没有可读取的工作表。") }
        let path = target.hasPrefix("/") ? String(target.dropFirst()) : ("xl/" + target as NSString).standardizingPath
        guard path.hasPrefix("xl/worksheets/"), !path.contains(".."), path.hasSuffix(".xml") else { throw AppFailure("Excel 工作表路径无效。") }
        var strings: [String] = []
        if let shared = try? entry(url, "xl/sharedStrings.xml") {
            let parser = SharedStringsParser(); try parse(shared, delegate: parser); strings = parser.values
        }
        let sheet = WorksheetParser(strings: strings)
        do { try parse(try entry(url, path), delegate: sheet) }
        catch {
            if sheet.tooLarge { throw AppFailure("Excel 最多支持 20000 行和 100 列，请拆分后重试。") }
            throw error
        }
        guard !sheet.tooLarge else { throw AppFailure("Excel 最多支持 20000 行和 100 列，请拆分后重试。") }
        return sheet.rows
    }
    static func unzip(_ url: URL, arguments: [String]) throws -> Data {
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments + [url.path]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw AppFailure("Excel 文件无法读取，请确认是有效的 .xlsx 文件。") }
        return data
    }
    static func entry(_ url: URL, _ path: String) throws -> Data {
        guard path.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[]")) == nil else { throw AppFailure("Excel 内部路径无效。") }
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = ["-p", url.path, path]
        let output = Pipe(); process.standardOutput = output; process.standardError = FileHandle.nullDevice
        try process.run(); let data = output.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0, data.count < 40_000_000 else { throw AppFailure("Excel 内容无法读取或过大。") }
        return data
    }
    static func parse(_ data: Data, delegate: XMLParserDelegate) throws {
        let parser = XMLParser(data: data); parser.shouldResolveExternalEntities = false; parser.delegate = delegate
        guard parser.parse() else { throw AppFailure("Excel XML 格式有误。") }
    }
}

private final class WorkbookParser: NSObject, XMLParserDelegate {
    var firstSheet: String?; var targets: [String: String] = [:]
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "sheet", firstSheet == nil { firstSheet = attributes["r:id"] }
        if name == "Relationship", let id = attributes["Id"], let target = attributes["Target"] { targets[id] = target }
    }
}
private final class SharedStringsParser: NSObject, XMLParserDelegate {
    var values: [String] = []; var current = ""; var inText = false
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "si" { current = "" }; if name == "t" { inText = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if inText { current += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "t" { inText = false }; if name == "si" { values.append(current) }
    }
}
private final class WorksheetParser: NSObject, XMLParserDelegate {
    let strings: [String]; var rows: [[String]] = []; var tooLarge = false
    var row: [String] = []; var type = ""; var content = ""; var column = 0; var reading = false
    init(strings: [String]) { self.strings = strings }
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        if name == "row" {
            row = []
            if let number = Int(attributes["r"] ?? ""), number > 0 {
                if number > 20_001 { tooLarge = true; parser.abortParsing(); return }
                while rows.count < number - 1 { rows.append([]) }
            }
        }
        if name == "c" {
            type = attributes["t"] ?? ""; content = ""; column = 0
            for c in (attributes["r"] ?? "A").uppercased().unicodeScalars where (65...90).contains(c.value) { column = column * 26 + Int(c.value - 64) }
            column -= 1
            if column < 0 || column >= 100 { tooLarge = true; parser.abortParsing() }
        }
        if name == "v" || name == "t" { reading = true }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) { if reading { content += string } }
    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if name == "v" || name == "t" { reading = false }
        if name == "c", column >= 0, column < 100 {
            while row.count <= column { row.append("") }
            if type == "s", let i = Int(content), strings.indices.contains(i) { row[column] = strings[i] }
            else { row[column] = content }
        }
        if name == "row" {
            rows.append(row)
            if rows.count > 20_001 { tooLarge = true; parser.abortParsing() }
        }
    }
}
