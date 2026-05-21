# AI Reply (PopClip Extension)

选中邮件正文，点 PopClip 工具栏里的 **AI Reply** 按钮，扩展会调用一个 OpenAI 兼容的 chat-completions 接口生成可直接发送的回复。

支持风格预设、Follow Up 改写、API Key Pool 智能容错、按源语言回复等。

## 安装

1. 从 [Releases](../../releases) 下载 `AIReply-vX.Y.Z.popclipextz`，双击安装。
2. 在 PopClip 设置中至少配置：
   - `Endpoint`（默认 `https://ai.hybgzs.com/v1`）
   - `Model`（下拉选择，默认读取 Pick Model 选择）
   - `API Key`，或把密钥写入 `~/.config/popclip-aireply/api_key`（推荐）

> 自行构建：运行 `zsh package.sh` 生成 `.popclipextz`，双击安装或升级。

## 使用

1. 在邮件客户端、Web 邮箱或任意文本里**选中**正文。
2. 点 PopClip 工具栏里的 **AI Reply**。
3. 弹出的对话框可输入补充要求（可留空），点对应风格按钮生成：
   - **正式 Professional** — 正式商务语气（默认）
   - **友好 Friendly** — 友好亲切
   - **简洁 Concise** — 言简意赅
4. 结果对话框：
   - **OK** 关闭。
   - **Copy** 复制当前文本（可编辑后再复制）。
   - **Follow Up** 让 AI 基于当前草稿继续改写。可无限次。

### 快捷动作（在 PopClip 设置中启用）

为避免工具栏过载，扩展只保留主回复、模型选择和 Key Pool 管理动作。回复风格在设置面板统一配置。

| 动作 | 说明 |
|------|------|
| **AI Reply** | 使用设置里的默认风格生成回复，并支持 Follow Up 改写 |
| **Pick Model** | 从服务端拉取最新模型列表并选择 |
| **Manage Key Pool** | 创建/更新 API Key Pool |

## API Key 配置

按优先级从高到低读取：

1. PopClip 设置里的 `API Key` 字段（`secret` 类型，存入 macOS 钥匙串）。
2. 环境变量 `AI_REPLY_API_KEY`（在 PopClip 启动前 export 才有效）。
3. `API Key File` 指向的文件首个非空行。默认 `~/.config/popclip-aireply/api_key`。

```bash
mkdir -p ~/.config/popclip-aireply
printf '%s\n' 'YOUR_KEY_HERE' > ~/.config/popclip-aireply/api_key
chmod 600 ~/.config/popclip-aireply/api_key
```

## API Key Pool（负载均衡 & 容错）

如果你有多个 key（同一家或多家），可以配成一个 Pool。每次调用随机选一个；当某个 key 遇到 **429 / 5xx / 网络错误** 时，会自动切换到下一个 key 重试。

- **429** 时读取 `Retry-After` 头并标记该 key 冷却 60 秒。
- **5xx / 网络错误** 指数退避（0.5s → 1s → 2s），最多重试 2–3 次。
- **401 / 403 / 404 / 400 等永久错误不会跨 key 重试**——这能避免一个坏 key 把整个 Pool 都试一遍。

**推荐方式**：把 JSON 存到文件，路径填到 `API Key Pool File`（默认 `~/.config/popclip-aireply/pool.json`）：

```json
[
  { "api_key": "sk-aaa...", "endpoint": "https://api.openai.com/v1" },
  { "api_key": "sk-bbb...", "endpoint": "https://api.deepseek.com/v1" }
]
```

```bash
mkdir -p ~/.config/popclip-aireply
chmod 600 ~/.config/popclip-aireply/pool.json
```

设置了 Pool 之后，单个 `API Key` / `Endpoint` 字段会被忽略。

## Model 选择

两种方式选模型：

1. **设置面板下拉** — 预置常用模型列表，也可用 `🛠 Custom` 输入任意 model ID。
2. **Pick Model 动作** — 从 PopClip 工具栏点 Pick Model，实时拉取 endpoint 返回的最新模型列表。选择会缓存 24 小时，并覆盖设置面板的选项。

默认优先级：Pick Model 文件 > 设置面板 > 默认模型。

## 风格 / 语言

- **默认风格** 在设置里选择，默认是 `Concise`；首轮和 Follow Up 都沿用这个设置。
- **补充要求弹窗** 只用于输入临时指令（可留空），不再每次选择风格。
- **按源语言回复** 开启后，模型会自动匹配邮件语言（不限中英，支持任意语言）。
- **语言徽章** 仅作 UI 提示，由本地基于 Unicode 区段的简易检测得出。

## 文件结构

```
AIReply.popclipext/
├── Config.json             # PopClip 扩展配置（UI、选项）
├── reply.zsh               # 入口脚本（编排）
├── models.zsh              # Pick Model 动作脚本
├── lib/
│   ├── build_payload.py    # 构造 chat-completions 请求体
│   ├── parse_response.py   # 解析模型响应 / 错误
│   ├── load_pool.py        # 读取 / 校验 Key Pool
│   ├── detect_language.py  # 邮件语言检测（仅用于徽章）
│   ├── fetch_mail_thread.py # Mail.app 线程抓取
│   ├── fetch_models.py     # 服务端模型列表解析
│   ├── append_history.py   # 历史记录写入
│   ├── dialog.zsh          # 后台对话框 + Follow Up 处理器
│   └── retry.py            # 退避重试与 Retry-After 工具
├── tests/
│   ├── test_parse_response.py
│   └── test_load_pool.py
└── README.md
```

## 调试

所有运行时元数据写在 `~/Library/Logs/AIReplyPopClip/`：

| 文件 | 内容 |
|------|------|
| `last_request.txt` | 时间、endpoint、masked key、model |
| `last_headers.txt` | HTTP 响应头 |
| `last_body.txt` | 原始响应 body |
| `last_http_status.txt` | HTTP 状态码 |
| `last_curl_stderr.txt` | curl stderr |
| `last_reply.txt` | 生成的回复 |
| `last_error.txt` | 错误分类（仅出错时） |
| `history.jsonl` | 启用 Save History 后追加 |

错误对话框上的 **Open Debug Folder** 按钮会直接打开这个目录。

> **隐私提醒**：调试日志可能包含邮件正文和模型输出。建议定期清理或保持 `Save History` 关闭。错误对话框会提示调试目录的位置。

## 错误处理

按消息内容分类（auth / quota / config / network / server / model / response / api / input / permission），每类配独立的中文提示与建议。详见 `lib/parse_response.py` 与 `reply.zsh:error_exit`。

## 隐私

- API Key 在设置中为 `secret` 类型，存入 macOS 钥匙串，不在磁盘写明文。
- `Save History` 默认关闭。开启后建议定期清理 `history.jsonl`，历史文件权限为 `600`。
- Session 临时文件（`dialog.zsh` 用）写后立即删除，权限 `600`。
- 调试目录不自动清理，需手动或在错误对话框点击打开后自行管理。

## 安全提示

把 API key 当作密码处理。如果不慎粘贴到聊天 / 公开仓库，应立即重置。建议优先使用 `API Key File` 而非 PopClip 设置里的字段，且文件权限设为 `600`。
