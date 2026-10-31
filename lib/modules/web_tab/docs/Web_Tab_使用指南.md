# Web Tab 使用指南

> **版本**：v1.0 · 最后更新：2026-10
> **适用版本**：源影 v2.0.8+
> **读者对象**：源作者（编写 HTML 源 / Web 源）

Web Tab 是源影内置的「可编程浏览器 Tab」。你可以上传自定义 HTML 页面或 Web 增强脚本，作为**第三方源**在壳子内运行，并通过 `ds` / `fm` 桥接调用原生能力。

---

## 目录

1. [概览](#一概览)
2. [文件结构](#二文件结构)
3. [桥接 API 完整参考](#三桥接-api-完整参考)
4. [自动嗅探机制](#四自动嗅探机制)
5. [`openVod` 数据格式](#五openvod-数据格式)
6. [HTML 源写法](#六html-源写法)
7. [Web 源写法](#七web-源写法)
8. [完整示例](#八完整示例)
9. [平台差异与限制](#九平台差异与限制)
10. [常见问题](#十常见问题)
11. [附录 A：API 速查表](#附录-a桥接-api-速查表)
12. [附录 B：媒体格式白名单](#附录-b媒体格式白名单)
13. [附录 C：网盘域名白名单](#附录-c网盘域名白名单)

---

## 一、概览

### 1.1 什么是 Web Tab

Web Tab 位于底部导航栏，行为类似浏览器，但额外注入了壳子的桥接脚本。用户可以：

- 浏览任意普通网页
- 加载自定义 HTML 页面（作为源）
- 加载 `.web.json + .js` 组合的增强源
- 让页面内的增强脚本通过 `ds.*` 与壳子交互
- 自动嗅探页面内的视频资源
- 自动检测页面内的网盘链接

### 1.2 两种源形态

| 类型 | 文件 | 用途 |
|------|------|------|
| **HTML 源** | `xxx.html`（可配 `xxx.js`） | 纯本地页面，配合 `ds.*` 桥接或 JS 增强 |
| **Web 源** | `xxx.web.json` + `xxx.js` | 加载远程页面（`homePage`），注入 `.js` 增强脚本 |

两者上传后都出现在「Web Tab 源列表」中，可像切换普通源一样切换。

### 1.3 源的存放位置

统一放在壳子数据目录下的 `spider/html/` 子目录：

```
<ApplicationSupportDirectory>/spider/html/
├── my_page.html        # HTML 源
├── my_page.js          # HTML 源的配套增强（可选）
├── target.web.json     # Web 源元信息
└── target.js           # Web 源的增强脚本（可选）
```

各平台的根目录：

| 平台 | `ApplicationSupportDirectory` |
|------|------------------------------|
| Windows | `%APPDATA%/com.example/yuanying/` |
| Android | `/data/data/<pkg>/files/` |
| iOS | `~/Library/Application Support/` |

---

## 二、文件结构

### 2.1 HTML 源

```
my_source.html   （必需）
my_source.js     （可选，同名配套）
```

**加载逻辑**：

1. 加载 `file:///.../my_source.html`
2. 若存在 `my_source.js`，在 `onLoadStop` 时注入执行

**适用场景**：

- 完全自定义的 Web UI（本地页面，无需远程访问）
- 轻量页面 + 桥接能力，如搜索面板、书签管理
- 配合 `ds.openVod` 做自定义影视推荐

### 2.2 Web 源

```
target.web.json   （必需）
target.js         （可选，同名配套）
```

**`.web.json` 格式**：

```json
{
  "name": "示例源",
  "api": "web://https://example.com/",
  "ext": ""
}
```

| 字段 | 必需 | 说明 |
|------|------|------|
| `name` | ✅ | 显示名，出现在源列表与切换弹窗 |
| `api` | ✅ | `web://` 前缀 + 目标 URL（即 `homePage`） |
| `ext` | ❌ | 自定义扩展数据，原样保留；当前实现不会主动读取，供未来使用 |

**加载逻辑**：

1. 剥掉 `web://` 前缀得到 `homePage`
2. WebView 加载 `homePage`
3. 若存在 `target.js`，在 `onLoadStop` 时注入执行

**适用场景**：

- 目标站点本身是完整 Web 应用（如 `wbbb1.com`）
- 增强脚本只负责在页面里注入「用源影播放」按钮、监听 DOM 事件
- 用户在原站点操作，选中后通过 `ds.openVod` 回推壳子

---

## 三、桥接 API 完整参考

所有桥接方法挂在 `window.ds` 上，`window.fm` 是其等价别名（DSPlayer 兼容）。

### 3.1 环境信息：`ds.env`（同步）

```js
// ds.env 的结构
{
  version: '2.0.8',
  platform: 'android' | 'ios' | 'windows' | 'macos' | 'linux',
  isTv: false,
  isMobile: true,
  gwPort: 5575,          // MediaProxy 本地端口
  safeInsets: { top, bottom, left, right },
  theme: { mode: 'dark' | 'light', isDark: bool, primary: '#RRGGBB' }
}
```

用途：页面按平台 / 主题自适应；`gwPort` 供 `ds.res()` 生成代理 URL。

### 3.2 网络请求

#### `ds.req(url, opts)` — 无 CORS 限制的 HTTP 请求（异步）

```js
const resp = await ds.req('https://api.example.com/data', {
  method: 'GET',       // 'GET' | 'POST'
  headers: { 'User-Agent': '...' },
  data: { /* 对象 */ } || 'form_string',
  responseType: 'json', // 'json' | 'text' | 'bytes'
  timeout: 20,          // 秒
});

// resp 结构
{
  status: 200,
  ok: true,
  url: 'https://...',
  body: /* 由 responseType 决定 */,
  headers: { /* 响应头 */ },
  cookies: [ /* ... */ ]
}
```

核心优势：走 Dart 原生栈（`HttpClientFactory.dio`），**没有浏览器 CORS 限制**，可请求任意跨域接口。典型用途是调用目标站 API、解析第三方 JSON 接口，再配合 `ds.openVod` 构造多集数据。

#### `ds.res(url, opts)` — 防盗链图片代理（同步）

```js
const proxyUrl = ds.res('https://i0.hdslb.com/bfs/xxx.jpg', {
  headers: { Referer: 'https://www.bilibili.com/' }
});
// 返回：http://127.0.0.1:5575/webResource?url=...&headers=...
```

可直接塞进 `<img src>`：

```html
<img id="cover">
<script>
  document.getElementById('cover').src = ds.res(coverUrl, {
    headers: { Referer: 'https://example.com/' }
  });
</script>
```

> ⚠️ `ds.res` **只生成代理 URL，不下载资源**。实际加载由 WebView 内的 `<img>` / `<video>` 触发，MediaProxy 再转发并补上请求头。

### 3.3 UI 控制

```js
ds.toast('消息');              // 原生 Toast
ds.fullscreen(true);           // 全屏：隐藏顶部栏，右下角显示退出按钮
ds.tab('home');                // 切换底部 Tab：home / live / search / web / setting / ...
ds.back();                     // WebView 后退；无历史则关闭页面
ds.reload();                   // 重载当前页
```

### 3.4 打开详情页 / 播放

#### `ds.openVod(vod)` — 打开原生详情页（核心接口，异步）

```js
await ds.openVod({
  vod_id: 'unique_id',
  vod_name: '视频名',
  vod_pic: 'https://.../cover.jpg',
  vod_content: '简介',
  vod_remarks: '共 12 集',
  // ...详见第五章
});
```

跳转后 UI、播放顺序、进度、历史记录与普通源完全一致。`ds.vodInline(vod)` 是其 DSPlayer 兼容别名，功能等价。

#### `ds.play(url, title)` — 直接播放直链（异步）

```js
await ds.play('https://xxx.m3u8', '直链播放');
```

前提：`url` 必须是 `.m3u8` / `.mp4` / `.flv` / `.mpd` 等媒体格式，非直链会被 media_kit 拒绝。

### 3.5 打开内置页面

```js
ds.openLive();          // 切换到直播 Tab
ds.openKeep();          // 打开历史记录页
ds.openSetting();       // 打开设置页

// 搜索
ds.search('关键词', { direct: true });
// direct: false → 跳搜索页（关键词可编辑）
// direct: true  → 直接展示搜索结果
```

#### `ds.vod(siteKey, vodId, name, pic)` — 按源打开详情（异步）

```js
await ds.vod('t4_site_key', '12345', '视频名', 'cover.jpg');
```

用途：已知某内置源的视频 ID，从 Web Tab 直接跳到该源详情页，适合外部跳转播放。

### 3.6 事件系统

```js
const off = ds.on('dstheme', (data) => {
  console.log('主题：', data.theme);
  document.body.classList.toggle('dark', data.theme.isDark);
});

// 用完注销
off();
```

| 事件名 | 触发时机 | 载荷 |
|--------|----------|------|
| `dstheme` | 应用主题切换 | `{ theme: { mode, isDark, primary } }` |
| `dsviewport` | 视口 / 键盘变化 | `{ width, height, keyboardBottom, ... }` |
| `fmpause` | 应用进入后台 | `{}` |
| `fmresume` | 应用恢复前台 | `{ pausedMs: number }` |
| `fmurlchange` | 页面 URL 变化（`pushState`） | `{ url: string }` |

### 3.7 持久化存储

```js
// 每个 ns 对应独立 Hive box，互不干扰
await ds.store.set('key', 'value', 'myns');
const v = await ds.store.get('key', 'myns');
await ds.store.del('key', 'myns');
```

- 默认命名空间 `'default'`，对应 Hive box `web_ds_default`
- 建议用**源名**作 ns，避免源之间冲突，例如 `ds.store.set('token', x, 'wbbb1')`

### 3.8 信息查询（均为异步）

```js
const device  = await ds.device();
// { uuid, name, ip, type, serial, eth, wlan, time }
// 隐私说明：serial / eth / wlan 恒为空字符串

const site    = await ds.site();
// { key, name, homePage, type, header }

const config  = await ds.config();
// { id: 'yuanying', url: '', desc: '源影', driveCheck: false }

const history = await ds.history();
// [{ key, vodName, vodPic, vodRemarks, vodFlag, createTime, ... }]

const viewport = await ds.viewport();
// { width, height, safeInsets, keyboardBottom, chromeMode, ... }
```

### 3.9 播放器状态（stub，仅兼容）

```js
await ds.stat();              // { state: 'idle', speed: 0, ... } 恒为初始值
await ds.ctrl('pause');       // { ok: true, noop: true }
await ds.preloadArtwork();    // true
```

> 当前壳子**不实现**真实的播放器状态注入，以上均返回 stub 值。如需当前播放状态，改用 `ds.history()` 等桥接方法。

### 3.10 网盘

```js
// 检查（当前恒返回 unsupported）
const result = await ds.pan.check([{ type: 'quark', url: '...' }]);

// 推送播放：交给 push_agent 源处理
await ds.pan.play({
  type: 'http',   // 或 'quark' / 'baidu' / 'ali' / ...
  url: 'https://...',
  title: '视频名'
});

// 短别名，等价 ds.pan.play
await ds.check({ /* ... */ });
```

规则：

- `type: 'http'` → 走 `ds.play` 直接播放
- 网盘类型 → 构造 `push://` 交给 `push_agent` 源处理
- `push_agent` 识别条件：`type == 4 && (key == 'push_agent' || name.includes('push_agent'))`

### 3.11 UI 分组（DSPlayer 兼容）

```js
ds.ui.getViewport();     // 等价 ds.viewport()
ds.ui.restoreChrome();   // Promise.resolve(true)
ds.ui.setToolbar(true);  // Promise.resolve(true)
```

### 3.12 扩展分组

```js
ds.ext.info();
// { siteKey, siteName, homePage, enabled, matched, ready }

ds.ext.log('消息', { data });   // 输出到控制台 / logcat
ds.ext.toast('消息');            // 等价 ds.toast
```

### 3.13 自定义解析钩子 `window.__dsResolver`（可选）

源作者可在页面上定义该函数，壳子在需要时主动调用：

```js
window.__dsResolver = async function (ep) {
  // ep = { url: '详情页 URL' }
  // 返回 { url: '真实 m3u8 URL', headers: {...} } | null
  const realUrl = await parsePage(ep.url);
  return { url: realUrl, headers: { Referer: location.href } };
};
```

**触发时机**：`ds.openVod` 传入的 `episode.url` 不是媒体直链（比如是详情页 URL）时，壳子播放前会：

1. 调用 `window.__dsResolver({ url })`
2. 拿到返回值后播放

**特殊返回值**：返回 `webview://xxx` 表示「我解析不了，请壳子嗅探」：

```js
return { url: 'webview://' + ep.url };
```

壳子会用 `ResourceSniffer` 打开该页面并拦截真实媒体 URL（**Android / iOS 有效，Windows 不支持**）。

---

## 四、自动嗅探机制

嗅探由壳子内置完成，源作者**无需额外实现**。嗅探到的媒体会显示在右下角「▶」按钮的列表里。

### 4.1 多层嗅探

| 层 | 机制 | 平台 | 覆盖场景 |
|----|------|------|----------|
| 1 | `PerformanceObserver`（buffered） | 全平台 | 所有 HTTP(S) 请求，含脚本注入前的历史资源 |
| 2 | DOM 扫描 `<video>` / `<source>` / `<link rel=preload>` | 全平台 | 直接持有 URL 的 video 元素 |
| 3 | `HTMLMediaElement.prototype.play/load` Hook | 全平台 | 用户点击播放、autoplay |
| 4 | `src` 属性 setter Hook | 全平台 | `video.src = url` 直接赋值 |
| 5 | `fetch` / XHR Hook | 全平台 | 通过 JS 加载的 m3u8 / JSON |
| 6 | `MutationObserver` | 全平台 | 动态创建的 video 元素 |
| 7 | `onLoadResource` | Android / iOS | 平台原生拦截（**Windows 不工作**） |

### 4.2 网盘链接自动检测

壳子每 **3 秒**扫描一次页面，匹配以下来源：

- `<a href>` 元素
- `document.body.innerText` 正则
- `TreeWalker` 遍历文本节点（捕获纯文本链接）

提取码识别正则：

```
(?:提取码|密码|pwd)[\s:：=]*([a-zA-Z0-9]{4})
```

覆盖域名见[附录 C](#附录-c网盘域名白名单)。

### 4.3 未覆盖的场景

| 场景 | 原因 | 解决 |
|------|------|------|
| `blob:` URL（MSE 流） | 无对应 HTTP URL | 需 Hook `MediaSource`，当前不支持 |
| iframe 内的资源（跨域） | Windows 下 `forMainFrameOnly: false` 可能失效 | 主框架内嗅探 + 源作者主动调用 `ds.play` |
| 页面加载前的非 HTTP 资源 | 无 HTTP 请求可拦截 | 无法嗅探 |

### 4.4 源作者主动上报

自动嗅探失败时，可手动上报：

```js
// 直接播放
ds.play('https://xxx.m3u8', '视频名');

// 或推给详情页
ds.openVod({
  title: '视频名',
  episodes: [{ name: '正片', url: 'https://xxx.m3u8' }]
});
```

---

## 五、`openVod` 数据格式

`ds.openVod` 支持 3 种输入格式，任选其一。

### 5.1 格式 A：顶层 `episodes`（最简）

```js
ds.openVod({
  title: '视频名',
  vod_pic: 'https://.../cover.jpg',
  episodes: [
    { name: '第1集', url: 'https://xxx.m3u8' },
    { name: '第2集', url: 'https://yyy.m3u8' },
  ],
});
```

适用：单集或单线路的短视频、直链资源。

### 5.2 格式 B：`lines` 多线路（推荐）

```js
ds.openVod({
  vod_id: 'xxx',
  vod_name: '视频名',
  vod_pic: 'https://.../cover.jpg',
  vod_remarks: '共 12 集',
  vod_content: '简介...',
  vod_actor: '主演',
  vod_director: '导演',
  vod_year: '2024',
  vod_area: '中国',
  mark: '第1集',   // 预选该集
  lines: [
    {
      name: '线路1',
      episodes: [
        { name: '第1集', url: 'https://xxx.m3u8' },
        { name: '第2集', url: 'https://yyy.m3u8' },
      ],
    },
    {
      name: '线路2',
      episodes: [ /* ... */ ],
    },
  ],
});
```

适用：多线路多集的完整影视资源。

### 5.3 格式 C：DSPlayer 原生格式

```js
ds.openVod({
  vod_id: 'xxx',
  vod_name: '视频名',
  vod_play_from: '线路1$$$线路2',
  vod_play_url: '第1集$https://xxx.m3u8#第2集$https://yyy.m3u8$$$第1集$https://zzz.m3u8',
});
```

适用：从 DSPlayer 生态移植的现有脚本。

### 5.4 `episode.url` 的处理规则

| url 类型 | 示例 | 处理方式 |
|----------|------|----------|
| 媒体直链 | `https://xxx.m3u8` | 直接播放 ✅ |
| 详情页 URL | `https://target.com/vplay/123.html` | 先尝试 `__dsResolver` → 再嗅探 |
| `webview://` 前缀 | `webview://https://target.com/xxx` | 交给嗅探器取真实媒体 |

> **推荐**：优先提供媒体直链，性能最好、兼容性最广。只有在无法直接拿到直链时才用 `__dsResolver`。

---

## 六、HTML 源写法

### 6.1 最小示例

文件：`spider/html/demo.html`

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>Demo</title>
</head>
<body>
  <h1>Demo 页面</h1>
  <button onclick="play()">播放测试视频</button>

  <script>
    async function play() {
      if (!window.ds) {
        alert('桥接未就绪');
        return;
      }
      await ds.play(
        'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
        '测试直链'
      );
    }
  </script>
</body>
</html>
```

点击后跳转原生详情页并播放该 m3u8。

### 6.2 配套 `demo.js`（可选）

文件：`spider/html/demo.js`（自动注入，在 `demo.html` 加载完成后执行）

```js
// 自动注入，demo.html 加载完成后执行
console.log('注入成功，主题：', ds.env.theme);

// 监听主题变化
ds.on('dstheme', (data) => {
  document.body.style.background = data.theme.isDark ? '#000' : '#fff';
});

// 按平台做适配
if (window.ds && ds.env.isMobile) {
  console.log('移动端模式');
}
```

### 6.3 带桥接检测的稳妥写法

`ds` 在 `onLoadStop` 时**可能尚未注入**（取决于 `addUserScript` 时机），建议加一个等待：

```js
function waitForBridge(maxTries = 30) {
  return new Promise((resolve, reject) => {
    let tries = 0;
    const check = () => {
      if (window.ds && window.ds.ready) {
        resolve();
      } else if (++tries > maxTries) {
        reject(new Error('桥接超时'));
      } else {
        setTimeout(check, 200);
      }
    };
    check();
  });
}

document.addEventListener('DOMContentLoaded', async () => {
  try {
    await waitForBridge();
    init();   // 桥接就绪，开始使用 ds.*
  } catch (e) {
    console.error(e);
  }
});
```

---

## 七、Web 源写法

### 7.1 `.web.json` 示例

文件：`spider/html/mysite.web.json`

```json
{
  "name": "我的站点",
  "api": "web://https://example.com/",
  "ext": ""
}
```

### 7.2 `.js` 增强脚本示例（完整模板）

文件：`spider/html/mysite.js`

```js
(function () {
  'use strict';

  // ===== 幂等守卫：每次 onLoadStop 都会注入，必须防重复 =====
  if (window.__mySiteBooster) return;
  window.__mySiteBooster = 1;

  // ============ 工具函数 ============

  function log(msg) {
    try { console.log('[mySite] ' + msg); } catch (e) {}
  }

  function absUrl(u) {
    if (!u) return '';
    if (u.indexOf('//') === 0) return 'https:' + u;
    if (u.charAt(0) === '/') return location.origin + u;
    return u;
  }

  // ============ 详情页数据提取（按目标站 DOM 调整） ============

  function extractDetail() {
    const titleEl = document.querySelector('h1.video-title');
    if (!titleEl) return null;

    const title = titleEl.textContent.trim();
    const cover = document.querySelector('.video-cover img')?.src || '';

    const episodes = [];
    document.querySelectorAll('.episode-item a').forEach((a) => {
      const name = a.textContent.trim();
      const href = absUrl(a.getAttribute('href'));
      if (name && href) episodes.push({ name, url: href });
    });

    return { title, cover, episodes };
  }

  // ============ 注入「用源影播放」按钮 ============

  function injectPlayButton() {
    if (!/\/detail\//.test(location.pathname)) return;   // 只在详情页注入
    if (document.getElementById('__myPlayFab')) return;  // 已注入则跳过

    const detail = extractDetail();
    if (!detail || detail.episodes.length === 0) return;

    const btn = document.createElement('div');
    btn.id = '__myPlayFab';
    btn.textContent = '▶ 用源影播放';
    btn.style.cssText = `
      position: fixed;
      right: 14px;
      bottom: 96px;
      z-index: 2147483647;
      padding: 10px 16px;
      border-radius: 24px;
      cursor: pointer;
      background: linear-gradient(135deg, #FF512F, #FF9A3D);
      color: #fff;
      font: 700 13px/1 -apple-system, sans-serif;
      box-shadow: 0 6px 18px rgba(255, 81, 47, 0.45);
      user-select: none;
    `;

    btn.onclick = () => pushToShell(detail);
    document.body.appendChild(btn);
    log('按钮已注入');
  }

  // ============ 推送到壳子 ============

  async function pushToShell(detail) {
    try {
      await ds.openVod({
        vod_name: detail.title,
        vod_pic: detail.cover,
        mark: detail.episodes[0]?.name || '',
        lines: [
          { name: '默认线路', episodes: detail.episodes },
        ],
      });
      ds.toast('已推送到源影');
    } catch (e) {
      log('推送失败：' + e);
      ds.toast('推送失败');
    }
  }

  // ============ 自定义解析器（可选） ============

  window.__dsResolver = async function (ep) {
    // ep.url 是详情页 URL，尝试 fetch 出真实 m3u8
    try {
      const resp = await fetch(ep.url, { credentials: 'include' });
      const html = await resp.text();
      const match = html.match(/https?:\/\/[^"'\s]+\.m3u8[^"'\s]*/);
      if (match) {
        return { url: match[0], headers: { Referer: location.href } };
      }
      return null;
    } catch (e) {
      return null;
    }
  };

  // ============ 启动 ============

  function boot() {
    try { injectPlayButton(); }
    catch (e) { log('注入失败：' + e); }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', boot);
  } else {
    boot();
  }

  // SPA 路由兜底：URL 变化时重新注入
  let lastPath = location.pathname;
  setInterval(() => {
    if (location.pathname !== lastPath) {
      lastPath = location.pathname;
      boot();
    }
  }, 800);
})();
```

**要点回顾**：

- 用 `window.__xxx` 守卫保证幂等
- 用 `location.pathname` 判断当前是否是详情页
- 用 `setInterval` 兜底 SPA 路由切换
- 用 `ds.openVod` + `lines` 把剧集推给壳子

---

## 八、完整示例

### 8.1 示例 1：搜索面板（HTML 源）

文件：`spider/html/search_panel.html`

```html
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>搜索</title>
  <style>
    body { font-family: -apple-system, sans-serif; padding: 20px; }
    input { width: 100%; padding: 12px; font-size: 16px; box-sizing: border-box; }
    button { margin-top: 12px; width: 100%; padding: 12px; font-size: 16px; }
    .result { padding: 8px; border-bottom: 1px solid #eee; cursor: pointer; }
  </style>
</head>
<body>
  <input id="kw" placeholder="输入搜索关键词">
  <button onclick="doSearch()">搜索</button>
  <div id="results"></div>

  <script>
    async function doSearch() {
      const kw = document.getElementById('kw').value.trim();
      if (!kw) return;
      // 直接跳壳子的搜索结果页
      await ds.search(kw, { direct: true });
    }
  </script>
</body>
</html>
```

### 8.2 示例 2：视频直链嗅探器（Web 源）

文件：`spider/html/video_hunter.web.json`

```json
{
  "name": "直链嗅探器",
  "api": "web://https://some-video-site.com/",
  "ext": ""
}
```

文件：`spider/html/video_hunter.js`

```js
(function () {
  if (window.__hunter) return;
  window.__hunter = 1;

  // 每 2 秒扫描一次页面内的 video 元素
  setInterval(() => {
    document.querySelectorAll('video[src]').forEach((v) => {
      const src = v.src;
      if (src && src.startsWith('http') && !v.dataset.reported) {
        v.dataset.reported = '1';
        ds.toast('检测到直链：' + src.slice(0, 50));
        ds.play(src, document.title || '视频');
      }
    });
  }, 2000);
})();
```

### 8.3 示例 3：完整影视源

即第七章的 `mysite.web.json` + `mysite.js` 组合，覆盖「详情页解析 → 注入按钮 → 多线路推送」的完整链路。

---

## 九、平台差异与限制

### 9.1 Windows WebView2 限制

| 能力 | Android / iOS | Windows |
|------|:---:|:---:|
| `onLoadResource` 原生拦截 | ✅ | ❌ 不触发 |
| `ResourceSniffer` 嗅探 | ✅ | ❌ 不支持 |
| `forMainFrameOnly: false` | ✅ | ⚠️ 可能失效 |
| `crypto.subtle`（非 secure context） | ✅ | ⚠️ 可能不可用 |
| `PerformanceObserver` | ✅ | ✅ |
| JS Hook（play / fetch / XHR） | ✅ | ✅ |

**结论**：Windows 上只能依赖 **JS 层嗅探**（PerformanceObserver + 各类 Hook），不能依赖平台原生拦截。

### 9.2 iframe 场景

- `forMainFrameOnly: false` 会尝试向每个 frame 注入脚本
- 但 Windows WebView2 上 iframe 注入可能不生效
- 跨域 iframe 内无法直接访问 DOM（同源策略）

**可行方案**：

1. 在 iframe 的 `src` 页面内也注入桥接（需服务端配合）
2. 仅依赖主框架能捕获的资源
3. 让 iframe 内播放器通过 `postMessage` 把 m3u8 URL 暴露给主框架

### 9.3 `blob:` URL 场景

使用 `MediaSource` / MSE 的播放器（如 B 站、YouTube）会把媒体数据以 `blob:https://...` 喂给 `<video>`：

```js
// 浏览器里看到的 src
video.src = 'blob:https://www.bilibili.com/xxx';
```

这类 URL **没有对应的 HTTP 直链**，无法直接播放，当前不支持嗅探。替代方案：

- 目标站点若提供原始 m3u8 API，由源作者自行解析
- Hook `MediaSource` 提取数据流（实现复杂，未实现）

### 9.4 关于 `ext` 字段

`.web.json` 的 `ext` **当前不会被自动注入**到 JS 环境。需要传配置时可选：

| 方式 | 做法 |
|------|------|
| 硬编码 | 直接在 `.js` 里写常量 |
| URL 参数 | 在 `homePage` URL 加 query，`.js` 读 `location.search` |
| `ds.store` | 首次运行写入，后续读取 |

---

## 十、常见问题

### Q1：`window.ds` 是 undefined（桥接未就绪）

**原因**：`addUserScript` 注入时机可能晚于页面脚本执行。

**解决**：加等待（见 [6.3](#63-带桥接检测的稳妥写法)）

```js
function waitForBridge() {
  return new Promise((resolve) => {
    const check = () => {
      if (window.ds && window.ds.ready) resolve();
      else setTimeout(check, 100);
    };
    check();
  });
}

await waitForBridge();
// 现在可以安全使用 ds.*
```

### Q2：`.web.json` 上传后列表里看不到

- 文件名必须是 `xxx.web.json`，不能是 `xxx.json`
- 文件必须放在 `spider/html/` 目录
- 在「手动源管理」里切到「HTML」类型筛选查看
- 检查内容是否符合 `{ name, api }` 结构

### Q3：HTML 源加载后白屏

- WebView 是否真的加载成功（看顶部进度条 / 控制台日志）
- 页面是否有 JS 报错（「更多 → 查看页面源码」）
- 桥接是否注入成功（「更多 → 执行 JS」里运行 `window.ds`）

### Q4：嗅探到了但播放失败

典型日志：

```
[media_kit] videoSource: xxx
error: stream: Failed to open xxx
```

常见原因：

- URL 需要特定 `Referer` / `User-Agent`，但未传
- URL 是临时签名（约 5 分钟有效），嗅探时已经过期
- URL 是 iframe 内页面的相对路径，未拼成完整地址

**解决**：在 `__dsResolver` 里带好请求头：

```js
return {
  url: 'https://xxx.m3u8',
  headers: { Referer: location.href, 'User-Agent': navigator.userAgent }
};
```

### Q5：网盘链接检测不到

检查项：

- 链接是否在[附录 C](#附录-c网盘域名白名单)的域名列表内
- 链接是否在 iframe 里（主框架可能检测不到）

**手动触发**：

```js
ds.pan.play({
  type: 'quark',
  url: 'https://pan.quark.cn/s/xxx',
  title: '视频名'
});
```

### Q6：`ds.res()` 的图片加载失败

可能原因：

- MediaProxy 未启动（检查 `main.dart` 里 `MediaProxyServer` 是否启动）
- `headers` 里的 `Referer` 不对（需匹配目标站要求）
- 图片 URL 本身要 cookie（`ds.res` 只支持 header，不支持 cookie）

**调试**：把 `ds.res(...)` 返回的 URL 复制到浏览器直接打开，看返回内容。

### Q7：如何调试 Web 源

| 方法 | 说明 |
|------|------|
| `ds.ext.log` | `ds.ext.log('调试信息', { foo: 'bar' })`，在 logcat（Android）/ DevTools（Windows）查看 |
| 「更多 → 查看页面源码」 | 复制页面 HTML 出来分析 |
| 「更多 → 执行 JS」 | 在源影内直接执行任意 JS，看返回结果 |
| 浏览器 DevTools | 先在浏览器里跑通逻辑，再移植到 `.js` |

### Q8：`.js` 注入失败

日志：`[WebTab] 注入 js 失败: xxx`

- `.js` 是否有语法错误（可用 `node -c xxx.js` 检查）
- `.js` 是否在 `spider/html/` 且**同名**
- `.web.json` 的 `name` 与 `.js` 基名是否一致

### Q9：如何避免重复注入

`.js` 每次 `onLoadStop` 都会注入一次，幂等要自己处理：

```js
(function () {
  if (window.__mySourceInjected) return;
  window.__mySourceInjected = 1;
  // ...
})();
```

### Q10：`ds.openVod` 之后能回到 Web Tab 吗

可以。`Get.toNamed(detail)` 是把详情页 push 进路由栈，**返回键会回到 Web Tab**，且 WebView 状态由 `AutomaticKeepAliveClientMixin` 保持。

---

## 附录 A：桥接 API 速查表

| API | 同步 / 异步 | 用途 |
|-----|:---:|------|
| `ds.env` | 同步 | 环境信息 |
| `ds.req(url, opts)` | 异步 | HTTP 请求（无 CORS） |
| `ds.res(url, opts)` | 同步 | 防盗链代理 URL |
| `ds.toast(msg)` | 异步 | 原生 Toast |
| `ds.fullscreen(bool)` | 异步 | 全屏切换 |
| `ds.tab(name)` | 异步 | 切换底部 Tab |
| `ds.back()` | 异步 | 后退 / 关闭 |
| `ds.reload()` | 异步 | 重载页面 |
| `ds.openVod(vod)` | 异步 | 打开详情页（核心） |
| `ds.play(url, title)` | 异步 | 直链播放 |
| `ds.openLive()` | 异步 | 打开直播 Tab |
| `ds.openKeep()` | 异步 | 打开历史 |
| `ds.openSetting()` | 异步 | 打开设置 |
| `ds.search(kw, opts)` | 异步 | 搜索 |
| `ds.vod(siteKey, id, ...)` | 异步 | 按源打开详情 |
| `ds.on(event, cb)` | 同步 | 注册事件，返回注销函数 |
| `ds.store.get / set / del` | 异步 | Hive 持久化 |
| `ds.device()` | 异步 | 设备信息 |
| `ds.site()` | 异步 | 当前源信息 |
| `ds.config()` | 异步 | 壳子配置 |
| `ds.history()` | 异步 | 历史记录 |
| `ds.viewport()` | 异步 | 视口信息 |
| `ds.stat()` | 异步 | 播放状态（**stub**） |
| `ds.ctrl(action)` | 异步 | 播放控制（**stub**） |
| `ds.pan.play(opts)` | 异步 | 网盘推送 |
| `ds.ui.getViewport()` | 异步 | 等价 `ds.viewport()` |
| `ds.ext.info()` | 异步 | 扩展信息 |
| `ds.ext.log(msg, data)` | 同步 | 日志 |
| `window.__dsResolver(ep)` | 源作者实现 | 自定义解析钩子 |
| `window.fm` | 同步 | `ds` 别名（DSPlayer 兼容） |
| `window.fongmiBridge` | 同步 | `ds` 别名 |
| `window.fongmiClient` | 同步 | `{ mode, isLeanback }` |

---

## 附录 B：媒体格式白名单

嗅探识别的媒体扩展名：

```
.m3u8   .mp4   .flv   .mpd   .mkv   .mov   .m4v   .ts   .webm
```

无扩展名也能识别的路径特征：

```
videoplayback    /video/    /stream/
```

明确排除（不会误判为媒体）：

```
.js  .css  .png  .jpg  .jpeg  .gif  .webp  .svg  .woff  .ttf
blob:   data:
```

---

## 附录 C：网盘域名白名单

| 域名 | 网盘 |
|------|------|
| `pan.quark.cn` | 夸克网盘 |
| `pan.baidu.com` | 百度网盘 |
| `pan.xunlei.com` | 迅雷云盘 |
| `aliyundrive.com` | 阿里云盘 |
| `alipan.com` | 阿里云盘（新域名） |
| `115.com` | 115 网盘 |
| `123pan.com` | 123 云盘 |
| `cloud.189.cn` | 天翼云盘 |
| `drive.uc.cn` | UC 网盘 |

如需支持其他网盘，修改 `DsBridgeService._sniffHook` 里的 `CLOUD_REGEX` 正则即可。

---

> **文档维护**：源影团队 · **反馈渠道**：项目仓库 issue
> **版本**：v1.0（2026-10）
>
> 本文只描述**已实现**的能力：例如 `ds.stat` 明确标注为 stub、Windows 的限制单独列出，未做任何夸大。
> 后续若新增桥接 API（如 `ds.showCloudPush` / `ds.sniffedVideo`），请同步更新「第三章」与「附录 A」。
