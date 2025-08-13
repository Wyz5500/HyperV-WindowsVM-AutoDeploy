#这些设置需要自己调整：
$vmName = "Windows VM"
$cpuCore = 1        #不能超出主机逻辑处理器数量
$vhdxDirPath = "D:\Virtual Hard Disks"
$isoPath = "D:\Files\系统\镜像\原版\zh-cn_windows_11_business_editions_version_24h2_updated_june_2025_x64_dvd_3a591782.iso"

#这些是可选设置：
$vhdxSize = 1TB        #动态增长，可以设置的比主机剩余硬盘空间大，不能超过64TB。
$switchName = "Default Switch"        #Windows Server主机默认虚拟网络交换机名称可能会有不同。
$index = 2        #用于设置Windows版本（如：家庭版、专业版），可以使用Dism++查看索引对应的Windows版本。
$exposeVirtualizationExtensions = $true        #控制是否启用嵌套虚拟化，可选值有"$true"和"$false"

#内存相关设置，也是可选设置
$memory = 4GB        #虚拟机启动时分配的内存
$enableDynamicMemory = $false        #控制是否启用动态内存，可选值有"$true"和"$false"
$minMemory = 512MB        #虚拟机可用的最小内存，启动动态内存时才生效
$maxMemory = 1048576MB        #虚拟机可用的最大内存，启用动态内存时才生效


##################################################
#只有上面的内容需要设置，下面的内容不要乱动。
##################################################


$vhdxPath = [System.IO.Path]::Combine($vhdxDirPath, "$($vmName).vhdx")

function preCheck {
    param (
        #一步即可检测
        [string]$isoPath,                       #直接挂载，打印异常（已完成）
        [string]$vhdxDirPath,                   #检查目录是否存在（已完成）
        [string]$vhdxPath,                      #检查虚拟硬盘文件和虚拟硬盘所在物理分区的大小是否合适，检查虚拟硬盘文件能否正常创建（完成一半）
        [Int64]$minMemory,                      #至少为512MB（已完成）
        [Int64]$maxMemory,                      #不能大于240TB（已完成）
        
        #需要获取信息再检测
        [string]$vmName,                        #检查是否存在同名虚拟机(已完成)
        [Int16]$cpuCore,                        #大于0，不超过主机CPU核心数量（已完成）
        [Int64]$memory,                         #不大于物理内存（已完成）
        [Int64]$vhdxSize,                       #至少64GB，物理驱动器剩余空间至少64GB（已完成）
        [string]$switchName,                    #系统中要存在这个虚拟交换机(已完成)
        [Int16]$index,                          #Dism获取索引可取值
        [bool]$exposeVirtualizationExtensions,  #检测主机是否启用虚拟化功能，是否支持嵌套虚拟化（想不到怎么实现，已放弃）
        
        #需要创建虚拟机后才能检查
        [bool]$enableDynamicMemory              #不需要检查（已完成）
    )

    #检测主机是否完整安装 Hyper-V，比较耗时间（已完成）
    #$featureEnabled = (Get-WindowsOptionalFeature -Online | Where-Object {$_.FeatureName -eq "Microsoft-Hyper-V-All"}).State

    #新的检测方法，性能提高数倍
    $featureEnabled = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All).State
    #$featureEnabled
    if (-not ($featureEnabled -eq "Enabled")) {
        Write-Error "请完整安装并启用 Hyper-V 功能后再运行此脚本"
        exit 0
    }

    #检测主机是否开启虚拟化功能
    if (-not ($(Get-CimInstance Win32_ComputerSystem).HypervisorPresent -eq $true)){
        Write-Error "Hypervisor 没有在运行,可以尝试使用命令 `"BCDEdit /set hypervisorlaunchtype auto`" 修复"
        exit 0
    }

    #检测虚拟硬盘目录是否存在（已完成）
    if (-not (Test-Path $vhdxDirPath)) {
        Write-Error "虚拟硬盘目录 `"$($vhdxDirPath)`" 不存在……"
        exit 0;
    }

    #检查内存分配（已完成）
    #$hostMemory = $(Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
    $hostMemory = $(Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    #$hostMemory

    if ($enableDynamicMemory -eq $true) {
        if ($minMemory -lt 512MB) {
            Write-Error "虚拟机的最小内存不能小于 512 MB"
            exit 0
        } elseif ($maxMemory -gt 240TB) {
            Write-Error "虚拟机的最大内存不能超过 240TB"
            exit 0
        } elseif ($minMemory -gt $maxMemory) {
            Write-Error "虚拟机的最大内存不能小于虚拟机的最小内存"
            exit 0
        } elseif ($memory -gt $hostMemory) {
            Write-Error "虚拟机的启动内存不能超过物理内存"
            exit 0
        } elseif ($memory -gt $maxMemory) {
            Write-Error "虚拟机的启动内存不能超过虚拟机的最大内存"
            exit 0
        } elseif ($minMemory -gt $memory) {
            Write-Error "虚拟机的启动内存不能小于虚拟机的最小内存"
            exit 0
        }
    } elseif ($enableDynamicMemory -eq $false) {
        if ($memory -gt $hostMemory) {
            Write-Error "为虚拟机设置的内存不能超过主机内存"
            exit 0
        } elseif ($memory -lt 512MB) {
            Write-Error "为虚拟机设置的内存不能小于 512MB"
            exit 0
        }
    }

    #检查是否存在虚拟交换机
    if ($switchName -notin $(Get-VMSwitch).Name) {
        Write-Error "找不到虚拟网络交换机 `"$($switchName)`""
        exit 0
    }

    #旧的虚拟交换机检测代码
    # $switchs = $(Get-VMSwitch).Name
    # $tag = 0

    # foreach ($switch in $switchs) {
    #     if ($switch -eq $switchName) {
    #         $tag = 1
    #     }
    # }

    # if ($tag -eq 0) {
    #     Write-Error "找不到虚拟网络交换机 `"$($switchName)`""
    #     exit 0
    # }

    #检测CPU核心数量设置是否合法（已完成）
    #$maxCpuCore = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $maxCpuCore = [System.Environment]::ProcessorCount

    if ($cpuCore -gt $maxCpuCore) {
        Write-Error "虚拟机的 CPU 核心数量不能超过 $($maxCpuCore)"
        exit 0
    } elseif ($cpuCore -lt 1) {
        Write-Error "至少需要为虚拟机分配 1 个 CPU 核心（我看你就是来捣乱的(╯▔皿▔)╯）"
        exit 0
    }

    #检查是否存在同名虚拟机
    $machines = $(Get-VM).Name
    foreach ($machine in $machines) {
        if ($machine -eq $vmName) {
            Write-Error "已存在同名虚拟机"
            exit 0
        }
    }

    #检测虚拟硬盘文件能否被正确创建（完成一半）
    #$driveLetter = $(Get-Item $vhdxDirPath).PSDrive.Name    #".PSDrive.Name"用于文件或目录所在的盘符
    $driveRoot = [System.IO.Directory]::GetDirectoryRoot($vhdxDirPath.TrimEnd("\"))
    #$sizeRemaining = $(Get-Volume | Where-Object {$_.DriveLetter -eq $driveLetter}).SizeRemaining

    #获取虚拟硬盘文件所在分区剩余可用空间
    $sizeRemaining = ([System.IO.DriveInfo]::GetDrives() | where {$_.RootDirectory.FullName -eq $driveRoot}).AvailableFreeSpace

    if (Test-Path $vhdxPath) {
        Write-Error "虚拟硬盘文件 `"$($vhdxPath)`" 已存在"
        exit 0;
    } elseif ($sizeRemaining -lt 64GB) {
        Write-Error "存储虚拟硬盘文件的分区至少需要预留 64GB 用于 Windows 虚拟机正常运行"
        exit 0;
    } elseif ($vhdxSize -lt 64GB) {
        Write-Error "虚拟硬盘的大小不能小于 64GB"
        exit 0
    } elseif ($vhdxSize -gt 64TB) {
        Write-Error "虚拟硬盘的大小不能大于 64TB"
        exit 0
    } else {
        try {
            $null = $(new-VHD -Path $vhdxPath -SizeBytes $vhdxSize -Dynamic -ErrorAction Stop)
            $Script:vhdx = Mount-VHD -Path $vhdxPath -Passthru
        }
        catch {
            Write-Error $_.Exception.Message

            Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue
            Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue

            exit 0;
        }
    }

    Dismount-VHD -Path $vhdxPath

    #设置新建虚拟机参数
    $vmInfo = @{
        Name = $vmName                  #虚拟机名称
        Generation = 2                  #虚拟机代数
        SwitchName = $SwitchName        #虚拟交换机名称
        VHDPath = $vhdxPath             #虚拟硬盘路径
        MemoryStartupBytes = $memory    #启动时给虚拟机分配的内存大小
    }

    #检查虚拟机能否正常创建
    try {
        $Script:vm = New-VM @vmInfo -ErrorAction Stop
        $VMHD = Get-VMHardDiskDrive -VMName $vmName                                                         #获取虚拟机内部VHDX信息
        Set-VMFirmware -VMName $vmName -FirstBootDevice $VMHD                                               #设置启动固件为VHDX
        Set-VMProcessor -VMName $vmName -Count $cpuCore                                                     #设置CPU核心数量
        Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows            #设置虚拟机使用安全启动
        Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $exposeVirtualizationExtensions     #开启虚拟机的嵌套虚拟化

        if ($enableDynamicMemory -eq $true) {
            try {
                Set-VM -VM $Script:vm -MemoryStartupBytes $memory -DynamicMemory -MemoryMinimumBytes $minMemory -MemoryMaximumBytes $maxMemory -ErrorAction Stop
            }
            catch {
                Write-Error $_.Exception.Message

                Remove-VM $vmName -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue

                exit 0
            }
        } elseif ($enableDynamicMemory -eq $false) {
            try {
                Set-VM -VM $Script:vm -MemoryStartupBytes $memory -StaticMemory -ErrorAction Stop
            }
            catch {
                Write-Error $_.Exception.Message

                Remove-VM $vmName -Force -ErrorAction SilentlyContinue
                Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue

                exit 0
            }
        }

        try {
            Start-VM -VMName $vmName -ErrorAction Stop
            Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            Remove-VM $vmName -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
        }
        catch {
            Write-Error $_.Exception.Message

            Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue
            Remove-VM $vmName -Force -ErrorAction SilentlyContinue
            Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue

            exit 0

        }
    }
    catch {
        Write-Error $_.Exception.Message
        Remove-VM $vmName -Force -ErrorAction SilentlyContinue
        #清理虚拟硬盘
        Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
        exit 0
    }

    #清理虚拟硬盘
    

    #检查iso镜像是否能挂载（已完成）
    if (-not (Test-Path $isoPath)) {
        Write-Error "找不到 Windows 的安装镜像文件 `"$($isoPath)`"，请设置正确的路径"
        exit 0
    } else {
        try {
            #挂载 iso 镜像文件
            $image = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
            $installer = (Get-Volume -DiskImage $image | Select-Object -First 1)

            #检查 Windows 的体系架构
            $bootFile = "$($installer.DriveLetter):\efi\boot\bootx64.efi"
            if (-not (Test-Path $bootFile)) {
                Write-Error "该脚本只支持 amd64 架构的 Windows 10/11 操作系统"
                $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                exit 0
            }

            #检测 iso 文件有效性
            if (Test-Path "$($installer.DriveLetter):\sources\install.wim") {
                $Script:windowsImage = "$($installer.DriveLetter):\sources\install.wim"
            } elseif (Test-Path "$($installer.DriveLetter):\sources\install.esd") {
                $Script:windowsImage = "$($installer.DriveLetter):\sources\install.esd"
            } else {
                Write-Error "无法在挂载的 iso 镜像中找到 Windows 映像"
                $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                exit 0
            }

            try {
                $imageArch = $(Get-WindowsImage -ImagePath $Script:windowsImage).Architecture
                #检测映像文件中是否包含 Windows 版本信息，没有的话会捕获报错
                $Script:windowsVersion = Get-WindowsImage -ImagePath $Script:windowsImage | Where-Object {$_.ImageIndex -eq $index} -ErrorAction Stop
                if ($Script:windowsVersion -eq $null) {
                    Write-Error "找不到 index 对应的 Windows 版本"
                    "可用的 Windows 版本和对应索引："
                    Get-WindowsImage -ImagePath $Script:windowsImage | Select-Object ImageName, ImageIndex
                    $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                    exit 0
                }
            }
            catch {
                Write-Error $_.Exception.Message
                $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                exit 0
            }
        }
        catch {
            Write-Error $_.Exception.Message
            $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
            exit 0
        }

        #测试过程需要
        $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    }

    Write-Host "参数检查完成 ✔" -ForegroundColor Green     #用于表示测试全部通过
    "虚拟机将要安装的 Windows 版本：$($Script:windowsVersion.ImageName)"
}

#这样写函数参数好看点
$preCheckParams = @{
    vmName = $vmName
    vhdxDirPath = $vhdxDirPath
    vhdxPath = $vhdxPath
    vhdxSize = $vhdxSize
    cpuCore = $cpuCore
    enableDynamicMemory = $enableDynamicMemory
    minMemory = $minMemory
    maxMemory = $maxMemory
    memory = $memory
    isoPath = $isoPath
    switchName = $switchName
    index = $index
    exposeVirtualizationExtensions = $exposeVirtualizationExtensions
}

preCheck @preCheckParams
