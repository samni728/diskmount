# Third-Party Notices

DiskMount 通过独立进程调用下列开源组件。它们保留各自的版权和许可条款。

## anylinuxfs 0.18.0

- 项目：https://github.com/nohajc/anylinuxfs
- 对应源码：https://github.com/nohajc/anylinuxfs/tree/v0.18.0
- 构建与 bottle：https://github.com/nohajc/homebrew-anylinuxfs/releases/tag/v0.18.0
- 许可：GNU General Public License v3.0 or later
- 内嵌 bottle SHA-256：`99b674114e3f44c7035521fddff315931723b71149b2b0030c217c45b853cf8f`

感谢 anylinuxfs 作者和贡献者提供基于 libkrun microVM 与 NFS 的 macOS 文件系统读写能力。上游项目还依赖并感谢 libkrun、libkrunfw、vmnet-helper、gvproxy 和 docker-nfs-server。

发布包在 `DiskMount.app/Contents/Resources/anylinuxfs/` 内保留 anylinuxfs 的 `LICENSE`、`README.md` 和 SBOM。DiskMount 与 anylinuxfs 上游项目没有隶属或官方背书关系。

## util-linux / libblkid 2.42.2

- 项目：https://github.com/util-linux/util-linux
- 对应源码：https://github.com/util-linux/util-linux/tree/v2.42.2
- Homebrew Formula：https://formulae.brew.sh/formula/util-linux
- 许可：以随组件分发的 `util-linux-COPYING` 为准；libblkid 采用其上游声明的许可条款。
- 内嵌 bottle SHA-256：`3b2174542f34178348f62bccf804a06d8a1adb3dbd6767ce6b01fd618d63f9db`

发布包在 `DiskMount.app/Contents/Resources/anylinuxfs/licenses/` 内保留 util-linux 的 COPYING 文件。
