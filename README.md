<p align="center">
  <img src="DiskMount/Brand/DiskMount-Logo.png" alt="DiskMount" width="520">
</p>

<p align="center">
  macOS 菜单栏外接磁盘管理工具 · 安全加载、NTFS 读写挂载与安全弹出
</p>

<p align="center">
  <a href="https://github.com/samni728/diskmount">项目主页</a> ·
  <a href="https://github.com/samni728/diskmount/stargazers">给项目一个 Star</a>
</p>

# DiskMount

当前版本：**0.1.3**

DiskMount 是面向普通 Mac 用户的菜单栏磁盘工具。插入 U 盘或移动硬盘后，App 会自动刷新设备列表；用户可以加载、卸载、在 Finder 打开或安全弹出磁盘。NTFS 分区通过 App 内嵌的 `anylinuxfs` 运行时重新挂载为可读写，不会改变磁盘原格式。

> [!IMPORTANT]
> DiskMount 不执行格式化、抹盘、重新分区或文件系统转换。“NTFS 读写加载”只改变本次挂载方式，不转换磁盘格式。

## 主要功能

- 常驻 macOS 顶部菜单栏，点击图标打开 WebUI 控制面板；
- 插拔外接磁盘后立即刷新，另有 5 秒状态轮询兜底；
- 显示卷名、设备标识、所属整盘、文件系统、容量、挂载点和读写状态；
- 普通 FAT/exFAT/APFS 数据卷使用 macOS `diskutil` 加载和卸载；
- NTFS 卷使用内嵌 `anylinuxfs 0.18.0` 读写挂载；
- 在 Finder 打开已加载卷；
- 安全弹出整块外接磁盘；
- 页面内提供项目地址和“给我一个 Star”按钮。

## 默认安全模式与专家模式

默认界面只显示可操作的外接数据卷，自动隐藏：

- 当前正在运行 macOS 的启动物理磁盘；
- 包含 macOS `System` 角色的外接启动盘；
- EFI、Recovery、Preboot、VM、Update 等辅助分区；
- 没有卷名、无法识别或不可正常加载的技术分区。

右上角“专家模式”可在风险确认后显示这些高级分区。该模式当前是**只读查看模式**：受保护设备只显示信息，不提供加载、卸载或弹出按钮；Swift 业务层也会拒绝伪造的操作请求。

## 系统要求

- Apple Silicon：M1、M2、M3、M4、M5 或后续 ARM64 Mac；
- macOS 26 或更高版本（0.1.3 使用 Tahoe 版内嵌运行时）；
- 首次初始化 NTFS microVM 数据时需要网络；
- NTFS 挂载时需要在 macOS 系统窗口中输入管理员密码。

0.1.3 不支持 Intel/x86 Mac。原因是核心 `anylinuxfs/libkrun` 上游目前只支持 Apple Silicon；App 不会把“界面能打开但核心功能不可用”描述成 Intel 支持。

## 安装与使用

1. 下载并双击 `DiskMount-0.1.3-macOS26.dmg`；
2. 将 `DiskMount.app` 拖入 `Applications`；
3. 从“应用程序”打开 DiskMount；
4. 首次启动会主动显示面板，关闭后仍常驻顶部菜单栏；
5. 插入 U 盘或移动硬盘；
6. 普通卷点击“加载”，NTFS 卷点击“NTFS 读写加载”；
7. 使用完成后点击“卸载卷”或“安全弹出整盘”。

最终用户不需要安装 Homebrew、Xcode、XcodeGen 或 anylinuxfs。DMG 内嵌 ARM64 的 anylinuxfs、Linux kernel、VM helpers、modules 和 libblkid。anylinuxfs 首次使用时可能自动下载并初始化 Alpine microVM 根文件系统到当前用户目录；后续使用复用该环境。

管理员密码由 macOS 系统授权窗口处理，DiskMount 不读取、不保存密码。

## 开源项目致谢

DiskMount 的 NTFS 读写能力建立在 [nohajc/anylinuxfs](https://github.com/nohajc/anylinuxfs) 之上。anylinuxfs 使用 Linux 原生文件系统驱动、[libkrun](https://github.com/containers/libkrun) microVM 和 NFS，让 macOS 无需内核扩展即可访问 Linux 支持的文件系统。衷心感谢 anylinuxfs 作者、维护者以及 libkrun、libkrunfw、vmnet-helper、gvproxy、docker-nfs-server 等项目的贡献者。

DiskMount 通过命令行子进程调用未修改的 anylinuxfs，并在发布包中保留它的 GPL-3.0-or-later 许可、README 与 SBOM。完整版本、源码地址、校验值和 util-linux/libblkid 许可见 [THIRD_PARTY_NOTICES.md](DiskMount/Resources/THIRD_PARTY_NOTICES.md)。DiskMount 不是 anylinuxfs 官方 GUI，也不代表上游项目提供背书。

## 架构

```text
显式 AppKit 生命周期
  └─ 顶部菜单栏 NSStatusItem
      └─ NSPopover
          └─ WKWebView（HTML/CSS/JavaScript）
              └─ 受限 Swift 消息桥
                  ├─ DiskService
                  │   ├─ 外接物理盘枚举
                  │   ├─ 启动盘 / APFS System / EFI 风险过滤
                  │   └─ /usr/sbin/diskutil
                  └─ AnyLinuxFSService
                      └─ App 内嵌 anylinuxfs 运行时
```

- `DiskMount/App/`：显式启动入口、菜单栏生命周期和弹层；
- `DiskMount/Web/`：WebKit 控制器和 Swift/JavaScript 消息桥；
- `DiskMount/Resources/`：WebUI、图标资源和第三方声明；
- `DiskMount/Services/`：命令执行、磁盘安全过滤和 NTFS 挂载；
- `DiskMount/Models/`：前后端共享状态；
- `DiskMount/Vendor/`：内嵌运行时签名权限文件；
- `DiskMount/scripts/`：可复现依赖下载、签名和 DMG 构建。

## Xcode 开发

生成并打开工程：

```bash
cd DiskMount
xcodegen generate
open DiskMount.xcodeproj
```

选择 `DiskMount` Scheme 和 `My Mac` 后运行。开发机可以临时使用 `/opt/homebrew/bin/anylinuxfs`；正式 DMG 始终嵌入固定版本，不依赖开发机现有安装。

运行测试：

```bash
cd DiskMount
xcodebuild \
  -project DiskMount.xcodeproj \
  -scheme DiskMount \
  -configuration Debug \
  -derivedDataPath build/TestDerived \
  test
```

## 构建自包含 DMG

```bash
cd DiskMount
./scripts/build_dmg.sh
```

脚本会：

1. 使用 Xcode 构建 ARM64 Release App；
2. 下载固定的官方 anylinuxfs 与 util-linux bottles；
3. 校验 SHA-256；
4. 嵌入运行时并修正 `libblkid` 动态库路径；
5. 分别签名运行时与 App；
6. 生成 `DiskMount/build/DiskMount-0.1.3-macOS26.dmg`。

当前本机构建使用 Apple Development 证书，适合本机和开发测试。面向公众无警告分发仍需要 Developer ID Application 证书、Apple 公证和 stapling。

## 0.1.3 更新记录

- 将“PRO”更名为更清晰的“专家模式”；
- 重构弹窗为固定头部、独立磁盘列表滚动区与固定底部；
- 设备较多时只滚动磁盘卡片，Logo、版本、项目地址和 Star 按钮始终可见；
- 收紧面板高度与上下间距，减少单设备场景的无效留白。

## 0.1.2 更新记录

- 修复无 Storyboard 工程中 `AppDelegate` 未被实例化的问题；
- 启动后菜单栏状态项和面板可靠显示；
- 新增品牌 Icon、Logo 和完整 AppIcon 资源；
- 新增磁盘插拔通知、设备详情和版本信息；
- 默认隐藏启动盘与系统辅助分区；
- 新增带风险确认的高级分区只读查看模式；
- 新增项目链接和 Star 按钮；
- 内嵌 anylinuxfs ARM64 运行时，不再要求最终用户安装 Homebrew；
- 保持 NTFS 原格式不变，删除所有格式转换含义。

## 已知限制

- anylinuxfs 将卷作为本机 NFS 网络卷暴露给 macOS；
- 上游说明 Microsoft Word 不能直接编辑该类网络卷上的文件；
- 默认 ntfs-3g 在长时间大量复制时可能出现可重试 I/O 错误；
- 首次 microVM 初始化需要网络，完成后可复用；
- 0.1.3 仅支持 Apple Silicon；
- 不应在文件仍在写入时卸载或拔出设备。

## 路线图

### Now — 0.1.x

- 真实 NTFS 移动硬盘的完整写入/卸载/再次插入回归；
- Developer ID 签名、公证和正式 Release；
- 完善首次 microVM 初始化进度提示。

### Next — 0.2.x

- 完全离线的预置 microVM 根文件系统；
- 登录时启动和按磁盘记忆挂载偏好；
- 可导出的诊断日志；
- 调研可靠、可合法分发的 Intel/x86 NTFS 后端。

### 永不纳入默认流程

- 自动格式化；
- 无确认抹盘或重新分区；
- 对当前系统盘提供一键弹出；
- 把“读写挂载”描述成“格式转换”。
