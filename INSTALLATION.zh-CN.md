# DiskMount 安装与授权说明

[English](INSTALLATION.md)

## 安装前须知

请仅从项目的 [GitHub Releases 页面](https://github.com/samni728/diskmount/releases)下载 DiskMount。0.2.7 是自包含版本，不需要用户安装 Homebrew、Xcode 或独立的 anylinuxfs。

当前安装包使用开发者本人的 Apple Development 证书签名，但尚未使用 Developer ID Application 证书，也没有通过 Apple 公证。从互联网下载 DMG 后，其他 Mac 可能会在第一次启动时进行拦截。这个 Gatekeeper 安装放行与 App 启动后的磁盘权限是两套相互独立的授权。

## 正常安装流程

1. 下载 `DiskMount-0.2.7-macOS26.dmg` 和对应的 `.sha256` 文件。
2. 可以在终端验证下载完整性：

   ```bash
   cd ~/Downloads
   shasum -a 256 -c DiskMount-0.2.7-macOS26.dmg.sha256
   ```

3. 打开 DMG，把 `DiskMount.app` 拖入“应用程序”。
4. 从“应用程序”打开 DiskMount；运行后，主要操作入口常驻在 macOS 顶部菜单栏。

## 如果 macOS 阻止打开

不建议永久关闭 Gatekeeper。请使用 macOS 提供的单 App 放行流程：

1. 先尝试打开一次 DiskMount，然后关闭系统警告。
2. 打开 **系统设置 → 隐私与安全性**。
3. 滚动到 **安全性**，找到 DiskMount 被阻止的提示。
4. 点击 **仍要打开**。通常该按钮会在被阻止启动后保留约一小时。
5. 输入当前 Mac 的登录密码，阅读提示后点击 **打开**。

完成后，macOS 会把 DiskMount 记录为这台 Mac 上的单独例外。如果设备受公司 IT 或 MDM 管理，管理员策略仍可能禁止用户自行放行。可参考 Apple 官方的[安全地打开 Mac App](https://support.apple.com/en-ie/102445)说明。

不要使用永久关闭 Gatekeeper 或无差别移除所有 quarantine 属性的安装教程。如果 SHA-256 校验失败，或 macOS 提示 App 已损坏，请删除该文件并从官方 Release 重新下载。

## App 启动后的权限

以下权限的用途不同，需要分别处理：

1. **管理员授权：** NTFS 读写加载、为安全弹出停止其磁盘服务，以及失败恢复需要更高权限。有效授权尚未过期时，DiskMount 会直接复用；只有 macOS 授权已经失效时才会再次询问。密码只会短暂交给 macOS `sudo`，DiskMount 不会保存、记录或上传密码。
2. **完全磁盘访问权限：** 前往 **系统设置 → 隐私与安全性 → 完全磁盘访问权限 → DiskMount** 开启。
3. **可移动卷权限：** 如果系统显示该选项，前往 **系统设置 → 隐私与安全性 → 文件与文件夹 → DiskMount → 可移动卷** 开启。
4. 修改上述任一隐私权限后，请完全退出并重新打开 DiskMount。

DiskMount 不会格式化、抹掉、重新分区或转换磁盘格式。NTFS 读写只会改变当前挂载方式。

DiskMount 启动和用户手动刷新时会访问 GitHub 的公开“最新 Release”接口。该检查不会发送磁盘内容或管理员密码，也不会自动下载或安装更新。

## 商业分发状态

0.2.7 仍属于开发签名的社区版本。要实现面向普通用户、无未知开发者拦截的公开分发，还需要 Developer ID Application 证书、对 App 和所有内嵌程序进行 Hardened Runtime 签名、提交 Apple 公证并装订公证票据。
