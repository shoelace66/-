# AI 角色扮演对话应用

> 基于 Flutter 的本地 AI 角色/故事对话应用：长期记忆、关键词召回 + 事件图 BFS、三级级联、opencode 助手桥接。

[![Flutter](https://img.shields.io/badge/Flutter-3.41-02569B)](.) [![Dart](https://img.shields.io/badge/Dart-3.4%2B-0175C2)](.) [![License](https://img.shields.io/badge/license-private-lightgrey)](.)

---

## 项目定位

单设备离线优先的 AI 角色扮演 App。LLM 调用走 HTTP（自配 base URL + API Key），长期记忆存在本地。**不上云、不上传联系人数据。**

> 📐 想看完整架构与数据流图：见 [docs/architecture.html](docs/architecture.html)（含 mermaid 流程图、状态机、数据存储布局、参数对照表）。

## 三种联系人

| 类型 | category | 引擎 | 走哪条路径 |
|---|---|---|---|
| **角色** | `ContactCategory.contact` | LLM + 结构化记忆 | `sendMessage` → `AiService` → 事件图 |
| **故事** | `ContactCategory.story` | LLM + 结构化记忆（schema 略不同） | 同上，`_buildJsonFormat(isStory: true)` |
| **助手** | `ContactCategory.assistant` | opencode 桥接 | `_sendAssistantMessage` → `OpencodeService` |

## 核心能力

- **三级记忆级联**：短期（10）→ 长期（5）→ 超长期（2），阈值触发 + LLM 压缩，详见 [架构图](docs/architecture.html#三级记忆短期--长期--超长期)
- **关键词召回 + 事件图 BFS**：本地 jieba + LLM 抽取关键词做关键词命中；`relatedEventsForPrompt` 在事件图上按关键词 + 边做 BFS 邻居检索（深度由 `searchDepth` 控制）。两条召回结果合并去重后进入 prompt 的"联想内容"段
- **事件间边关系**：LLM 通过 `relatedEventIds` 声明强关联，**硬上限 2 个**；LRU 排序按关键词 + 邻居 + 物品/设定 关联权重综合打分
- **三种创建方式**：表单 / JSON 导入 / 自然语言描述（LLM 转 JSON）
- **撤回最近一轮**：基于 snapshot，可恢复消息列表 + 联系人
- **调试模式**：显示完整 prompt + 关键词提取结果
- **应用设置**：21 项可调（详见 [应用设置](#应用设置)）

## 项目结构

```
lib/
├── main.dart, app.dart              # 入口
├── features/chat/
│   ├── domain/
│   │   ├── providers/chat_provider.dart     # 核心状态机 (~2800 行)
│   │   └── services/{heartbeat,input_formatter}.dart
│   ├── data/
│   │   ├── models/{contact,message}.dart    # 联系人（含 eventGraph）、消息
│   │   ├── repositories/chat_repository.dart
│   │   └── datasources/chat_local_storage.dart  # SharedPreferences
│   └── presentation/
│       ├── pages/chat_page.dart              # 主聊天界面
│       └── widgets/{contact_sidebar,contact_editor_dialog}.dart
├── core/
│   ├── data/models/app_settings.dart
│   ├── presentation/pages/{app_settings,assistant_config}_page.dart
│   └── utils/
│       ├── structured_input_prompt_composer.dart  # prompt 拼接
│       ├── structured_output_regex_parser.dart    # JSON 解析
│       ├── vector_memory_service.dart              # 向量记忆（预留扩展位：searchSimilar 未参与 prompt 拼装）
│       └── chinese_tokenizer_service.dart          # jieba
└── infrastructure/services/
    ├── ai_service.dart        # LLM HTTP 客户端
    └── opencode_service.dart  # opencode REST 客户端
```

## 数据流（角色对话，单轮）

```mermaid
sequenceDiagram
    autonumber
    actor U as User
    participant CP as ChatProvider
    participant KW as Keyword Extract
    participant VM as Vector Memory
    participant CO as Composer
    participant AS as AiService
    participant LL as LLM
    participant SP as SharedPreferences
    participant PR as Parser

    U->>CP: sendMessage(text)
    CP->>CP: _saveSnapshot(contact)
    CP->>KW: jieba 本地 + LLM 抽取
    KW-->>CP: keywords + theme
    Note over CP: 相关事件: relatedEventsForPrompt(keywords, depth)<br/>BFS 邻居检索（已加 prompt）
    CP-->>VM: searchSimilar(top 3)
    Note right of VM: 虚线 = 当前未参与 prompt 拼装<br/>属预留扩展位（见已知限制）
    CP->>CO: composeSystemPromptWithContactObject
    CO-->>CP: systemPrompt
    CP->>AS: askAi(prompt)
    AS->>LL: POST chat/completions
    LL-->>AS: {reply, memoryPatch}
    AS-->>CP: 响应
    CP->>PR: extractReply + extractMemoryPatch
    CP->>CP: _updateContactFromMemoryPatch
    Note over CP: 合并知识 / 事件 → short-term /<br/>summary? → long-term /<br/>belongings / states / edges / LRU
    CP->>SP: saveContacts + saveMessagesByContact
    CP->>VM: addMemoryEntry(userMessage)
    CP-->>U: UI 刷新
```

## 三级记忆（1→2 与 2→3 级联）

- **1→2** 触发：短期 un-summarized ≥ `summaryThreshold`（默认 10）
  - LLM 强制输出 `summary`，进入长期 un-summarized
  - 旧 brief 搬入长期、标 summarized
- **2→3** 触发：长期 un-summarized ≥ `ultraSummaryThreshold`（默认 5），**仅在 1→2 未触发时**
  - 同样 LLM 输出 `summary`，进入超长期 un-summarized
  - 旧长期 entry 搬入超长期、标 summarized
- LLM 也可在场景/话题结束时**自主**输出 summary（不强制时）
- 调 `ultraSummaryThreshold = 999` 即禁用 2→3

> LLM 输出 summary 的提示词在 `_buildRules(mustSummarize: ...)` 区分强制 vs 自主。

## 边关系

LLM 在 `memoryPatch.relatedEventIds` 里声明与本次事件强相关的往期事件编号：

- **硬上限 2 个**，重复边去重
- 提示词里强调：宁缺毋滥，不要连环关联
- 用于建立事件间边图，LRU 评分时会按 `lruEventEventWeight`（默认 50）给邻居事件加成

## 助手（opencode）

不走 LLM，直接 HTTP 调 PC 上跑的 `opencode serve`（默认 :4096）：

```mermaid
sequenceDiagram
    actor U as User
    participant CP as ChatProvider
    participant OS as OpencodeService
    participant OC as opencode

    U->>CP: 助手联系人发消息
    CP->>OS: execute(text)
    OS->>OC: GET /global/health
    OS->>OC: GET /config/providers (取 text-capable)
    OS->>OC: GET /session (选 text-capable session)
    OS->>OC: POST /session/:id/message
    OC-->>OS: {info, parts: [...]}
    OS->>OS: 过滤 type==="text" parts 拼接
    OS-->>CP: result.output
    CP->>CP: extractReply (StructuredOutputRegexParser)
    CP-->>U: 显示回复
```

**关键点**：
- 选模型/session 时**过滤 TTS / 纯 audio 模型**（`capabilities.output.text !== false` 且 id/name 不含 `tts`）
- LLM 响应结构和角色相同（`{reply, memoryPatch}`），按 `extractReply` 取 `reply` 字段
- 缓存 `sessionId` 持久化，复用同一会话
- Android 9+ 走明文 HTTP 需 `network_security_config.xml`（已配）

### opencode 声明与致谢

本项目的助手桥接、远程执行与会话复用等部分功能基于 opencode 的服务接口与开发体验进行适配和开发。感谢 opencode 项目及其社区提供的开放工具与启发。

本项目是独立开发的 AI 角色/故事对话应用，与 opencode 项目及其维护者不存在从属、隶属、官方合作或背书关系；项目中的 opencode 相关能力仅作为可选桥接功能使用。

## 远程连接 PC 上的 opencode

| 方式 | PC 端 | 安卓端配置 | 优缺点 |
|---|---|---|---|
| **Tailscale** | 装 Tailscale，登录同账号 | host=100.x.x.x, port=4096, http | 一次配好长期稳定，4G/5G/Wi-Fi 都通 |
| **Cloudflare Tunnel** | `cloudflared tunnel --url http://localhost:4096` | host=trycloudflare.com, port=443, https ✓ | 零配置，URL 每次启动会变 |
| **VPS SSH 反代** | `ssh -R 14096:127.0.0.1:4096 user@vps` | host=VPS 公网 IP, port=14096, http | 灵活但 VPS 自身是攻击面 |

> PC 启动：`opencode web --hostname 0.0.0.0 --port 4096`（建议 `export OPENCODE_SERVER_PASSWORD=xxx`）

## 应用设置

应用设置页（右上角齿轮）共 21 项，分 6 组：

| 分组 | 设置 | 默认 | 范围 |
|---|---|---|---|
| **LLM 输入限制** | maxShortTermEvents | 10 | 1-50 |
| | maxLongTermEvents | 1 | 1-30（默认只取最新 summary；老 summary 走 2→3 进超长期） |
| | maxUltraTermEvents | 2 | 1-20 |
| | maxRelatedEvents | 5 | 1-20 |
| **本地存储限制** | maxShortQueue | 2000 | 100-10000 |
| | maxLongQueue | 500 | 50-5000 |
| | maxUltraQueue | 200 | 20-2000 |
| **Prompt 限制** | maxPromptListItems | 5 | 1-20 |
| | maxPromptLineLength | 200 | 50-1000 |
| **事件处理** | summaryThreshold | 10 | 2-50 |
| | ultraSummaryThreshold | 5 | 2-100（设 999 禁用 2→3） |
| **关联检索** | searchDepth | 2 | 1-5（BFS 跳数） |
| | vectorSimilarityWeight | 80 | 0-100（当前未启用，保留作未来扩展位） |
| **LRU 权重** | lruKeywordMatchWeight | 100 | 1-500 |
| | lruEventEventWeight | 50 | 1-300 |
| | lruEventBelongingKeywordWeight | 30 | 1-200 |
| | lruEventBelongingNormalWeight | 10 | 1-100 |
| | lruEventSettingKeywordWeight | 30 | 1-200 |
| | lruEventSettingNormalWeight | 10 | 1-100 |
| **关键词库** | keywordLibrarySize | 200 | 50-1000 |

## 数据存储

| 数据 | 存储 | Key |
|---|---|---|
| 联系人（含 eventGraph） | SharedPreferences | `chat_contacts_v1` |
| 消息历史 | SharedPreferences | `chat_messages_v1` |
| App 设置 | SharedPreferences | `app_settings_v1` |
| opencode 连接配置 | SharedPreferences | `opencode_connection_v1` |
| 向量记忆（预留） | JSON 文件 | `<app Documents>/vector_memory.json` |

> 安卓设备查看：`adb pull /data/data/<package>/shared_prefs/`

## 已知限制

- **向量记忆是预留扩展位**：`VectorMemoryService.searchSimilar` 算出的结果目前**未参与 prompt 拼装**（`_buildPromptContact` 没消费 `weightedMemories`）。`addMemoryEntry` 在每轮发送后入库是真实运行；`vectorSimilarityWeight` 设置保留但暂未生效
- **字符级伪向量**：`_simpleEmbedding` 走 `codeUnit` 累加 + 余弦相似度，不是真语义；`tflite_flutter` 已在 `pubspec.yaml` 但未挂接真模型（属于未来升级点）
- `legacy events: EventLruBucket` 仍在写但 prompt 实际只读 `eventGraph`，旧字段是冗余
- SSH 模式在 `OpencodeService._executeViaSsh` 里是占位，**实际只支持 HTTP**
- opencode 的 `POST /session/:id/message` 是同步等待；超长 AI 任务（>300s）会撞默认超时
- `comprehensiveKeywordWeight` / `comprehensiveSemanticWeight` 字段已删除（之前是规划未落地的"综合搜索"功能）

## 构建

```bash
# 1. 安装 Flutter SDK 3.41+、Dart 3.4+
# 2. 拉依赖
flutter pub get

# 3. 调试运行（接真机或模拟器）
flutter run

# 4. 打包发布 APK
flutter build apk --release
# 产物：build/app/outputs/flutter-apk/app-release.apk
```

## 依赖

- `http: ^1.2.2` — LLM / opencode HTTP 客户端
- `shared_preferences: ^2.5.3` — 本地 KV 存储
- `path_provider: ^2.1.5` — 应用文档目录（vector_memory.json 预留位用）
- `tflite_flutter: ^0.10.4` — 已声明但**目前未挂接且未在路径上使用**（见已知限制）
- `jieba_flutter: ^0.2.0` — 中文分词

---

## 架构与数据流图

完整 mermaid 流程图、状态机、数据存储布局、参数对照表：

👉 **[docs/architecture.html](docs/architecture.html)**

（用浏览器直接打开；GitHub 上 README 里的 mermaid 块会自动渲染）
