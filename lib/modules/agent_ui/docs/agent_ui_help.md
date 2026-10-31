# AI 助手使用指南

## 1. 整体结构

「源影」的 AI 能力由三部分组成：

| 组件 | 位置 | 作用 |
|---|---|---|
| AI 设置页 | 设置 → AI 助手 | 保存 API 基址、Key、模型名 |
| agent-ui 页面 | 插件中心安装「AI 助手界面」后可用 | 对话界面（NextChat） |
| AI 网关 APK | 应用市场安装（aigw / raccoon / zhipu-gw） | 在本机提供 OpenAI 兼容接口 |

数据流：
AI 设置页（Hive 存参）
│ 打开 agent-ui 时自动注入 localStorage('app-config')
▼
agent-ui 页面（NextChat）──HTTP──▶ AI 网关 APK（127.0.0.1:端口/v1）──▶ 上游 AI


## 2. 使用步骤

### 2.1 安装 agent-ui 插件

设置 → 插件中心 → 市场 → 搜索「AI 助手界面」→ 安装。

### 2.2 配置 AI 参数（二选一）

**方式 A：直连公开 API**

1. 设置 → AI 助手
2. API 基址：`https://api.openai.com/v1`
3. API Key：你的 Key
4. 模型：`gpt-4o-mini`（或你账号可用的）
5. 点「测试连接」确认可用
6. 点「保存」

**方式 B：使用本地 AI 网关**

1. 安装一个网关 APK（推荐先试 `zhipu-gw`）
2. 打开网关 APK，按提示登录上游账号，启动监听
3. 记下端口和模型名（网关界面会显示）
4. 设置 → AI 助手
5. 点 API 基址右侧的「雷达」按钮自动探测（或手动填 `http://127.0.0.1:端口/v1`）
6. API Key：网关给的（免鉴权填 `sk-local`）
7. 模型：从网关界面复制（如 `zhipu/glm-4`）
8. 点「测试连接」→「保存」

### 2.3 打开 AI 助手

设置 → AI 助手 → 点顶部「打开 AI 助手」。

配置会自动注入，无需在页面内再填。如果页面顶部出现登录/配置提示，说明注入失败，检查：

- 设置页是否已保存（基址和 Key 都非空）
- agent 插件是否已安装
- 点右上角刷新按钮重试

## 3. 常见问题

**Q：设置页填了，AI 页面还要再填吗？**
A：不需要。打开 AI 页面时会自动注入。如果页面里还是旧配置，点右上角刷新。

**Q：三个网关 APK 有什么区别？**

| 网关 | 特点 |
|---|---|
| `aigw` | 聚合多家上游（Trae、WorkBuddy 等），模型名带前缀 |
| `raccoon` | 小浣熊本地网关，绑定 127.0.0.1 |
| `zhipu-gw` | 专供智谱清言，包体最小，最稳定 |

**Q：对话报错怎么办？**

1. 浏览器访问 `http://127.0.0.1:端口/v1/models`，看是否有 JSON（没有 = 网关没启动/端口不对）
2. 模型名是否从网关界面复制（不要猜）
3. 网关是否需要 Key，是否填对
4. 设置页「测试连接」是否通过

**Q：不想装网关 APK 能用吗？**
A：能，用方式 A 直连公开 API。

**Q：注入的配置存在哪？**
A：NextChat 的 `localStorage['app-config']`，key 是 Zustand persist 的 `name` 字段。关键字段：`openaiUrl`、`openaiApiKey`、`useCustomConfig: true`、`modelConfig.model`。

**Q：NextChat 升级后注入失效怎么办？**
A：注入依赖 NextChat 内部存储结构。升级后如果字段名变化，需要更新 `AgentUiPage._buildInjectScript` 里的 patch 字段。当前 v2.15.8 已验证可用。