#这些设置需要自己调整：
$vmName = "Windows 10"
$cpuCore = 8        #不能超出主机逻辑处理器数量
$vhdxDirPath = "D:\Virtual Hard Disks"
$isoPath = "D:\Files\系统\镜像\原版\zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso"

#这些是可选设置：
$vhdxSize = 64GB        #动态增长，可以设置的比主机剩余硬盘空间大，不能超过64TB。
$switchName = "Default Switch"        #Windows Server主机默认虚拟网络交换机名称可能会有不同。
$index = 1        #用于设置Windows版本（如：家庭版、专业版），可以使用Dism++查看索引对应的Windows版本。
$exposeVirtualizationExtensions = $true        #控制是否启用嵌套虚拟化，可选值有"$true"和"$false"

#内存相关设置，也是可选设置
$memory = 4GB        #虚拟机启动时分配的内存
$enableDynamicMemory = $true        #控制是否启用动态内存，可选值有"$true"和"$false"
$minMemory = 512MB        #虚拟机可用的最小内存，启动动态内存时才生效
$maxMemory = 1048576MB        #虚拟机可用的最大内存，启用动态内存时才生效


##################################################
#只有上面的内容需要设置，下面的内容不要乱动。
##################################################


$vhdxPath = [System.IO.Path]::Combine($vhdxDirPath, "$($vmName).vhdx")
function envCheck {
    #检测主机是否完整安装 Hyper-V，比较耗时间（已完成）
    #$featureEnabled = (Get-WindowsOptionalFeature -Online | Where-Object {$_.FeatureName -eq "Microsoft-Hyper-V-All"}).State

    #新的检测方法，性能提高数倍
    $featureEnabled = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All).State
    #$featureEnabled
    if (-not ($featureEnabled -eq "Enabled")) {
        Write-Warning "请完整安装并启用 Hyper-V 功能后再使用此脚本"
        return $false
    }

    #检测主机是否开启虚拟化功能
    if (-not ($(Get-CimInstance Win32_ComputerSystem).HypervisorPresent -eq $true)){
        Write-Warning "Hypervisor 没有在运行,可以尝试使用命令 `"BCDEdit /set hypervisorlaunchtype auto`" 修复"
        return $false
    }

    return $true
}

function memCheck {
    param (
        [Int64]$memory,
        [bool]$enableDynamicMemory,
        [Int64]$minMemory,
        [Int64]$maxMemory
    )

    #检查内存分配（已完成）
    #$hostMemory = $(Get-CimInstance -ClassName Win32_ComputerSystem).TotalPhysicalMemory
    $hostMemory = $(Get-CimInstance -ClassName Win32_PhysicalMemory | Measure-Object -Property Capacity -Sum).Sum
    #$hostMemory

    if ($enableDynamicMemory -eq $true) {
        if ($minMemory -lt 512MB) {
            Write-Warning "虚拟机的最小内存不能小于 512 MB"
            return $false
        } elseif ($maxMemory -gt 240TB) {
            Write-Warning "虚拟机的最大内存不能超过 240TB"
            return $false
        } elseif ($minMemory -gt $maxMemory) {
            Write-Warning "虚拟机的最大内存不能小于虚拟机的最小内存"
            return $false
        } elseif ($memory -gt $hostMemory) {
            Write-Warning "虚拟机的启动内存不能超过物理内存"
            return $false
        } elseif ($memory -gt $maxMemory) {
            Write-Warning "虚拟机的启动内存不能超过虚拟机的最大内存"
            return $false
        } elseif ($minMemory -gt $memory) {
            Write-Warning "虚拟机的启动内存不能小于虚拟机的最小内存"
            return $false
        }
    } elseif ($enableDynamicMemory -eq $false) {
        if ($memory -gt $hostMemory) {
            Write-Warning "为虚拟机设置的内存不能超过主机内存"
            return $false
        } elseif ($memory -lt 512MB) {
            Write-Warning "为虚拟机设置的内存不能小于 512MB"
            return $false
        }
    }

    return $true
}

function basicCheck {
    param (
        [string]$vhdxDirPath,
        [string]$switchName,
        [Int16]$cpuCore,
        [string]$vmName
    )

    #检测虚拟硬盘目录是否存在（已完成）
    if (-not (Test-Path $vhdxDirPath)) {
        Write-Warning "找不到存放虚拟硬盘的目录 `"$($vhdxDirPath)`""
        return $false
    }

    #检查是否存在虚拟交换机
    if ($switchName -notin $(Get-VMSwitch).Name) {
        Write-Warning "找不到虚拟网络交换机 `"$($switchName)`""
        return $false
    }

    #检测CPU核心数量设置是否合法（已完成）
    #$maxCpuCore = (Get-CimInstance -ClassName Win32_Processor | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
    $maxCpuCore = [System.Environment]::ProcessorCount
    if ($cpuCore -gt $maxCpuCore) {
        Write-Warning "虚拟机的 CPU 核心数量不能超过 $($maxCpuCore)"
        return $false
    } elseif ($cpuCore -lt 1) {
        Write-Warning "至少需要为虚拟机分配 1 个 CPU 核心（我看你就是来捣乱的(╯▔皿▔)╯）"
        return $false
    }

    #检查是否存在同名虚拟机
    $machines = $(Get-VM).Name
    foreach ($machine in $machines) {
        if ($machine -eq $vmName) {
            Write-Warning "已存在同名虚拟机"
            return $false
        }
    }

    return $true
}

function isoCheck {
    #若检查未通过，则卸载iso镜像
    #检查通过后，iso镜像将保持挂载状态

    param (
        [string]$isoPath,
        [Int16]$index
    )

    #检查iso镜像是否能挂载（已完成）
    if (-not (Test-Path $isoPath)) {
        Write-Warning "找不到 Windows 的安装镜像文件 `"$($isoPath)`"，请设置正确的路径"
        return $false
    } else {
        $windowsImage = $null

        try {
            #挂载 iso 镜像文件
            $image = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
            $installer = (Get-Volume -DiskImage $image | Select-Object -First 1)

            if(-not $installer) {
                Write-Warning "无法从 iso 镜像文件中获取有效卷"
                $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                
                return $false
            }

            #检查 Windows 的体系架构
            $bootFile = "$($installer.DriveLetter):\efi\boot\bootx64.efi"
            if (-not (Test-Path $bootFile)) {
                Write-Warning "该脚本只正式支持 amd64 架构的 Windows 10/11 操作系统"
                $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue

                return $false
            }

            #检测 iso 文件有效性
            if (Test-Path "$($installer.DriveLetter):\sources\install.wim") {
                $windowsImage = "$($installer.DriveLetter):\sources\install.wim"
            } elseif (Test-Path "$($installer.DriveLetter):\sources\install.esd") {
                $windowsImage = "$($installer.DriveLetter):\sources\install.esd"
            } else {
                Write-Warning "无法在挂载的 iso 镜像中找到 Windows 系统映像"
                $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue

                return $false
            }

            try {
                #检测映像文件中是否包含 Windows 版本信息，没有的话会捕获报错
                $Script:windowsVersion = Get-WindowsImage -ImagePath $windowsImage | Where-Object {$_.ImageIndex -eq $index} -ErrorAction Stop
                if ($Script:windowsVersion -eq $null) {
                    Write-Warning "找不到 index 对应的 Windows 版本"
                    Write-Host "可用的 Windows 版本和对应索引："
                    Write-Host (Get-WindowsImage -ImagePath $windowsImage | Select-Object ImageName, ImageIndex)
                    $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue

                    return $false
                }
            }
            catch {
                Write-Warning "映像中不包含任何 Windows 版本"
                $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue

                return $false
            }
        }
        catch {
            Write-Warning $_.Exception.Message
            $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue

            return $false
        }

    }

    return $true
}

function vhdxCheck {
    #如果检查没通过，则卸载iso镜像、删除VHDX文件
    #检查通过后，iso镜像保持挂载状态，vhdx硬盘被卸载，vhdx硬盘文件被保留

    param (
        [string]$vhdxPath,
        [Int64]$vhdxSize,
        [string]$isoPath
    )

    $success = 1

    #获取虚拟硬盘文件所在分区剩余可用空间
    try {
        $driveRoot = [System.IO.Directory]::GetDirectoryRoot($vhdxPath.TrimEnd("\"))
        $sizeRemaining = ([System.IO.DriveInfo]::GetDrives() | Where-Object {$_.RootDirectory.FullName -eq $driveRoot}).AvailableFreeSpace
    }
    catch {
        Write-Warning $_.Exception.Message
        return $false
    }

    if (Test-Path $vhdxPath) {
        Write-Warning "虚拟硬盘文件 `"$($vhdxPath)`" 已存在"
        $success = 0
    } elseif ($sizeRemaining -lt 64GB) {
        Write-Warning "存储虚拟硬盘文件的分区至少需要预留 64GB 用于 Windows 虚拟机正常运行"
        $success = 0
    } elseif ($vhdxSize -lt 64GB) {
        Write-Warning "虚拟硬盘的大小不能小于 64GB"
        $success = 0
    } elseif ($vhdxSize -gt 64TB) {
        Write-Warning "虚拟硬盘的大小不能大于 64TB"
        $success = 0
    } else {
        try {
            $null = new-VHD -Path $vhdxPath -SizeBytes $vhdxSize -Dynamic -ErrorAction Stop
            $Script:vhdx = Mount-VHD -Path $vhdxPath -Passthru -ErrorAction Stop    #VHDX挂载后的内部信息，保留用于全局
            Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning $_.Exception.Message
            Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
            $success = 0
        }
    }

    if ($success -eq 0) {
        $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
        return $false
    }

    return $true
}

function vmCheck {
    #成功后关闭虚拟机，保留虚拟机、vhdx文件、iso镜像挂载状态
    #失败后卸载iso镜像、删除虚拟机、删除vhdx文件

    param (
        [string]$vmName,
        [string]$switchName,
        [string]$vhdxPath,
        [Int16]$cpuCore,
        [bool]$exposeVirtualizationExtensions,
        [int64]$memory,
        [bool]$enableDynamicMemory,
        [Int64]$minMemory,
        [Int64]$maxMemory,
        [string]$isoPath
    )

    $success = 1

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
        $vm = New-VM @vmInfo -ErrorAction Stop
        $VMHD = Get-VMHardDiskDrive -VMName $vmName                                                                         #获取虚拟机内部VHDX信息
        Set-VMFirmware -VMName $vmName -FirstBootDevice $VMHD                                                               #设置启动固件为VHDX
        Set-VMProcessor -VMName $vmName -Count $cpuCore                                                                     #设置CPU核心数量
        Set-VMFirmware -VMName $vmName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows -ErrorAction Stop          #设置虚拟机使用安全启动
        Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $exposeVirtualizationExtensions                     #开启虚拟机的嵌套虚拟化

        if ($enableDynamicMemory -eq $true) {
            try {
                Set-VM -VM $vm -MemoryStartupBytes $memory -DynamicMemory -MemoryMinimumBytes $minMemory -MemoryMaximumBytes $maxMemory -ErrorAction Stop
            }
            catch {
                Write-Warning $_.Exception.Message
                $success = 0
            }
        } elseif ($enableDynamicMemory -eq $false) {
            try {
                Set-VM -VM $vm -MemoryStartupBytes $memory -StaticMemory -ErrorAction Stop
            }
            catch {
                Write-Warning $_.Exception.Message
                $success = 0
            }
        }

        #这个没有报错就是检查通过，需要卸载iso镜像，关闭虚拟机
        try {
            Start-VM -VMName $vmName -ErrorAction Stop
            Stop-VM -Name $vmName -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Warning $_.Exception.Message
            $success = 0
        }
    }
    catch {
        Write-Warning $_.Exception.Message
        $success = 0
    }

    if ($success -eq 0) {
        $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
        $null = Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue
        $null = Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
        $null = Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue

        return $false
    }

    return $true
}

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

    $vmCheckParams = @{
        vmName = $vmName
        switchName = $switchName
        vhdxPath = $vhdxPath
        cpuCore = $cpuCore
        exposeVirtualizationExtensions = $exposeVirtualizationExtensions
        memory = $memory
        enableDynamicMemory = $enableDynamicMemory
        minMemory = $minMemory
        maxMemory = $maxMemory
        isoPath = $isoPath
    }

    if (-not (envCheck)) {return $false}
    if (-not (memCheck -memory $memory -enableDynamicMemory $enableDynamicMemory -minMemory $minMemory -maxMemory $maxMemory)) {return $false}
    if (-not (basicCheck -vhdxDirPath $vhdxDirPath -switchName $switchName -cpuCore $cpuCore -vmName $vmName)) {return $false}
    if (-not (isoCheck -isoPath $isoPath -index $index)) {return $false}
    if (-not (vhdxCheck -vhdxPath $vhdxPath -vhdxSize $vhdxSize -isoPath $isoPath)) {return $false}
    if (-not (vmCheck @vmCheckParams)) {return $false}

    return $true
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



$Script:successDeploy = 1     #用于控制脚本是否继续执行。

function vhdxCreate {
    try {
        "创建虚拟硬盘`"$($vhdxPath)`"……"
        $null = New-VHD -Path $vhdxPath -SizeBytes $vhdxSize -Dynamic -ErrorAction Stop
        $Script:successDeploy = 1
    }
    catch {
        Write-Warning "$($_.Exception.Message)"
        "虚拟硬盘创建失败……"
        $Script:successDeploy = 0
    }
}

function vhdxPrepare {
    if ($Script:successDeploy -eq 1) {
        try {
            #挂载虚拟硬盘并选中。
            $VHDX = Mount-VHD -Path $vhdxPath -Passthru -ErrorAction Stop
            $disk = Get-Disk -Number $VHDX.DiskNumber -ErrorAction Stop

            try {
                #初始化虚拟硬盘。
                Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction Stop

                #新建200MB的EFI分区，格式化为FAT32。
                "为虚拟硬盘新建EFI分区……"
                $efiPartition = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter -ErrorAction Stop
                $null = Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel 'SYSTEM' -Force -Confirm:$false -ErrorAction Stop

                #新建16MB的MSR分区，不需要格式化。
                "为虚拟硬盘新建MSR分区……"
                $null = New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' -ErrorAction Stop

                #新建Windows系统分区，格式化为NTFS，使用虚拟硬盘所有剩余空间
                "为虚拟硬盘新建NTFS分区……"
                $ntfsPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
                $null = Format-Volume -Partition $ntfsPartition -FileSystem NTFS -NewFileSystemLabel $vmName -Force -Confirm:$false -ErrorAction Stop

                #从分区对象获取EFI分区和NTFS分区卷标。
                $Script:efiDriverLetter = $(Get-Volume -Partition $efiPartition).DriveLetter
                $Script:ntfsDriverLetter = $(Get-Volume -Partition $ntfsPartition).DriveLetter
            }
            catch {
                Write-Warning $_.Exception.Message
                "虚拟硬盘分区失败……"
                "清理虚拟硬盘文件……"
                $null = Dismount-VHD -Path $vhdxPath
                Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
                $Script:successDeploy = 0
            }
        }
        catch {
            Write-Warning $_.Exception.Message
            "虚拟硬盘挂载失败……"
            $Script:successDeploy = 0
        }
    }
}

function isoMount {
    if ($Script:successDeploy -eq 1) {
        try {
            #挂载Windows安装镜像并选中。
            "挂载Windows安装镜像`"$($isoPath)`"……"
            $image = Mount-DiskImage -ImagePath $isoPath -PassThru -ErrorAction Stop
            $installer = Get-Volume -DiskImage $image | Select-Object -First 1

            #获取Windows映像文件路径。
            $Script:wimPath = "$($installer.DriveLetter):\sources\install.wim"
            $Script:esdPath = "$($installer.DriveLetter):\sources\install.esd"
        }
        catch {
            Write-Warning $_.Exception.Message
            "挂载Windows安装镜像失败……"
            "清理虚拟硬盘文件……"
            $null = Dismount-VHD -Path $vhdxPath
            Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
            $Script:successDeploy = 0
        }
    }
}

function installWindows {
    if ($Script:successDeploy -eq 1) {
        #将Windows安装镜像中的系统安装到虚拟硬盘的NTFS分区，并在EFI分区上设置引导。
        $Script:successDeploy = 0

        #检测Windows映像文件类型并应用映像。
        #应用成功后为虚拟机的Windows系统设置引导项。
        if (Test-Path $Script:wimPath) {
            Dism /Apply-Image /index:$index /ImageFile:"$Script:wimPath" /ApplyDir:"$($ntfsDriverLetter):\"
            if ($LASTEXITCODE -ne 0) {
                "应用Windows映像失败……"
            } else {
                bcdboot "$($ntfsDriverLetter):\Windows" /s "$($efiDriverLetter):" /f UEFI /l zh-CN
                if ($LASTEXITCODE -ne 0) {
                    "Windows引导添加失败……"
                } else {
                    unattendProcess
                    $Script:successDeploy = 1
                    "卸载Windows安装镜像……"
                    $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                    $null = Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue
                }
            }
        } elseif (Test-Path $Script:esdPath) {
            Dism /Apply-Image /index:$index /ImageFile:"$Script:esdPath" /ApplyDir:"$($ntfsDriverLetter):\"
            if ($LASTEXITCODE -ne 0) {
                "应用Windows映像失败……"
            } else {
                bcdboot "$($ntfsDriverLetter):\Windows" /s "$($efiDriverLetter):" /f UEFI /l zh-CN
                if ($LASTEXITCODE -ne 0) {
                    "Windows引导添加失败……"
                } else {
                    unattendProcess
                    $Script:successDeploy = 1
                    "卸载Windows安装镜像……"
                    $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                    $null = Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue
                }
            }
        } else {
            "找不到Windows映像文件……"
        }

        if ($Script:successDeploy -eq 0) {
            "卸载Windows安装镜像……"
            $null = Dismount-DiskImage -ImagePath $isoPath
            "清理虚拟硬盘文件……"
            $null = Dismount-VHD -Path $vhdxPath
            Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
        }
    }
}

function unattendProcess {
    #尝试搜索脚本同目录下的"autounattend.xml"文件作为应答文件个性化Windows设置。
    if (Test-Path "$($PSScriptRoot)\autounattend.xml") {
        "在`"$($PSScriptRoot)`"中找到`"autounattend.xml`"……"
        $null = New-Item -Path "$($ntfsDriverLetter):\Windows\Panther\" -ItemType Directory
        $null = Copy-Item -Path "$($PSScriptRoot)\autounattend.xml" -Destination "$($ntfsDriverLetter):\Windows\Panther\unattend.xml"
    } else {
        "没有在`"$($PSScriptRoot)`"中找到`"autounattend.xml`"……"
    }
}

function startVM {
    if ($Script:successDeploy -eq 1) {
        #设置虚拟机创建信息
        $vmInfo = @{
            Name = $vmName                  #虚拟机名称
            Generation = 2                  #虚拟机代数
            SwitchName = $SwitchName        #虚拟交换机名称
            VHDPath = $vhdxPath             #虚拟硬盘路径
            MemoryStartupBytes = $memory    #启动时给虚拟机分配的内存大小
        }

        try {
            "创建虚拟机……"
            $vm = New-VM @vmInfo -ErrorAction Stop
            $VMHD = Get-VMHardDiskDrive -VMName $vmName                                                         #获取虚拟机内部VHDX信息
            Set-VMFirmware -VMName $vmName -FirstBootDevice $VMHD                                               #设置启动固件为VHDX
            Set-VMProcessor -VMName $vmName -Count $cpuCore                                                     #设置CPU核心数量
            Set-VMFirmware -VMName $vmName -EnableSecureBoot On                                                 #设置虚拟机使用安全启动
            Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $exposeVirtualizationExtensions     #开启虚拟机的嵌套虚拟化

            if ($enableDynamicMemory -eq $true) {
                try {
                    Set-VM -VM $vm -MemoryStartupBytes $memory -DynamicMemory -MemoryMinimumBytes $minMemory -MemoryMaximumBytes $maxMemory -ErrorAction Stop
                }
                catch {
                    Write-Warning $_.Exception.Message
                    "虚拟机设置失败……"
                    #"删除虚拟机……"
                    Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
                    #Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
                    $Script:successDeploy = 0
                }
            } elseif ($enableDynamicMemory -eq $false) {
                try {
                    Set-VM -VM $vm -MemoryStartupBytes $memory -StaticMemory -ErrorAction Stop
                }
                catch {
                    Write-Warning $_.Exception.Message
                    "虚拟机设置失败……"
                    #"删除虚拟机……"
                    Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
                    #Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
                    $Script:successDeploy = 0
                }
            } else {
                "内存设置失败……"
                $Script:successDeploy = 0
            }

        }
        catch {
            Write-Warning $($_.Exception.Message)
            $Script:successDeploy = 0
        }
        
        if ($Script:successDeploy -eq 1) {
            "启动虚拟机……"
            try {
                Start-VM -VMName $vmName -ErrorAction Stop
                $null = Start-Process -FilePath "vmconnect.exe" -ArgumentList $('"' + $env:COMPUTERNAME + '"'), $('"' + $vmName + '"') -ErrorAction Stop
            }
            catch {
                Write-Warning $_.Exception.Message
                "虚拟机启动失败……"
                "删除虚拟机`"$($vmName)`"……"
                Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
                "清理虚拟硬盘文件……"
                Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
            }
            
        } elseif ($Script:successDeploy -eq 0) {
            "虚拟机创建失败……"
            "清理虚拟硬盘文件……"
            Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
        }
    }
}

#脚本主流程，先通过几次检测才开始正式执行脚本流程

if (preCheck @preCheckParams) {
    Write-Host "参数检查完成 ✔" -ForegroundColor Green     #用于表示测试全部通过

    #全部检查通过后的清理流程，正式部署时不需要
    $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
    Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
    #Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue

    #vhdxCreate      #创建虚拟硬盘
    vhdxPrepare     #初始化虚拟硬盘，为虚拟硬盘分区
    isoMount        #挂载iso安装镜像
    installWindows  #从挂载的iso镜像中安装Windows到虚拟硬盘并添加引导项
    startVM         #创建并启动虚拟机
}