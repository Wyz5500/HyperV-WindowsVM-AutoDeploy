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
| `$cpuCore` | CPU 核心数 |
| `$switchName` | 虚拟交换机名称 |
| `$VHDXDirPath` | 虚拟硬盘存储路径 |
| `$VHDXSize` | 虚拟硬盘最大空间 |
| `$isoPath` | Windows 安装镜像路径 |
| `$index` | 安装映像的索引号 |

## 🚀 快速开始

确保已启用 Hyper-V 并安装 PowerShell 7。然后以管理员身份启动 Powershell 7：

```Administrator: PowerShell 7 (x64)
Set-ExecutionPolicy RemoteSigned -Scope Process
.\Deploy-VM.ps1
```
