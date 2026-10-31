# 源影 Linux 沙盒使用指南

> **适用**：源影 Android 版 · 基于 PRoot 用户态隔离 · 免 root 跑完整 Linux  
> **版本**：v1.1（对应源影 v2.0.8+，PRoot 1.0.0）｜最后更新：2026-10-30  
> **主线**：装运行时 → 装环境 → 装软件 → 注册常驻服务

---

<details>
<summary><b>📑 目录（点击展开）</b></summary>

1. [它是什么 / 能做什么](#一-它是什么)
2. [前置条件](#二-前置条件)
3. [快速开始：3 步跑起第一个服务](#三-快速开始-3-步跑起第一个服务)
4. [安装沙盒运行时（PRoot）](#四-安装沙盒运行时-proot)
5. [安装沙盒环境（Alpine / Ubuntu）](#五-安装沙盒环境-alpine--ubuntu)
6. [沙盒终端怎么用](#六-沙盒终端怎么用)
7. [常驻服务管理](#七-常驻服务管理)
8. [常见应用场景（可直接抄）](#八-常见应用场景可直接抄)
9. [常见问题排查](#九-常见问题排查)
10. [进阶技巧](#十-进阶技巧)
- [附录 A · 命令速查表](#附录-a-命令速查表)
- [附录 B · 内置镜像源一览](#附录-b-内置镜像源一览)

</details>

---

## 一、它是什么

Linux 沙盒在你的 Android 手机上跑一个**完整的 Linux 用户空间**，和宿主系统隔离：

| 特性 | 说明 |
| --- | --- |
| 🟢 免 root | 靠 PRoot 在应用私有目录里运行，不碰系统分区 |
| 📦 随便装软件 | node、python、php、ffmpeg、nginx……包管理器里有什么就有什么 |
| 🔁 可常驻 | 装好的程序能注册成后台服务，退后台、锁屏都照跑 |
| 🗑️ 随时销毁 | 卸载环境一键清空，不留残留 |

### 能用来做什么

| 场景 | 举例 |
| --- | --- |
| 跑下载器 | aria2、yt-dlp 常驻下载 |
| 跑媒体服务 | filebrowser、alist 提供网页文件管理 |
| 小程序后端 | Node / Python / PHP 写的接口、Web 服务 |
| 定时任务 | 拉 RSS、抓数据、定时备份 |
| 开发调试 | 临时验脚本、跑单元测试 |
| 看家护院 | 内网穿透客户端（frpc）、监控脚本 |

### ⚠️ 它不是什么

- **不是 Android 桌面替代品**：终端没有 TTY，`vim` / `top` / `htop` / `nano` 会乱码（[怎么办 →](#97-vim--top--htop-乱码)）
- **不是真 root**：沙盒里的 root 是 PRoot 模拟的，改不了宿主系统
- **不是跨进程遥控**：服务只在沙盒内跑，调不到 Android API

---

## 二、前置条件

| 项目 | 要求 |
| --- | --- |
| 设备 | Android 8.0+，**arm64**（2018 年后的手机基本都满足） |
| 存储 | 至少 **200MB** 空闲（Alpine ≈10MB、Ubuntu ≈100MB，装软件另算） |
| 网络 | 首次装环境要联网；国内已内置加速源，**不用自己配** |
| 权限 | 无强制要求；「所有文件访问」可选（用来挂 sdcard） |

> **🚫 不支持**：x86 模拟器（部分 PC 安卓模拟器）、32 位设备

---

## 三、快速开始：3 步跑起第一个服务

> 目标：跑一个 Node.js HTTP 服务，手机浏览器访问能看到返回。

```
① 装 PRoot 运行时  →  ② 装 Alpine  →  ③ 终端里装 Node 并注册成服务
```

### Step 1 · 装 PRoot 运行时

1. 底部导航进 **实验室** → 点 **Linux 沙盒**
2. 若顶部提示「缺少沙盒运行时」→ 点 **去插件中心安装**
3. 市场里找 **Linux 沙盒运行时（PRoot）**（作者：DsPlayer）→ **安装**
4. 回到沙盒页，依赖提示卡消失即成功（[装完还提示缺？](#43-安装后的验证)）

### Step 2 · 装 Alpine 环境

1. 沙盒页 → 环境卡 → 点 **Alpine 3.22.7（3.3MB）**
2. 等进度条走完 → 显示 **已就绪：alpine**
3. 耗时参考：4G/5G ≈10 秒，WiFi ≈30 秒

### Step 3 · 装 Node 跑起来

点 **启动终端**，逐行输入：

```sh
apk update
apk add nodejs
node -e "require('http').createServer((q,s)=>s.end('hello from sandbox')).listen(5757)"
```

浏览器打开 `http://<手机IP>:5757`，看到 `hello from sandbox` 就成了 ✅

> **注意**：这样启动时 Node 跟着终端走，终端一关进程就没了。想让它常驻，接着看 [第七章](#七-常驻服务管理)。

---

## 四、安装沙盒运行时（PRoot）

### 4.1 为什么要单独装

沙盒本身依赖 PRoot 这个用户态隔离工具，它被打包成**插件**，得先从插件市场装好，环境才能跑。

### 4.2 安装步骤

1. 打开 **实验室**（底部导航栏）
2. 找到 **Linux 沙盒** 卡片并进入
3. 顶部显示「缺少沙盒运行时」时，点 **去插件中心安装**
4. 切到插件中心 **市场** Tab，搜/找 **Linux 沙盒运行时（PRoot）**
5. 点安装 → 下载 → 自动完成

### 4.3 安装后的验证

依赖提示卡应该消失。如果还在：

- 去插件中心 **插件** Tab，看 `proot` 是不是 **已启用**
- 下拉刷新沙盒页，或直接杀掉 App 重开

### 4.4 常见坑

| 现象 | 原因 | 解决 |
| --- | --- | --- |
| 装完了还提示「缺少」 | 缓存没刷新 | 返回上一页再进，或重启 App |
| 市场里找不到 PRoot | 索引缓存旧 | 市场页右上角点 **刷新** |
| 下载中断 | 网络不稳 | 重试，或换个网络 |

---

## 五、安装沙盒环境（Alpine / Ubuntu）

### 5.1 两个发行版怎么选

> **一句话建议**：先用 Alpine 试水，不够再上 Ubuntu。两个能并存，当前跑哪个取决于「最近一次安装/重装的是谁」。

| 特性 | Alpine | Ubuntu |
| --- | --- | --- |
| 体积 | ≈10MB | ≈100MB |
| 包管理 | `apk` | `apt` |
| 软件生态 | 精简够用（Node/Python/PHP 都有） | 完整庞大（啥都有） |
| 内存占用 | 极低（50MB 起） | 中等（200MB 起） |
| 适合谁 | 大多数用户、老设备、轻量服务 | 依赖特定软件、长期开发 |

### 5.2 装 Alpine

**环境卡 → 点 `Alpine 3.22.7（3.3MB）` → 等进度 → `已就绪：alpine`**

### 5.3 装 Ubuntu

**环境卡 → 点 `Ubuntu 24.04.3（28.6MB）` → 首次约 3–5 分钟 → `已就绪：ubuntu`**

> **⚠️ 装完第一件事**：开终端跑一次 `apt update`，确认源正常。报错看 [9.2](#92-apk-update--apt-update-报错)。

### 5.4 重装 / 卸载（会丢数据！）

| 按钮 | 作用 | 注意 |
| --- | --- | --- |
| 重装 | 清空当前 rootfs 重新下载 | 先停掉所有沙盒服务，**rootfs 内数据全没** |
| 卸载 | 彻底删除环境 | 同上，卸载后回到「未安装」 |

> **💡 重装前**：重要数据先备份（[文件互通 →](#74-文件互通与数据保命)）。

### 5.5 多发行版切换

- 两个 rootfs **同时存在、互不覆盖**
- 服务跑在哪个环境里 = **最近一次安装/重装**的那个
- 想切回 Alpine：点 Alpine 标签 → 会触发**重装（Alpine 数据会丢）**
- 想「只切换不重装」：目前得先卸载 Ubuntu，再重新激活 Alpine

---

## 六、沙盒终端怎么用

### 6.1 启动会话

环境就绪后，「启动终端」变可点 → 状态 **未启动 → 会话中**（绿点）→ 出现黑色终端区 + 输入框。

### 6.2 会话特性

| 特性 | 说明 |
| --- | --- |
| 持久 | `cd`、环境变量、已装软件，整个会话里一直有效 |
| 长驻 | 不是「一条命令一次执行」，是持续的 shell |
| ❌ 非 TTY | `vim`/`top`/`htop`/`nano` 会乱码 |
| ✅ 管道正常 | `cat file \| grep xxx \| sort` 毫无问题 |

### 6.3 包管理速查

**Alpine（`apk`）**

```sh
apk update                       # 刷新软件源
apk search nodejs                # 搜软件
apk add nodejs                   # 装 Node.js
apk add python3 py3-pip          # 装 Python
apk add nginx                    # 装 Nginx
apk del nodejs                   # 卸载
apk info                         # 列出已装
```

**Ubuntu（`apt`）**

```sh
apt update                       # 刷新源
apt install -y nodejs           # 装（必须 -y！）
apt install -y python3 python3-pip
apt remove -y nodejs             # 卸载
dpkg -l                          # 列出已装
```

> **🔴 Ubuntu 铁律**：`apt install` / `apt remove` **一律加 `-y`**，否则卡在 `Do you want to continue? [Y/n]` —— 而终端没有 TTY，你按 Ctrl+C 也断不掉，只能 [结束会话重来](#93-apk-add--apt-install-卡住)。

### 6.4 文件与进程

```sh
ls -la                           # 列目录
cd /srv                          # 切目录
cat file.txt                     # 看内容
echo "content" > file.txt        # ✅ 写文件（推荐）
echo "more" >> file.txt          # ✅ 追加

nano file.txt                    # ❌ 不支持
vi file.txt                      # ❌ 不支持

ps aux                           # 看进程
pkill -f node                    # 按名字杀
kill -9 <pid>                    # 按 PID 强杀
```

> **💡 怎么编辑文件**：用 `echo` 重定向，或者从宿主推到 sdcard 再 `cp`（[见 7.4](#74-文件互通与数据保命)）。

### 6.5 输入 / 输出 / 结束

- **输入**：下方输入框敲命令 → 点「发送」或回车
- **回显**：你敲的命令会以 `> 命令` 形式显示
- **输出**：终端区显示 stdout + stderr，可上下滑动翻历史
- **结束会话**：点「结束」→ 发 `exit` → 300ms 后还没退就 SIGKILL

> **⚠️ 结束会话 ≠ 停服务**：已经注册成常驻服务的进程会继续跑。

### 6.6 会话 vs 服务

| 维度 | 终端会话 | 常驻服务 |
| --- | --- | --- |
| 生命周期 | 手动开 / 关 | 手动或自启 |
| 后台锁屏 | 应用打开时才活 | 退后台、锁屏都照跑 |
| 通知栏 | 无 | 有「源影运行中 · 服务 N」 |
| 探活 | 无 | TCP / HTTP / 进程探活 |
| 日志 | 只在终端区 | 独立日志面板，可复制 |
| 用途 | 装软件、调命令、调试 | 长期跑的服务 |

---

## 七、常驻服务管理

### 7.1 什么是沙盒服务

= 跑在沙盒里的**常驻后台进程**：

- 靠 Android 前台服务保活，退后台、锁屏不停
- 崩溃自动重启（默认最多 1 次）
- 支持定时探活（TCP / HTTP / 进程）
- 有独立日志、可设自启动

### 7.2 创建服务的三种姿势

#### 方式一：一键示例（新手先玩这个）

**服务卡 → 一键创建示例服务 → 启动 → 点日志**

自动生成的命令：

```sh
while true; do echo "[sample] alive $(date)"; sleep 10; done
```

日志里每 10 秒蹦一条 `[sample] alive ...`，启停 / 日志 / 通知栏全流程一次跑通。

#### 方式二：自定义

**服务卡 → 自定义 → 填表 → 添加**

| 字段 | 必填 | 说明 | 示例 |
| --- | --- | --- | --- |
| 服务名称 | ✅ | 给你自己看的 | `my-node-api` |
| 启动命令 | ✅ | 沙盒内完整命令 | `node /srv/app.js --port 5757` |
| 端口 | ⬜ | 填了才开 TCP 探活 + Web 入口 | `5757` |
| 备注 | ⬜ | 备忘 | 测试用 API |
| 自启动 | ⬜ | App 冷启动自动拉起 | 见 [7.5](#75-自启动) |

#### 方式三：模板抄作业（软件得先装好）

| 场景 | 启动命令 | 端口 |
| --- | --- | --- |
| Node HTTP | `node -e "require('http').createServer((q,s)=>s.end('ok')).listen(5757)"` | 5757 |
| Python HTTP | `python3 -m http.server 8000 --directory /srv` | 8000 |
| PHP 内置服务 | `php -S 0.0.0.0:8000 -t /srv` | 8000 |
| 静态文件（busybox） | `busybox httpd -f -p 8080 -h /srv` | 8080 |
| Node 项目 | `cd /srv && npm start` | 依应用 |

### 7.3 启停与探活

**启动**：服务卡 → 启动。状态 `已停止 → 启动中 → 运行中`（15 秒内），超时判 **探活超时**。

**停止**：服务卡 → 停止。流程：`SIGTERM`（给 2 秒优雅退出）→ `SIGKILL` 兜底。PRoot 正常退出时 `--kill-on-exit` 会连带清掉内部子进程，**不会留僵尸占端口**。

**探活规则**

| 探活方式 | 触发条件 | 判断依据 |
| --- | --- | --- |
| TCP | 填了端口 | 每 5 秒连 `127.0.0.1:<端口>` |
| HTTP | 填了端口 + 路径 | 每 5 秒 `GET http://127.0.0.1:<端口><路径>`（路径默认 `/`） |
| 进程 | 没填端口 | 进程还在不在 |

> **💡 跑 HTTP 服务一定填端口**，不然服务挂了 App 也不知道。

**端口冲突**：两个服务同端口 → 第二个报「端口已被占用」；端口被宿主占了（如 `5575` MediaProxy）→ 也会冲突，换一个。

### 7.4 文件互通与数据保命

沙盒文件在应用私有目录（`.../files/sandbox/rootfs/alpine/`），普通文件管理器看不到。

| 方式 | 怎么做 |
| --- | --- |
| ✅ 沙盒内直接造 | `echo "内容" > /srv/file.txt`，最省事，不碰宿主 |
| 从宿主拷进来 | 插件中心 **服务** Tab → 沙盒运行时 → 打开数据目录；或 App 缓存管理把文件推到 `files/`，再 `cp /path/源 /target` |
| 挂 sdcard（要改代码） | 见 [10.5](#105-挂载-sdcard到沙盒需改代码) |

> **📌 血泪提示**：**重装 / 卸载会清空 rootfs**。重要数据别只放 rootfs 里——想留就先弄到宿主存储（如 `/sdcard/backup`），因为 PRoot 卸载时连 rootfs 一起删。

### 7.5 自启动

勾了「自启动」的服务，在下面这些时机自动拉起：

- App **冷启动** ✅
- App 从前台恢复 → **不触发**（只认冷启动）
- 沙盒页**首次进入**（`_autoStartTriggered` 第一次执行时）

**怎么测**：勾自启动并保存 → 启动服务确认有日志 → 从最近任务划掉 App → 重开 App 进沙盒页 → 服务应自己变「运行中」。

### 7.6 日志

点服务卡 **日志**，底部弹层按时间顺序显示：

| 前缀 | 含义 |
| --- | --- |
| `[start]` | 启动动作 |
| `[proc] pid=xxx` | 进程 PID |
| `[health] ready` | 探活通过 |
| （裸行） | stdout |
| `[err]` | stderr |
| `[proc] exited (0)` | 退出码 |

操作：**复制**（全量进剪贴板）、**清空**（清当前缓冲，滚动保留最近 2000 行）。

### 7.7 编辑 / 删除

| 操作 | 行为 |
| --- | --- |
| 编辑 | 改名称/命令/端口/备注/自启；**跑着会先自动停**，保存后需手动重启 |
| 删除 | 二次确认，先停服务再删 |

### 7.8 通知栏保活

任一服务进入「运行中」后：

- 通知栏出现 **源影运行中 · 服务 N**
- 点通知 → 回到 App
- 点通知上 **全部停止** → 停掉所有沙盒服务，约 2 秒后通知消失

> **⚠️ 通知栏没出来？** 检查：设置 → 应用 → 源影 → 通知权限；Android 14+ 看「服务运行」通知频道是否开启；MIUI 这类 ROM 还得加「自启动白名单」。

---

## 八、常见应用场景（可直接抄）

### 8.1 Node.js HTTP 服务

```sh
# 1. 装 Node
apk add nodejs              # Alpine
# apt install -y nodejs     # Ubuntu

# 2. 写应用
mkdir -p /srv/app && cd /srv/app
echo "require('http').createServer((q,s)=>s.end('Hello from Node')).listen(5757)" > app.js

# 3. 先跑一次试试
node app.js
# 浏览器访问 http://127.0.0.1:5757
# 想停？终端里 Ctrl 可能没反应，直接「结束会话」
```

注册为服务：**名称** `node-hello`｜**命令** `node /srv/app/app.js`｜**端口** `5757`｜自启动按需。

### 8.2 Python Flask API

```sh
apk add python3 py3-pip
pip3 install flask -i https://pypi.tuna.tsinghua.edu.cn/simple

mkdir -p /srv/api
cat > /srv/api/app.py <<'EOF'
from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return 'Hello from Flask'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000)
EOF

python3 /srv/api/app.py
```

注册为服务：**名称** `flask-api`｜**命令** `python3 /srv/api/app.py`｜**端口** `8000`。

### 8.3 Nginx 静态站点

```sh
apk add nginx

mkdir -p /srv/www
echo "<h1>Hello Nginx</h1>" > /srv/www/index.html

cat > /etc/nginx/http.d/default.conf <<'EOF'
server {
    listen 8080;
    root /srv/www;
}
EOF

nginx -g 'daemon off;'
```

注册为服务：**名称** `nginx-site`｜**命令** `nginx -g 'daemon off;'`｜**端口** `8080`。

> **💡 必须 `daemon off;`** 把 Nginx 按前台进程跑，否则沙盒以为它退了。

### 8.4 busybox httpd 秒级共享文件

```sh
mkdir -p /srv/share
echo "shared file" > /srv/share/test.txt
busybox httpd -f -p 8080 -h /srv/share
```

浏览器开 `http://手机IP:8080` 就是文件列表。  
注册为服务：**名称** `file-share`｜**命令** `busybox httpd -f -p 8080 -h /srv/share`｜**端口** `8080`。

### 8.5 定时任务（Alpine 没 cron 的平替）

```sh
while true; do
  echo "[task] $(date)" >> /var/log/task.log
  # 你的任务逻辑放这儿
  sleep 3600
done
```

注册为服务：**名称** `hourly-task`｜**命令** `while true; do date >> /var/log/task.log; sleep 3600; done`｜**端口留空**（探活走进程）。

---

## 九、常见问题排查

### 9.1 环境装不上 / 卡在下载

| 原因 | 解决 |
| --- | --- |
| 网络抖 | 换 WiFi / 切 4G 重试 |
| 镜像站同步滞后 | 换相邻版本（如 `3.22.7` → `3.22.3`） |
| 磁盘满 | 清出至少 200MB |
| 权限 | 插件中心 设置 → 文件访问 授权 |

### 9.2 `apk update` / `apt update` 报错

**症状**：`temporary error` / `Temporary failure resolving` / `connection refused`  
**根因**：DNS 或软件源没生效。

```sh
cat /etc/resolv.conf
# 正常应该看到：
# nameserver 223.5.5.5
# nameserver 119.29.29.29

cat /etc/apk/repositories          # Alpine → 应是阿里云
cat /etc/apt/sources.list.d/ubuntu.sources   # Ubuntu → 应是清华 ubuntu-ports
```

**源不对就手动重写**：

```sh
# Alpine
echo "https://mirrors.aliyun.com/alpine/v3.22/main" > /etc/apk/repositories
echo "https://mirrors.aliyun.com/alpine/v3.22/community" >> /etc/apk/repositories

# Ubuntu
echo "nameserver 223.5.5.5" > /etc/resolv.conf
```

还不通 → 先确认宿主手机本身能不能上网。

### 9.3 `apk add` / `apt install` 卡住

> 基本都是 Ubuntu 上**忘了 `-y`**，卡在确认提示。非 TTY 下 Ctrl+C 无效，**只能结束会话 → 重开 → 补上 `-y`**。

### 9.4 服务启动超时（探活 15 秒）

| 原因 | 怎么查 |
| --- | --- |
| 命令路径写错 | 终端里手动跑一遍，看报错 |
| 软件没装 | `which node` 确认 |
| 端口被别的沙盒服务占 | 看其他服务端口配置 |
| 端口被宿主占 | 如 `5575` = MediaProxy，换端口 |
| 依赖缺失 | 翻日志面板的 `[err]` |

### 9.5 通知栏不出现

1. 设置 → 应用 → 源影 → **通知** 打开
2. Android 14+：确认「源影 → **服务运行**」通知频道没关
3. MIUI / 国产 ROM：加 **自启动白名单**

### 9.6 状态「运行中」但浏览器打不开

Android 默认不对外开放应用端口：

- 本机访问：`http://127.0.0.1:端口` ✅
- 局域网访问：`http://手机IP:端口`，要和手机同 WiFi；大多数 ROM 默认允许监听 `0.0.0.0` 被局域网访问

### 9.7 `vim` / `top` / `htop` 乱码

终端是**无 TTY 模式**，全屏交互程序一律歇菜。

| 想做的事 | 替代方案 |
| --- | --- |
| 编辑文件 | `echo "x" > f.txt` / `echo "x" >> f.txt` |
| 看进程 | `ps aux` |
| 看内存/负载 | `free -h`、`cat /proc/loadavg` |
| 非要交互 shell | 装 `openssh-server`，从 PC 用 adb shell / ssh 进来 |

### 9.8 卸载环境后空间没释放

```sh
# 法一：卸载后回沙盒页，随便点个 distro 触发「重装」
# 法二：手动清缓存
rm -rf /data/data/com.example.yuanying/files/sandbox/cache/*
```

### 9.9 服务没输出但状态「运行中」

正常——命令本身不吐日志（比如 `sleep infinity`），或者输出被缓冲了。

```sh
# 强制行缓冲
python3 -u your_script.py
# 或通用包裹
stdbuf -oL -eL your_command
```

---

## 十、进阶技巧

### 10.1 国内镜像加速（默认已配，这是手动兜底）

```sh
# Alpine：切阿里云
sed -i 's|dl-cdn.alpinelinux.org|mirrors.aliyun.com|g' /etc/apk/repositories
apk update

# Ubuntu：切清华
sed -i 's|archive.ubuntu.com|mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list.d/ubuntu.sources
apt update
```

### 10.2 查看服务资源占用

```sh
ps aux | grep -v grep | head -20
free -h
df -h
```

### 10.3 完整备份环境（手动）

rootfs 位置：

```text
/data/data/com.example.yuanying/files/sandbox/rootfs/<alpine|ubuntu>/
```

步骤（需要「文件访问」权限）：

1. MT 管理器 / 系统文件管理器进上面路径
2. 整份 `alpine/`（或 `ubuntu/`）复制到 `/sdcard/backup/`
3. 卸载重装后，反向复制回去

> ⚠️ 别把唯一副本留在 rootfs 里，卸载即没。

### 10.4 和「插件中心服务」混用要注意

| 维度 | 插件中心服务 | 沙盒服务 |
| --- | --- | --- |
| 运行时 | Node / PHP / Python / custom | PRoot + Linux 发行版 |
| 命令形态 | `bin/node index.js` | `proot ... /bin/sh -c "..."` |
| 端口表 | ServiceManager 独立维护 | SandboxServiceManager 独立维护 |
| 通知栏 | 同一个 ServiceHostService | 同一个 ServiceHostService |

混用三条守则：

- **两边端口表不互通**，但内核层面会真冲突（沙盒用 5757、插件中心也用 5757 → 必炸一个）
- 关 proot 插件 **不影响** 插件中心服务
- 通知栏「全部停止」**两边一起停**

### 10.5 挂载 sdcard 到沙盒（需改代码）

默认**不挂载**。要在 `proot_launcher.dart` 的 `buildArgs` 里加一行：

```dart
'--bind=/storage/emulated/0:/mnt/sdcard',
```

之后沙盒里 `/mnt/sdcard` 就是宿主存储根。改完**重装 proot 插件**才生效。

### 10.6 多服务端口分配建议

| 用途 | 推荐段 |
| --- | --- |
| 一般 HTTP | `8000–8999` |
| Node 服务 | `3000–3999` |
| Python 服务 | `5000–5999` |
| 🚫 避开 | `5575`（MediaProxy）、`8080` 等宿主常占端口 |

---

## 附录 A · 命令速查表

**Alpine**

```sh
apk update                    # 刷新源
apk add <pkg>                 # 装
apk del <pkg>                 # 卸
apk info                      # 已装列表
apk search <keyword>          # 搜
```

**Ubuntu**

```sh
apt update                    # 刷新源
apt install -y <pkg>          # 装（必须 -y）
apt remove -y <pkg>           # 卸
dpkg -l                       # 已装列表
apt search <keyword>          # 搜
```

**通用**

```sh
ls -la                        # 详细列出
cd <dir>                      # 切目录
cat <file>                    # 看内容
echo "x" > <file>             # 写文件
echo "x" >> <file>            # 追加
ps aux                        # 进程
pkill -f <name>               # 按名杀
kill -9 <pid>                 # 强杀
free -h                       # 内存
df -h                         # 磁盘
uname -a                      # 系统信息
```

---

## 附录 B · 内置镜像源一览

**Alpine（阿里云）**

```text
https://mirrors.aliyun.com/alpine/v3.22/main
https://mirrors.aliyun.com/alpine/v3.22/community
```

**Ubuntu（清华 ubuntu-ports）**

```text
https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports/
```

**PyPI（清华）**

```sh
pip3 install <pkg> -i https://pypi.tuna.tsinghua.edu.cn/simple
```

**npm（淘宝镜像）**

```sh
npm config set registry https://registry.npmmirror.com
```

**DNS**

```text
nameserver 223.5.5.5      # 阿里
nameserver 119.29.29.29   # 腾讯
```

---

## 反馈与支持

- 文档没覆盖的问题 → 设置 → **系统日志** 导出日志反馈
- 插件相关 → 插件中心 **市场 → 刷新**，看 PRoot 有无新版
- 功能建议 → 设置 → 关于 → **反馈**

---

*文档版本 v1.1｜源影 v2.0.8+｜PRoot 1.0.0｜2026-10-30*
