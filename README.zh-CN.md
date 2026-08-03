<p align="center">
  <img src="DiskMount/Brand/DiskMount-Logo.png" alt="DiskMount" width="520">
</p>

<p align="center">
  macOS 菜单栏外接磁盘管理工具 · 安全加载、NTFS 读写与安全弹出
</p>

<p align="center">
  <a href="README.md">English</a> · <strong>简体中文</strong>
</p>

<p align="center">
  <a href="https://github.com/samni728/diskmount/releases/latest">下载最新版</a> ·
  <a href="https://github.com/samni728/diskmount/stargazers">给项目一个 Star</a>
</p>

# DiskMount

当前版本：**0.2.2**

DiskMount 会识别 U 盘和移动硬盘，并在紧凑的菜单栏面板中提供加载、卸载、Finder 打开和安全弹出操作。NTFS 卷通过 App 内嵌的 `anylinuxfs` 运行时以读写方式重新加载，不会改变原有文件系统格式。

> [!IMPORTANT]
> DiskMount 不会格式化、抹掉、重新分区或转换磁盘格式。“NTFS 读写加载”只改变当前挂载方式。

![DiskMount 中文界面](docs/screenshots/diskmount-zh.png)

## 主要功能

- 原生 macOS 菜单栏 AppKit 生命周期与 WebKit 控制面板；
- 外接卷加载、卸载或改名时自动刷新；
- 支持英文和简体中文，语言选择会保存；
- 显示卷名、设备标识、所属整盘、文件系统、容量、挂载点和读写状态；
- FAT、exFAT 和 APFS 数据卷的普通加载与卸载；
- 通过内嵌 `anylinuxfs 0.18.0` 进行 NTFS 读写加载；
- 在 Finder 打开已加载卷，并安全弹出外接整盘；
- 固定头部与底部，仅中间磁盘列表滚动；
- App 内置项目地址和 Star 按钮。

## 默认安全模式与专家模式

默认安全模式会隐藏当前 macOS 启动磁盘，以及 EFI、Recovery、Preboot、VM、Update 等技术分区。

专家模式会显示高级卷，但不会自动解锁。用户必须对每一个卷再次阅读警告并确认。通过二次确认后，该卷可在当前 App 会话中尝试加载、在 Finder 打开和卸载。

安全边界会在 Swift 业务层强制执行，不只是 WebUI 文案：

- 关闭专家模式或退出 App 后，会话授权立即失效；
- 不允许通过专家模式弹出受保护的整块磁盘；
- 不会绕过 SIP 或 macOS 安全策略；
- 不会强制将已封存的 macOS 系统卷变为可写；
- 不存在格式转换、抹盘或重新分区功能。

![专家模式的单卷二次授权](docs/screenshots/diskmount-expert-en.png)

## NTFS 管理员授权与可移动卷权限

旧版通过 macOS 管理员授权窗口把 `anylinuxfs` 直接作为 root 进程启动。这种方式不像 `sudo` 那样提供 `SUDO_UID` 和 `SUDO_GID`，因此 anylinuxfs 无法判断真实桌面用户并主动拒绝挂载。

0.2.0 已传入 anylinuxfs 所需的真实用户身份，但 AppleScript 管理员授权链仍可能被 macOS 隐私控制拒绝原始磁盘访问。

0.2.2 改为从 DiskMount 的当前用户上下文，通过真实的 `/usr/bin/sudo` 进程启动内嵌引擎。密码在原生安全输入框中输入，只通过标准输入交给 `sudo`，随后立即清空输入框，不会写入磁盘、偏好设置或日志。由引擎执行真实原始磁盘检查；如果引擎在卸载 NTFS 后失败，DiskMount 会自动恢复 macOS 普通只读挂载。

第一次成功以 NTFS 读写模式加载后，DiskMount 会记住该物理磁盘与分区。当 App 保持运行时，再次插入会自动尝试读写加载，并使用 macOS 持续维护的 `sudo` 授权时间戳。密码不会被持久化；可通过每块磁盘上的“自动读写”按钮关闭。

## 系统要求

- Apple Silicon：M1、M2、M3、M4、M5 或后续芯片；
- macOS 26 或更高版本；
- 首次初始化 Alpine microVM 根文件系统时需要网络；
- 挂载需要更高权限时，需通过 macOS 管理员授权；
- 第一次进行 NTFS 原始磁盘访问时，需允许访问可移动卷。

0.2.2 不支持 Intel/x86 Mac，因为上游 `anylinuxfs/libkrun` 运行时目前主要支持 Apple Silicon。

## 安装

1. 从 [Releases](https://github.com/samni728/diskmount/releases) 下载 `DiskMount-0.2.2-macOS26.dmg`；
2. 打开 DMG，将 `DiskMount.app` 拖入“应用程序”；
3. 从“应用程序”启动 DiskMount；
4. 首次显示面板后，App 会继续常驻顶部菜单栏。

第一次进行 NTFS 读写加载时，可能需要允许“可移动卷访问”并输入管理员密码。DiskMount 仅为把密码交给系统 `sudo` 进程而短暂处理，不会记录或持久化密码。

DMG 内嵌 ARM64 的 anylinuxfs、Linux kernel、VM helpers、modules 和 `libblkid`。最终用户不需要安装 Homebrew、Xcode、XcodeGen 或独立的 anylinuxfs。

当前发布包使用 Apple Development 证书，适合项目测试。若需面向所有用户无警告公开分发，仍需要 Developer ID Application 证书、Apple 公证和 stapling。

## 构建与测试

```bash
cd DiskMount
xcodegen generate
xcodebuild \
  -project DiskMount.xcodeproj \
  -scheme DiskMount \
  -configuration Debug \
  -derivedDataPath build/TestDerived \
  test
```

构建本机签名 DMG：

```bash
cd DiskMount
./scripts/build_dmg.sh
```

## 自动 Release

`.github/workflows/release.yml` 会在每次推送 `v*` 版本标签时，使用 GitHub Apple Silicon `macos-26` runner 自动：

1. 校验标签与 `VERSION` 是否一致；
2. 构建自包含 DMG；
3. 生成 SHA-256 校验文件；
4. 创建带自动更新说明的 GitHub Release。

```bash
# 先更新 VERSION 和更新说明
git tag -a v0.2.2 -m "DiskMount 0.2.2"
git push origin main
git push origin v0.2.2
```

如未配置 Developer ID 签名和公证 Secrets，自动产物使用 ad-hoc 签名。详细维护清单见 [RELEASING.md](RELEASING.md)。

## 开源项目致谢

DiskMount 的 NTFS 读写能力建立在 [nohajc/anylinuxfs](https://github.com/nohajc/anylinuxfs) 之上。anylinuxfs 结合 Linux 原生文件系统驱动、[libkrun](https://github.com/containers/libkrun) microVM 和 NFS。感谢 anylinuxfs 作者，以及 libkrun、libkrunfw、vmnet-helper、gvproxy、docker-nfs-server 和 util-linux 贡献者。

DiskMount 通过独立进程调用未修改的 anylinuxfs。发布包保留上游许可证、README、SBOM 和 util-linux 许可文件。版本、源码地址、校验值和许可详情见 [THIRD_PARTY_NOTICES.md](DiskMount/Resources/THIRD_PARTY_NOTICES.md)。

DiskMount 不是 anylinuxfs 官方 GUI，也不代表上游项目对本项目提供背书。

## 已知限制

- anylinuxfs 会将卷作为本机 NFS 网络卷暴露给 macOS；
- Microsoft Word 可能无法直接编辑这类网络卷上的文件；
- 默认 ntfs-3g 驱动在长时间大量传输时可能出现可重试 I/O 错误；
- 首次 microVM 初始化需要网络；
- 文件正在写入时不应卸载或拔出设备。

完整版本历史见 [CHANGELOG.md](CHANGELOG.md)。
