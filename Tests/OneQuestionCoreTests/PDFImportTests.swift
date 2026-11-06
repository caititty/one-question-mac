import Testing
import Foundation
import CoreGraphics
import CoreText
import PDFKit
@testable import OneQuestionCore

struct PDFImportTests {
    @Test func numberedQuestionsKeepMultilineAnswersCodeAndPages() throws {
        let text = """
        面试题库
        【PDF第1页】
        1. Java 中 == 和 equals() 有什么区别？
        答案：== 对引用类型判断对象身份。
        String 的 equals 比较内容。
        ```text
        2. 这行在代码块中，不是新题
        ```
        【PDF第2页】
        Object 的 equals 默认判断对象身份。
        评分要点：区分值与引用（5分）
        - 说明 equals 重写（5分）
        2. 为什么要重写 hashCode？
        参考答案：相等对象必须具有相同哈希值。
        """
        let doc = try PDFQuestionImporter.parse(text: text, name: "面试")
        #expect(doc.rows.count == 2)
        let first = try #require(doc.rows[0].question)
        #expect(first.title == "Java 中 == 和 equals() 有什么区别？")
        #expect(first.referenceAnswer.contains("String 的 equals"))
        #expect(first.referenceAnswer.contains("2. 这行在代码块中"))
        #expect(first.referenceAnswer.contains("Object 的 equals"))
        #expect(first.criteria.map(\.weight) == [5, 5])
        #expect(doc.rows[0].source == "第 1–2 页")
        #expect(doc.rows[1].source == "第 2 页")
    }
    @Test func answerListsAndNumericAnswersAreNotDropped() throws {
        let text = """
        1. 如何执行一次请求？
        答案：
        1. 创建连接
        2. 执行请求
        3. 释放连接
        2. 下面表达式的结果是什么？
        答案：
        1
        """
        let doc = try PDFQuestionImporter.parse(text: text, name: "列表")
        #expect(doc.rows.count == 2)
        #expect(doc.rows[0].question?.referenceAnswer.contains("2. 执行请求") == true)
        #expect(doc.rows[1].question?.referenceAnswer == "1")
    }
    @Test func explicitMarkersAndQuestionOnlyDocuments() throws {
        let doc = try PDFQuestionImporter.parse(text: "题目：\n什么是线程安全？\n答案：多个线程并发操作时满足约定。\n题目：请介绍线程池。", name: "标记")
        #expect(doc.rows.count == 2)
        #expect(doc.rows[0].question?.canEvaluate == true)
        #expect(doc.rows[1].question?.canEvaluate == false)
        #expect(doc.rows[1].warning?.contains("缺少参考答案") == true)
        let list = try PDFQuestionImporter.parse(text: "1、Java 基础\n2、集合原理", name: "题单")
        #expect(list.rows.count == 2)
    }
    @Test func ambiguousTextRemainsEditableWithoutInventingQuestions() throws {
        let text = "这是一段没有题目分隔的普通学习资料。"
        let doc = try PDFQuestionImporter.parse(text: text, name: "资料")
        #expect(doc.rows.isEmpty)
        #expect(doc.sourceText == text)
        #expect(doc.notice?.contains("添加") == true)
    }
    @Test func nestedQuestionsAndTheirAnswersRemainOneCard() throws {
        let text = """
        1. 线程池综合题
        （1）什么是线程池？
        答案：复用工作线程处理任务。
        （2）为什么使用线程池？
        答案：减少创建开销并控制并发。
        2. 什么是索引？
        答案：辅助查找的数据结构。
        """
        let doc = try PDFQuestionImporter.parse(text: text, name: "小问")
        #expect(doc.rows.count == 2)
        #expect(doc.rows[0].question?.title == "线程池综合题\n（1）什么是线程池？\n（2）为什么使用线程池？")
        #expect(doc.rows[0].question?.referenceAnswer == "（1） 复用工作线程处理任务。\n（2） 减少创建开销并控制并发。")
        #expect(doc.rows[1].question?.title == "什么是索引？")
    }
    @Test func explicitParentKeepsPlainAndDecimalSubquestions() throws {
        let text = "第1题：线程池综合题\n1. 什么是线程池？\n答案：复用线程。\n2. 为什么使用它？\n答案：减少开销。\n2.1 如何限制并发？\n答案：限制线程数。\n第2题：什么是索引？\n答案：辅助查找的结构。"
        let doc = try PDFQuestionImporter.parse(text: text, name: "层级")
        #expect(doc.rows.count == 2)
        let first = try #require(doc.rows[0].question)
        #expect(first.title.contains("1. 什么是线程池？"))
        #expect(first.title.contains("2. 为什么使用它？"))
        #expect(first.title.contains("2.1 如何限制并发？"))
        #expect(first.referenceAnswer == "1. 复用线程。\n2. 减少开销。\n2.1 限制线程数。")
    }
    @Test func independentParenthesizedQuestionsStillSplit() throws {
        let doc = try PDFQuestionImporter.parse(text: "（1）什么是线程？\n答案：执行单元。\n（2）什么是进程？\n答案：资源分配单元。", name: "独立题")
        #expect(doc.rows.count == 2)
    }
    @Test func explicitQuestionFollowedByNumberedIndependentQuestionStillSplits() throws {
        let doc = try PDFQuestionImporter.parse(text: "题目：什么是线程？\n答案：执行单元。\n2. 什么是进程？\n答案：资源分配单元。", name: "混合题号")
        #expect(doc.rows.count == 2)
        #expect(doc.rows[1].question?.title == "什么是进程？")
    }
    @Test func textPDFIsExtractedAcrossPages() throws {
        let url = try makePDF(pages: [
            ["1. What is reference equality?", "Answer: Both references identify the same object.", "The answer continues on the following page."],
            ["It differs from a class-defined logical equality method.", "2. What is an index?", "Answer: An auxiliary structure that reduces search work."]
        ])
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try QuestionImporter.load(url: url)
        #expect(doc.rows.count == 2)
        #expect(doc.rows[0].question?.referenceAnswer.contains("logical equality") == true)
        #expect(doc.rows[0].source == "第 1–2 页")
        #expect(doc.notice?.contains("0 页使用本地 OCR") == true)
    }
    @Test func scannedPDFUsesLocalOCR() throws {
        let url = try makePDF(pages: [["1. What is a thread?", "Answer: A unit of execution within a process."]], scanned: true)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(PDFDocument(url: url)?.page(at: 0)?.string?.trimmed.isEmpty != false)
        let doc = try QuestionImporter.load(url: url)
        #expect(doc.rows.count == 1)
        #expect(doc.rows[0].question?.title.localizedCaseInsensitiveContains("thread") == true)
        #expect(doc.rows[0].question?.referenceAnswer.localizedCaseInsensitiveContains("process") == true, "提取内容：\(doc.sourceText ?? "")")
        #expect(doc.notice?.contains("1 页使用本地 OCR") == true)
    }
    @Test func invalidPDFIsRejected() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try Data("not a PDF".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(throws: AppFailure.self) { try QuestionImporter.load(url: url) }
    }
    @Test func chineseScannedPDFUsesLocalOCR() throws {
        let url = try makePDF(pages: [["1. 什么是线程？", "答案：线程是进程中的执行单元。"]], scanned: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let doc = try QuestionImporter.load(url: url)
        #expect(doc.rows.count == 1)
        #expect(doc.rows[0].question?.title.contains("线程") == true)
        #expect(doc.rows[0].question?.referenceAnswer.contains("进程") == true)
        #expect(doc.notice?.contains("1 页使用本地 OCR") == true)
    }

    private func makePDF(pages: [[String]], scanned: Bool = false) throws -> URL {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let consumer = try #require(CGDataConsumer(data: data as CFMutableData))
        let pdf = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for lines in pages {
            pdf.beginPDFPage(nil)
            if scanned {
                let bitmap = try #require(CGContext(data: nil, width: 1190, height: 1684, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                bitmap.setFillColor(CGColor(gray: 1, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 1190, height: 1684))
                draw(lines, into: bitmap, scale: 2)
                let image = try #require(bitmap.makeImage()); pdf.draw(image, in: bounds)
            } else { draw(lines, into: pdf, scale: 1) }
            pdf.endPDFPage()
        }
        pdf.closePDF()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        try (data as Data).write(to: url)
        return url
    }
    private func draw(_ lines: [String], into context: CGContext, scale: CGFloat) {
        let font = CTFontCreateWithName("PingFangSC-Regular" as CFString, 14 * scale, nil)
        for (index, text) in lines.enumerated() {
            let attrs: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font,
                         kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(gray: 0, alpha: 1)]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
            context.textPosition = CGPoint(x: 36 * scale, y: (790 - CGFloat(index) * 30) * scale)
            CTLineDraw(line, context)
        }
    }
}
