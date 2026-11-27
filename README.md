<div align="center">
    <img width="200" height="200" src="assets/images/logo/logo.png">
</div>



<div align="center">
    <h1>源影</h1>
<div align="center">
    
![GitHub repo size](https://img.shields.io/github/repo-size/bggRGjQaUbCoE/PiliPlus) 
![GitHub Repo stars](https://img.shields.io/github/stars/bggRGjQaUbCoE/PiliPlus) 
</div>
    <p>使用Flutter开发的媒体聚合盒子</p>
</div>


<br/>

## 适配平台

- [x] Android
- [x] iOS
- [x] Pad
- [x] Windows
- [x] Linux


## feat

- [x] 编辑动态
- [x] DLNA 投屏
- [x] 离线缓存/播放
- [x] WebDAV 备份/恢复设置
- [x] 播放全部/继续播放/倒序播放
- [x] Cookie登录
- [x] 显示视频分段信息
- [x] 调节字幕大小
- [x] 调节全屏弹幕大小
- [x] 直播弹幕
- [x] 其他

<br/>

## 功能

- [x] 视频播放相关
  - [x] 双击快进/快退
  - [x] 双击播放/暂停
  - [x] 垂直方向调节亮度/音量
  - [x] 垂直方向上滑全屏、下滑退出全屏
  - [x] 水平方向手势快进/快退
  - [x] 全屏方向设置
  - [x] 倍速选择/长按2倍速
  - [x] 硬件加速（视机型而定）
  - [x] 画质选择（高清画质未解锁）
  - [x] 音质选择（视视频而定）
  - [x] 解码格式选择（视视频而定）
  - [x] 弹幕
  - [x] 字幕
  - [x] 记忆播放
  - [x] 视频比例：高度/宽度适应、填充、包含等
     
- [x] 搜索相关
  - [x] 热搜
  - [x] 搜索历史
  - [x] 默认搜索词
    
- [x] 视频详情页相关
  - [x] 视频选集(分p)切换

- [x] 设置相关
  - [x] 画质、音质、解码方式预设      
  - [x] 图片质量设定
  - [x] 主题模式：亮色/暗色/跟随系统
  - [x] 震动反馈(可选)
  - [x] 高帧率
  - [x] 自动全屏
  - [x] 横屏适配
- [ ] 等等

<br/>

## 下载

可以通过右侧release进行下载或拉取代码到本地进行编译

## 构建、签名与在线更新

版本由 `pubspec.yaml` 的语义版本和 CI run 共同生成：

- 实际构建号：`pubspec 基础构建号 + GITHUB_RUN_NUMBER`
- 关于页显示：`2.0.8+43 · CI #42`
- Android 产物：`yuanying-android-arm64-v8a-v2.0.8+43-r42.apk`
- iOS 产物：`yuanying-ios-trollstore-v2.0.8+43-r42.ipa`
- macOS 产物：`yuanying-macos-v2.0.8+43-r42.dmg`
- Windows 安装包：`yuanying-windows-x64-v2.0.8+43-r42.exe`
- Windows 便携包：`yuanying-windows-x64-portable-v2.0.8+43-r42.zip`

Android Release 使用固定签名。首次迁移时，如果设备上安装的是旧 debug 签名包，
需要先卸载旧包一次；之后所有 CI 产物必须使用同一份密钥，才能直接覆盖安装。

本地生成密钥（命令会交互式要求输入密码）：

```powershell
& "C:\Users\tinyd\Desktop\jdk-21.0.13.1+2-jre\bin\keytool.exe" `
  -genkeypair -v `
  -keystore "android\yuanying-release.jks" `
  -storetype PKCS12 `
  -keyalg RSA -keysize 4096 -validity 10000 `
  -alias yuanying `
  -dname "CN=YuanYing, OU=Mobile, O=YuanYing, L=Shanghai, ST=Shanghai, C=CN"
```

PKCS12 格式下 `keyPassword` 应与 `storePassword` 保持一致。

本地构建时，将 `android/key.properties.example` 复制为 `android/key.properties`
并填写密码。该文件与 `*.jks` 已被 Git 忽略，不要提交。

GitHub Actions 需要配置以下 Secrets：

- `ANDROID_KEYSTORE_BASE64`：JKS 文件的 Base64 内容
- `ANDROID_KEYSTORE_PASSWORD`：keystore 密码
- `ANDROID_KEY_ALIAS`：密钥别名

本项目的 CI 固定签名使用 PKCS12，密钥密码与 keystore 密码相同。
`ANDROID_KEY_PASSWORD` 不再需要单独配置；如果控制台中已有该项，可以保留或删除。

Windows PowerShell 可把密钥内容写入剪贴板：

```powershell
[Convert]::ToBase64String(
  [IO.File]::ReadAllBytes("android\yuanying-release.jks")
) | Set-Clipboard
```

版本唯一维护点是 `pubspec.yaml` 的 `version`。发布前只需要修改这一行，
然后手动运行需要平台对应的 GitHub Actions 工作流。CI 不会自动创建 tag
或发布 Release，只上传已命名的构建产物。

Windows 使用 `Build Windows EXE` 工作流，会同时生成 Inno Setup 安装包和
便携 ZIP；Windows 程序与安装包的版本均来自同一个 `pubspec.yaml` 版本源。

在线更新读取当前仓库的 GitHub Releases。需要发布时，请手动创建
`v2.0.8` 形式的 Release 并上传对应平台产物；Android 会按设备 ABI 选择 APK，
下载后拉起系统安装器。设置 → 关于 → 当前版本即可在线检查更新。

<br/>

## 声明

此项目（源影）基于[PiliPlus](https://img.shields.io/github/repo-size/bggRGjQaUbCoE/PiliPlus)开发而来，仅用于学习和测试，请于下载后24小时内删除。
所用API皆从官方网站收集，不提供任何破解内容。
在此致敬原作者：[guozhigq/pilipala](https://github.com/guozhigq/pilipala)
在此致敬上游作者：[orz12/PiliPalaX](https://github.com/orz12/PiliPalaX)
本仓库做了更激进的修改，感谢原作者的开源精神。

感谢使用


<br/>

## 致谢

- [flutter_meedu_videoplayer](https://github.com/zezo357/flutter_meedu_videoplayer)
- [media-kit](https://github.com/media-kit/media-kit)
- [dio](https://pub.dev/packages/dio)
- 等等

<br/>
<br/>
<br/>

## Star History

<a href="https://www.star-history.com/#bggRGjQaUbCoE/PiliPlus&Date">
 <picture>
   <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date&theme=dark" />
   <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
   <img alt="Star History Chart" src="https://api.star-history.com/svg?repos=bggRGjQaUbCoE/PiliPlus&type=Date" />
 </picture>
</a>
