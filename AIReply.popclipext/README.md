# AI Reply (PopClip Extension)

选中邮件正文，点 PopClip 工具栏里的 **AI Reply** 按钮，扩展会调用一个 OpenAI 兼容的 chat-completions 接口生成可直接发送的回复。

支持风格预设、Follow Up 改写、API Key Pool 智能容错、按源语言回复等。

## 安装

1. 双击 `AIReply.popclipext` 安装。
2. 在 PopClip 设置中至少配置：
   - `Endpoint`（默认 `https://api.openai.com/v1`）
   - `Model`（默认 `gpt-4o-mini`）
   - `API Key`，或把密钥写入 `~/.config/popclip-aireply/api_key`（推荐）

> 修改扩展内的文件后，需要再次双击 `AIReply.popclipext` 让 PopClip 重新加载。

## 使用

1. 在邮件客户端、Web 邮箱或任意文本里**选中**正文。
2. 点 PopClip 工具栏里的 **AI Reply**。
3. 弹出的对话框可输入补充要求（可留空），点对应风格按钮生成：
   - **正式 Professional** — 正式商务语气（默认）
   - **友好 Friendly** — 友好亲切
   - **简洁 Concise** — 言简意赅
4. 结果对话框：
   - **OK** 关闭（默认已复制到剪贴板）。
   - **Copy** 复制当前文本（可编辑后再复制）。
   - **Follow Up** 让 AI 基于当前草稿继续改写。可无限次。

## API Key 配置

按优先级从高到低读取：

1. PopClip 设置里的 `API Key` 字段。
2. 环境变量 `AI_REPLY_API_KEY`（在 PopClip 启动前 export 才有效）。
3. `API Key File` 指向的文件首个非空行。默认 `~/.config/popclip-aireply/api_key`。

```bash
mkdir -p ~/.config/popclip-aireply
printf '%s\n' 'YOUR_KEY_HERE' > ~/.config/popclip-aireply/api_key
chmod 600 ~/.config/popclip-aireply/api_key
```

## API Key Pool（负载均衡 & 容错）

如果你有多个 key（同一家或多家），可以配成一个 Pool。每次调用随机选一个；当某个 key 遇到 **429 / 5xx / 网络错误** 时，会自动切换到下一个 key 重试。**401 / 403 / 404 / 400 等永久错误不会跨 key 重试**——这能避免一个坏 key 把整个 Pool 都试一遍。

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

## 风格 / 语言

- **默认风格** 在设置里选择，每次调用时仍可临时切换。
- **取消"每次提示"** （`Prompt Before Each Reply` 关掉）后，会用默认风格直接生成，无对话框。
- **按源语言回复** 开启后，模型会自动匹配邮件语言（不限中英，支持任意语言）。
- **语言徽章** 仅作 UI 提示，由本地基于 Unicode 区段的简易检测得出。

## 文件结构

```
AIReply.popclipext/
├── Config.json            # PopClip 扩展配置（UI、选项）
├── reply.zsh              # 入口脚本（编排）
├── lib/
│   ├── build_payload.py   # 构造 chat-completions 请求体
│   ├── parse_response.py  # 解析模型响应 / 错误
│   ├── load_pool.py       # 读取 / 校验 Key Pool
│   ├── detect_language.py # 邮件语言检测（仅用于徽章）
│   └── append_history.py  # 历史记录写入
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

## 错误处理

按消息内容分类（auth / quota / config / network / server / model / response / api / input / permission），每类配独立的中文提示与建议。详见 `lib/parse_response.py` 与 `reply.zsh:error_exit`。

## 安全提示

把 API key 当作密码处理。如果不慎粘贴到聊天 / 公开仓库，应立即重置。建议优先使用 `API Key File` 而非 PopClip 设置里的明文字段，且文件权限设为 `600`。
