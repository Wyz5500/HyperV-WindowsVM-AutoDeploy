<p align="center">
  <img src="https://img.shields.io/badge/PowerShell-7-blue.svg" alt="PowerShell 7" align="left"/>
</p>

# 🖥️ Deploy-VM.ps1 自动部署脚本

⚡ 使用 PowerShell 7 编写的高度自动化 Hyper-V 虚拟机部署脚本，支持从 ISO 镜像自动安装 Windows，并完成引导配置与个性化设置。

## 📦 功能概览

- 自动创建 VHDX 并在其中建立 EFI、MSR 和 NTFS 分区
- 自动挂载 ISO 镜像
- 自动应用 Windows 映像到 VHDX 并添加 EFI 引导
- 加载脚本相同目录下的 "autounattend.xml" 作为应答文件个性化 Windows 设置
- 自动创建并启动虚拟机

## ⚙️ 可配置项

| 参数 | 说明 |
|------|------|
| `$vmName` | 虚拟机名称 |
| `$cpuCore` | CPU 核心数，不能超过主机 CPU 逻辑核心数 |
| `$switchName` | 虚拟交换机名称，一般情况下默认即可 |
| `$VHDXDirPath` | 虚拟硬盘存储路径，默认使用 Hyper-V 的虚拟硬盘路径 |
| `$VHDXSize` | 虚拟硬盘最大空间，最大支持 64TB |
| `$isoPath` | Windows 安装镜像路径，".iso" 后缀文件 |
| `$index` | 安装映像的索引号，决定 Windows 的版本（如：专业版） |

## 🚀 脚本食用指南

❗确保已启用 Hyper-V

1. 安装 PowerShell 7 和 Git，如果已经安装可以跳过这一步：
```
winget install Microsoft.PowerShell
winget install Microsoft.Git
```
2. 重启终端，设置 Git 的用户名和邮箱，如果已经设置可以跳过这一步：
```
#用户名和邮箱可以随便填，也可以填 Github 账号用户名和邮箱
git config --global user.name <你的用户名>
git config --global user.email <你的邮箱>
```
3. 以管理员身份启动 PowerShell 7，执行命令：

```
git clone https://github.com/Wyz5500/HyperV-WindowsVM-AutoDeploy.git
Set-Location HyperV-WindowsVM-AutoDeploy
```
4. 修改 Deploy-VM.ps1 内的配置信息，接着运行脚本：
```
Set-ExecutionPolicy RemoteSigned -Scope Process
.\Deploy-VM.ps1
```
## 🔗使用的第三方组件

本项目在映像应用流程中使用了 [wimlib](https://wimlib.net/)（版本 1.14.4）来替代 Windows 原生 DISM 工具，以获得更高的性能。

### wimlib 简介
wimlib 是一个开源的 WIM（Windows Imaging Format）文件读写工具，支持多种压缩算法和跨平台使用。

### 版权与许可
wimlib 遵循 GNU General Public License v3 (GPL-3.0)。完整许可证请参见：
[wimlib License](https://github.com/ebiggers/wimlib/blob/master/COPYING.GPLv3).

> **注意**：本项目仅调用 wimlib 的命令行接口，不对其源码做任何修改。
