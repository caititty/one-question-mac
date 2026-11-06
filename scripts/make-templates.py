from pathlib import Path
from xml.sax.saxutils import escape
import csv
import json
import zipfile

root = Path(__file__).resolve().parents[1]
templates = root / "Templates"
fixtures = root / "Tests" / "OneQuestionCoreTests" / "Fixtures"
templates.mkdir(exist_ok=True)
fixtures.mkdir(exist_ok=True)
questions = [
    {
        "id": "template-equals", "title": "Java 中，== 和 equals() 有什么区别？",
        "referenceAnswer": "== 对基本类型比较值，对引用类型判断是否为同一对象。Object.equals 默认按对象身份判断，类可以重写它，例如 String 按字符内容比较。",
        "criteria": [{"id": "identity", "text": "区分值比较和对象身份比较", "weight": 5}, {"id": "override", "text": "解释 equals 的默认行为与重写", "weight": 5}],
        "category": "Java 基础", "difficulty": "基础", "tags": ["对象", "相等性"], "deck": "我的导入题库"
    },
    {
        "id": "template-index", "title": "数据库索引有哪些收益和代价？",
        "referenceAnswer": "索引能减少适用查询需要扫描的数据。\n索引会占用空间，并增加写入时维护索引的成本，效果取决于查询条件与执行计划。",
        "criteria": [{"id": "benefit", "text": "解释减少扫描的收益", "weight": 5}, {"id": "cost", "text": "说明空间与写入维护成本", "weight": 5}],
        "category": "数据库", "difficulty": "基础", "tags": ["索引"], "deck": "我的导入题库"
    }
]
(templates / "interview-template.json").write_text(json.dumps({"version": 1, "deckName": "我的导入题库", "questions": questions}, ensure_ascii=False, indent=2), encoding="utf-8")
header = ["题目ID", "题目", "参考答案", "评分要点", "分类", "难度", "标签", "题库"]
rows = [header] + [[q["id"], q["title"], q["referenceAnswer"], "\n".join(p["text"] for p in q["criteria"]), q["category"], q["difficulty"], ",".join(q["tags"]), q["deck"]] for q in questions]
with (templates / "interview-template.csv").open("w", encoding="utf-8-sig", newline="") as f:
    csv.writer(f).writerows(rows)


def workbook(path, table, shared=False):
    strings = []
    sheet_rows = []
    for number, row in enumerate(table, 1):
        cells = []
        for col, text in enumerate(row):
            ref = f"{chr(65 + col)}{number}"
            if shared:
                strings.append(text)
                cells.append(f'<c r="{ref}" t="s"><v>{len(strings)-1}</v></c>')
            else:
                cells.append(f'<c r="{ref}" t="inlineStr"><is><t xml:space="preserve">{escape(text)}</t></is></c>')
        sheet_rows.append(f'<row r="{number}">{"".join(cells)}</row>')
    main_ns = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
    rel_ns = "http://schemas.openxmlformats.org/package/2006/relationships"
    doc_rel_ns = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    files = {
        "[Content_Types].xml": f'<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>{"<Override PartName=\"/xl/sharedStrings.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml\"/>" if shared else ""}</Types>',
        "_rels/.rels": f'<Relationships xmlns="{rel_ns}"><Relationship Id="rId1" Type="{doc_rel_ns}/officeDocument" Target="xl/workbook.xml"/></Relationships>',
        "xl/workbook.xml": f'<workbook xmlns="{main_ns}" xmlns:r="{doc_rel_ns}"><sheets><sheet name="面试题库" sheetId="2" r:id="rId2"/></sheets></workbook>',
        "xl/_rels/workbook.xml.rels": f'<Relationships xmlns="{rel_ns}"><Relationship Id="rId2" Type="{doc_rel_ns}/worksheet" Target="worksheets/sheet2.xml"/>{f"<Relationship Id=\"rId3\" Type=\"{doc_rel_ns}/sharedStrings\" Target=\"sharedStrings.xml\"/>" if shared else ""}</Relationships>',
        "xl/worksheets/sheet2.xml": f'<worksheet xmlns="{main_ns}"><sheetData>{"".join(sheet_rows)}</sheetData></worksheet>'
    }
    if shared:
        files["xl/sharedStrings.xml"] = f'<sst xmlns="{main_ns}" count="{len(strings)}" uniqueCount="{len(strings)}">' + "".join(f'<si><t xml:space="preserve">{escape(s)}</t></si>' for s in strings) + "</sst>"
    with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
        for name, text in files.items():
            z.writestr(name, '<?xml version="1.0" encoding="UTF-8"?>' + text)


workbook(templates / "interview-template.xlsx", rows)
workbook(fixtures / "shared-strings.xlsx", [["题目", "参考答案", "评分要点"], ["从共享字符串读取的问题", "多行\n参考答案", "要点一;要点二"]], shared=True)
print("Created JSON, CSV, XLSX templates and XLSX test fixture")
