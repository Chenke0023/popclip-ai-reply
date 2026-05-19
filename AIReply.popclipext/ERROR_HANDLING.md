错误分类和友好提示
此更新改进了 PopClip 插件的错误处理机制，提供更友好和针对性的错误提示。

错误类型及示例
1. 认证错误
  - 原因：API Key 无效、过期或格式错误
  - 示例消息：
    - HTTP 401: Unauthorized
    - API Error: Invalid API key
    - Missing API key
    - Authentication failed
  - 建议：
    - 检查 API Key 设置中的拼写错误或多余空格
    - 确认 API Key 有效且未过期
    - 如需要，重新生成 API Key

2. 配额/计费错误
  - 原因：API 额度不足或请求过多、计费问题
  - 示例消息：
    - HTTP 429: Rate limit exceeded
    - API Error: quota exceeded
    - insufficient_quota
  - 建议：
    - 稍等片刻后重试
    - 检查账户余额
    - 升级计划以获取更高限额

3. 配置错误
  - 原因：Endpoint URL 或其他配置设置不正确
  - 示例消息：
    - HTTP 404: Not Found
    - Missing endpoint
  - 建议：
    - 验证 Endpoint URL 设置
    - 应为有效的 base URL（例如：https://api.openai.com/v1）
    - 首选不使用尾部斜杠

4. 网络错误
  - 原因：连接超时、网络连接问题
  - 示例消息：
    - Error: Connection timeout
    - Error: Timed out waiting for response
  - 建议：
    - 检查互联网连接
    - VPN 可能会导致问题，尝试暂时禁用
    - 检查端点是否可访问

5. 服务器错误
  - 原因：API 服务出现问题
  - 示例消息：
    - HTTP 500: Internal Server Error
    - HTTP 502: Bad Gateway
    - HTTP 503: Service Unavailable
  - 建议：
    - 通常是临时性问题，请稍后重试
    - 如果问题持续存在，请检查服务状态页面

6. 模型错误
  - 原因：选定的模型不存在或不可用
  - 示例消息：
    - Error: Model gpt-5 not found
    - Invalid model name
  - 建议：
    - 选定的模型可能不存在或不可用
    - 尝试在设置中使用不同模型
    - 检查模型名称是否正确对应至提供方

7. 输入错误
  - 原因：未选择文本输入
  - 示例消息：
    - No input text selected
  - 建议：
    - 首先选择一些文本，然后点击 AI Reply 按钮

8. 权限错误
  - 原因：API Key 访问权限不足
  - 示例消息：
    - HTTP 403: Forbidden
  - 建议：
    - API Key 无权访问此模型
    - 验证订阅计划是否支持此模型
    - 尝试使用不同的模型

9. 响应错误
  - 原因：服务器返回无效或空的响应
  - 示例消息：
    - Empty response body from server
    - Empty model output
  - 建议：
    - 请求可能被拒绝
    - 尝试使用不同的提示词或模型
    - 检查错误日志以了解详情

10. API 错误
  - 原因：API 返回无效的响应格式
  - 示例消息：
    - Error: Failed to parse JSON response
  - 建议：
    - 端点可能不兼容
    - 检查是否使用了正确的 API 格式（OpenAI 兼容）

实现细节
- 使用不区分大小写的模式匹配
- 具体的模式优先，确保正确的分类
- 每种错误类型都配有特定的图标和说明
- 错误信息存储在 ~/Library/Logs/AIReplyPopClip/last_error.txt 中
- 改进的错误对话框，便于打开调试文件夹

测试
- 包含 21 个测试用例，覆盖各种错误场景
- 测试验证错误分类和预期建议的一致性
