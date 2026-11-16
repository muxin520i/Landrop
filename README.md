# 近传 LanDrop

局域网文件互传 App，**Android + iOS 双端**。两台手机连同一个 Wi-Fi，打开就能互相传文件——不经过服务器、不登录、不限速、不限大小。

---

## 功能

| 能力 | 说明 |
| --- | --- |
| 自动发现 | 同一 Wi-Fi 下打开 App，2 秒左右自动出现对方设备 |
| 任意文件 | 照片、视频、文档、压缩包、APK 都可以，支持多选 |
| 大文件 | 2 MB 分片传输，带实时进度；断线后从断点续传，不用从头再来 |
| 聊天式界面 | 收发记录按时间线排列，像聊天一样，点一下就能打开/导出 |
| 扫码连接 | 自动发现失败时，扫对方「我的连接码」即可直连 |
| 手动 IP | 最后兜底，输入 `192.168.1.5` 这种地址 |

传输全程走局域网直连，没有任何云端中转，也没有账号体系。

---

## 一、构建（推荐：GitHub Actions 一键出包）

不需要本地装 Flutter / Xcode，直接用 GitHub 的机器构建。

```bash
git init
git add .
git commit -m "init: 近传"
git branch -M main
git remote add origin https://github.com/<你的用户名>/<仓库名>.git
git push -u origin main
```

推上去之后：

1. 打开仓库的 **Actions** 页 → 左侧 **Build** → 右侧 **Run workflow**
2. 等约 8~12 分钟，两个 job 都变绿
3. 在本次运行的页面底部 **Artifacts** 下载：
   - `landrop-android-apk` → 解压得到 `app-release.apk`，传到手机直接安装
   - `landrop-ios-ipa` → 解压得到 `Landrop-unsigned.ipa`（**未签名，需要自签**，见第二节）

### 打 tag 自动发 Release

```bash
git tag v1.0.0
git push origin v1.0.0
```

流水线会把 APK 和 IPA 一起挂到 Releases 页面，下载更方便（公开仓库无需登录）。

> 如果 Actions 报权限错误，去 **Settings → Actions → General → Workflow permissions** 选 **Read and write permissions**。

---

## 二、iOS 安装（未签名 ipa 的正确用法）

iOS 不允许安装未签名应用，`Landrop-unsigned.ipa` 必须用你的 Apple ID 重签一次。任选一种：

### 方案 A：Sideloadly（Windows / macOS，最省事）

1. 电脑装 [Sideloadly](https://sideloadly.io/)
2. 数据线连 iPhone，把 `Landrop-unsigned.ipa` 拖进窗口
3. Apple Account 填你的 Apple ID，点 Start，输入密码
4. 手机上：**设置 → 通用 → VPN与设备管理 → 开发者 App → 信任**
5. iOS 16+ 还需要：**设置 → 隐私与安全性 → 开发者模式 → 打开并重启**

免费 Apple ID 签名的有效期是 **7 天**，到期用同样步骤重签即可（聊天记录和已收文件不会丢）。

### 方案 B：AltStore / SideStore（手机上续签）

装一次 AltStore，之后每周在手机上点一下刷新，不用连电脑。适合长期自用。

### 方案 C：有付费开发者账号（$99/年）

把证书和描述文件配进仓库 Secrets，我可以再给你加一段自动签名配置，直接出可以装一年的正式 ipa。

> **首次打开 App 会弹「是否允许访问本地网络」——必须点允许**。iOS 靠这个权限才能发现局域网里的另一台手机，拒绝后只能走扫码。

---

## 三、使用

1. 两台手机连**同一个 Wi-Fi**（注意别开「AP 隔离 / 访客网络」，这类网络设备之间互相不通）
2. 各自打开「近传」
3. 上方出现对方设备后点一下选中
4. 点底部 `+` 或输入框 → 选「文件」或「照片或视频」→ 选完自动开始传
5. 接收方在聊天流里看到文件，点一下 → 系统分享面板 → 存到相册 / 文件 / 发给别人

### 接收的文件存在哪

| 平台 | 位置 |
| --- | --- |
| Android | `Android/data/com.landrop.app/files/Received/`（App 内点文件可直接分享导出） |
| iOS | App 沙盒 `Documents/Received/`，已开启文件共享，可在「文件」App → 我的 iPhone → 近传 里看到 |

---

## 四、技术说明

### 设备发现：为什么不用 UDP 组播

iOS 14 起，raw socket 收发组播/广播需要 Apple 单独审批的 `com.apple.developer.networking.multicast` entitlement。未签名的 ipa 用个人证书重签时拿不到这个权限，组播会静默失败——这是很多局域网工具在 iOS 上「搜不到设备」的根因。

所以这里改成 **对 /24 网段的 254 个地址并发发一次 HTTP 探测**：

- 纯 TCP 单播，iOS 不需要任何特殊 entitlement，只要用户授权「本地网络」
- 一轮全量扫描 254 个地址约 2~4 秒（32 并发，单地址 420 ms 超时）
- 之后每 10 秒只复探已知设备（毫秒级），每 3 轮做一次全量发现
- 探测请求就是 `GET /api/info`，对端返回设备名和 ID，因此发现和传输共用同一个端口

### 传输协议

```
GET  /api/info?…                          设备信息，发现探测用
GET  /api/upload/init?fileId&name&size&sender&senderId
                                          → {"offset": 已收字节数}  用于续传
POST /api/upload/chunk?fileId&offset      body 为原始分片字节
                                          → {"received": 累计字节数}
```

- 分片 2 MB，发送端顺序 POST，服务端按序追加写入 `<fileId>.part`
- 每次重试前重新 `init`，拿到对端**真实**已收字节数再继续，所以切后台、Wi-Fi 闪断都不会白传
- 收满 `size` 字节后自动改名为最终文件，重名自动加 `(1)`、`(2)`
- 端口固定 `53318`，被占用时退回系统随机端口（二维码里带真实端口）

### 安全边界

- 只在局域网内通信，没有服务器、没有账号、没有埋点
- 接收端**默认自动接收**同一 Wi-Fi 内发来的文件（自用场景省一次确认）。不要在公共 Wi-Fi 下开着这个 App 传敏感文件
- 文件名做了路径穿越过滤，不会写到 `Received/` 之外

---

## 五、本地构建

```bash
flutter pub get
flutter run                     # 调试
flutter build apk --release     # Android
flutter build ios --release --no-codesign   # iOS 未签名
```

环境要求：

- Flutter **3.32.8**（Dart 3.8.1）
- Android：JDK 17 + Android SDK 35 + Build-Tools 35.0.0
- iOS：macOS + Xcode 16+、CocoaPods

本地打 iOS 包需要 macOS；Linux / Windows 只能出 Android。

> 国内网络下 Gradle 官方源很慢，`android/gradle/wrapper/gradle-wrapper.properties` 已指向腾讯云镜像。如果你的网络环境访问不了腾讯云，把它换回 `https://services.gradle.org/distributions/gradle-8.12-all.zip` 即可。

---

## 六、目录结构

```
lib/
├── main.dart                     入口
├── core/
│   ├── protocol.dart             端口、分片大小、超时等常量
│   ├── device_identity.dart      本机 ID / 名称 / IP
│   ├── discovery_service.dart    /24 网段 TCP 探测发现
│   ├── transfer_server.dart      接收端 HTTP 服务、分片落盘、续传
│   ├── transfer_client.dart      发送端分片上传、失败重试
│   ├── chat_store.dart           聊天记录本地持久化
│   └── models/
│       ├── peer_device.dart      设备模型、二维码编解码
│       └── chat_message.dart     消息模型
├── state/app_state.dart          全局状态、收发调度队列
└── ui/
    ├── chat_page.dart            聊天式主界面
    ├── scan_page.dart            扫码连接
    ├── my_qr_sheet.dart          我的连接码
    ├── manual_connect_sheet.dart 手动输入 IP
    ├── theme.dart
    └── widgets/
        ├── device_bar.dart       顶部设备条
        └── message_bubble.dart   文件气泡、进度、状态
.github/workflows/build.yml       Android APK + iOS IPA 双端构建
```

---

## 七、已知限制

- **iOS 后台会挂起**：传输时请保持 App 在前台（已用 wakelock 防止息屏，但切到别的 App 仍可能断）。断了重试会自动续传。
- **AP 隔离网络不可用**：酒店、校园网、公司访客 Wi-Fi 常开启客户端隔离，设备之间无法互通，此时扫码也连不上。用自己的手机热点即可。
- **两台 iPhone 的设备名可能相同**：iOS 16 起系统不返回用户自定义设备名，App 用名称 + 4 位短码区分。

---

## 八、后续可以加的（按需）

- 传输前确认（防止陌生设备乱塞文件）
- 断点续传管理面板（清理未完成的分片）
- 文件夹整体传输（保留目录结构）
- 传输完成通知
- 深色模式手动切换
