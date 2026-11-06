# 一题 · OneQuestion

<img src="docs/assets/app-icon.png" width="88" alt="一题应用图标">

一次只练一道技术面试题。导入自己的题库，写下回答，获得可解释的分项反馈，再按掌握程度复习。

**一题**是一款以本地存储为基础的原生 macOS 桌面应用，使用 SwiftUI、AppKit 和 SQLite 实现，支持 PDF / Excel / CSV / JSON 题库导入、扫描件本地 OCR，以及可选的 AI 简答题评价。

Native macOS interview practice cards with PDF/Excel import, on-device OCR, local storage, and optional AI feedback.

当前版本 **v0.3.0**；支持 macOS 13 及以上，已在 Apple Silicon（M 系列）Mac 上构建与测试。

## 已实现功能

| 功能 | 当前实现 |
|---|---|
| 单题卡片练习 | 每次显示一题、文字作答、顺序 / 随机练习、改写重答 |
| 原生桌面交互 | 菜单栏入口、窗口置顶、键盘快捷键、深浅色外观 |
| 题库管理 | 新建与编辑、分类标签、搜索、JSON 导出 |
| 多格式导入 | PDF、Excel `.xlsx`、CSV、JSON，支持拖拽文件 |
| PDF 与扫描件 | PDFKit 文字提取、Vision 中英文 OCR、跨页合并、来源页码 |
| 导入预览 | 校正题目与答案、调整 PDF 提取文字、重复题跳过或更新 |
| AI 题库整理 | 按语义区分题干与原文答案，支持长文分段和已导入题目修正 |
| AI 简答题评价 | 分项评分、原文依据、遗漏纠正、改进回答、失败重试 |
| 自评与复习 | 参考答案对照、三档掌握程度、只练待复习题 |
| 本地数据 | 草稿自动保存、独立作答历史、题目与答案版本快照 |
| 凭据管理 | API 密钥存入 macOS 钥匙串，支持安全命令行配置 |

## 功能如何实现

应用分为原生界面层 `OneQuestionMac` 和核心模块 `OneQuestionCore`，没有第三方 Swift 包依赖。

| 模块 | 实现方式 |
|---|---|
| 界面与状态 | SwiftUI 数据绑定，AppKit 控制窗口，`AppStore` 协调练习和异步任务 |
| 文字 PDF / OCR | PDFKit 逐页读取，文字不足时用 Vision 在本机识别 |
| 表格导入 | CSV 状态机；Excel 解读 OOXML、共享字符串和工作表关系 |
| 持久化 | 系统 SQLite C API，参数绑定、事务写入、Codable 数据快照 |
| AI 反馈 | URLSession 调用 Chat Completions 兼容接口，客户端校验引用和分数并汇总 |
| 隐私 | Keychain Services 保存密钥，PDF 与题库文件在本地解析 |

完整的流程、代码索引和存储设计见 **[功能实现文档](docs/IMPLEMENTATION.md)**。

## 快速开始

需要 macOS 13+、Swift 6.0+、Apple Command Line Tools 或 Xcode，以及 Python 3。已验证的 Swift 版本为 6.1.2。

```bash
git clone https://github.com/caititty/one-question-mac.git
cd one-question-mac
bash scripts/build-app.sh
```

构建后双击 `dist/一题.app`。首次启动包含 4 道 Java / 数据库示例题。

1. 输入自己的回答，按 **⌘ Return** 提交。
2. 未配置 AI 时，对照参考答案，并选择“需复习 / 部分掌握 / 已掌握”。
3. 点击“下一题”继续；“改写再答”保留原回答并创建新的作答记录。
4. 通过工具栏打开题库管理，或按 **⇧⌘L**；通过 **⇧⌘H** 查看历史。
5. 菜单栏图标可以重新唤起答题卡；工具栏图钉控制窗口置顶。

## 导入自己的题库

点击“导入”或按 **⌘O**，支持 `.pdf`、`.xlsx`、`.csv`、`.json`，也可以把文件拖入答题窗口。

`Templates/` 内提供三种格式的可用模板。题库管理窗口的“导入模板”会打开模板目录。

- Excel 读取**第一张工作表**，首行为列名，不依赖安装 Microsoft Excel。旧版 `.xls` 需要另存为 `.xlsx`。
- 中文列名：`题目ID,题目,参考答案,评分要点,分类,难度,标签,题库`。
- 题目必填。缺少参考答案的题目仍可导入，但不能自动评价。
- Excel / CSV 评分要点用换行、分号或 `|` 分隔，各要点等权；JSON 支持独立权重。
- 标签以逗号分隔。
- 导入前预览错误、缺失字段和重复题；可跳过重复，或更新题目并保留历史作答。
- 文件内重复的题目 ID 会标记为错误行。确认跳过错误行后才会处理其余有效题目。
- 同 ID 或同名题目视为重复。更新题目不会改变历史记录中的题目、答案和评分版本。
- 单文件最大 20 MB、20000 道题；Excel 最多读取 100 列。公式只使用文件中保存的缓存值，不执行宏或公式。
- 导入后题目保存在本地 SQLite 中，不再依赖原始文件。

### PDF 题库

- 文字版 PDF 使用 macOS PDFKit 逐页提取；扫描页自动尝试 Vision 本地中英文 OCR，不会上传 PDF，也不依赖 AI 接口。
- 支持 `1. / 1、 / 第1题 / 题目： / Q:` 等题目分段，以及 `答案： / 参考答案： / Answer:`、`评分要点：` 等标记。
- 跨页题目和答案会合并，来源页码随题目保存在本地。
- 识别后先进入预览，逐题点“编辑”调整题目和答案；也可点“调整提取文字”，补充分段标记后重新识别。
- 无清晰题号的资料不会自动编造题目；可以调整提取文字后再拆题。
- 只有题目的 PDF 也可导入，参考答案留空并提示待补充。
- 最多 200 页、20 MB；显示提取 / OCR 进度并支持取消。加密或限制复制的 PDF 需先取得可读取的版本。
- 复杂分栏、图表、公式、手写内容及低清晰度扫描件可能识别不完整，需在预览中核对修正。不会将图表转换为可作答的图像题。

### 使用 DeepSeek / AI 区分问题与答案

当规则把讲解并入题干，或者没有识别出标准答案时：

1. 在设置中配置模型地址、模型 ID 和密钥，例如你自己的 DeepSeek 兼容服务。
2. 导入 PDF，在预览中点击 **“AI 区分问题与答案”**。
3. 模型按上下文选取原文中的题干与答案；缺少答案时保持留空，不自动编写标准答案。
4. 核对预览，必要时点“编辑”，再确认导入。

题库中已经导入的题目可点击 **“AI 整理本题”**，确认后更新原题，保留历史作答；如果一条记录混入多道题，额外题目会作为新题导入。

AI 整理会向当前配置的模型服务发送本次提取文字或所选题目文字，需要有效接口。它与“提交回答后自动评价”的开关独立。单次最多 30 万字，长文分段处理并显示进度；取消、接口错误或无效结果不会覆盖原预览，也不会自动写入题库。

客户端只接受模型选择的原文行号，并从本机原文组装题干和答案，拒绝不存在的行号及题干/答案重叠。这能限制补写内容，但语义归属仍需人工核对。题干被改写或拆分时需重新核对评分要点。

JSON 示例：

```json
{
  "version": 1,
  "deckName": "Java 面试",
  "questions": [
    {
      "id": "java-001",
      "title": "Java 中，== 和 equals() 有什么区别？",
      "referenceAnswer": "在这里填写经过核对的参考答案。",
      "criteria": [
        { "id": "point-1", "text": "区分值比较与引用比较", "weight": 5 },
        { "id": "point-2", "text": "解释 equals 的默认行为与重写", "weight": 5 }
      ],
      "category": "Java 基础",
      "difficulty": "基础",
      "tags": ["对象"]
    }
  ]
}
```

## AI 评价

在 **⌘, 设置** 中填写 Chat Completions 兼容服务的地址、模型 ID、API 密钥，再启用自动评价。地址可填写到 `/v1`，或提供完整 `/chat/completions` 路径。本地模型允许 `http://localhost` 地址；远程接口要求 HTTPS。支持 JSON 模式的服务建议保持该选项开启。

仅在提交或主动重试时发送本题、参考答案、评分要点和本次回答。密钥存入 macOS 钥匙串，不写入数据库或题库导出文件。网络请求不跟随重定向。

结果包含分项分数、逐字原文依据、遗漏纠正和改进回答。总分由应用计算；无效分数、缺失要点和不存在于回答中的原文引用会被拒绝。AI 评价仍需结合人工判断，应用允许额外标记自评掌握程度。

本地练习、自评与 PDF OCR 无需 AI 接口。自动评价需要使用者自行配置可用的模型服务、密钥及对应额度；不同模型的反馈质量可能不同。

也可通过隐藏输入配置，密钥经标准输入传递：

```bash
python3 scripts/configure-runtime.py --endpoint https://your-provider.example/v1 --model your-model-id
dist/一题.app/Contents/MacOS/OneQuestion --test-ai
```

自检使用内置的公开示例题，会向你配置的服务发送一次请求。

使用 `dist/一题.app/Contents/MacOS/OneQuestion --test-import-ai` 可单独自检题目与答案整理，不读取个人题库、不修改练习记录。

## 数据

默认保存于 `~/Library/Application Support/OneQuestion/`。设置中的“打开数据目录”可定位它。备份完整记录前请退出应用，再复制整个目录；题库管理也可单独导出题库 JSON（不含作答历史）。

草稿自动保存。每次提交独立留档，历史记录保留当时的题目和参考答案。只练待复习依据每道题最近一次作答的自评或 AI 得分筛选；目前未实现按日期间隔调度。

## 开发与构建

运行测试与生成安装包：

```bash
bash scripts/test.sh
bash scripts/build-app.sh --dmg
```

构建辅助脚本会将工具链接口复制到项目的 `.build` 中，并通过本地 VFS 覆盖处理本机残留的重复模块映射；不会修改系统 Swift 工具链。测试使用 Swift Testing，无需完整 Xcode 的 XCTest 框架。

27 项测试覆盖多格式导入、历史快照、AI 评分与整理校验、跨段答案合并、失败保留原预览、PDF 跨页提取和中英文扫描件 OCR。AI 整理测试使用模拟响应，不依赖真实服务；OCR 测试需正常访问 macOS Vision 服务。

`--dmg` 需要系统允许创建磁盘映像；受限环境下可先使用不带该参数的命令生成 `.app`。

本地试用版使用 ad-hoc 签名，尚未申请 Developer ID 签名和 Apple 公证。对外发行时需补充正式分发流程。当前只构建并验证 arm64；Intel 版本需要另行编译验证。全局快捷键、语音答题、自动追问、云同步暂不包含在此原型中。

接口格式依据：[OpenAI Chat Completions 官方文档](https://developers.openai.com/api/reference/resources/chat/subresources/completions/methods/create)。
