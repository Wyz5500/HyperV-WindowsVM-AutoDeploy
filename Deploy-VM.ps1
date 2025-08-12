#这些设置需要自己调整：
$vmName = "Windows 11"
$cpuCore = 4        #不能超出主机逻辑处理器数量
$vhdxDirPath = "D:\Virtual Hard Disks\"
$isoPath = "D:\Files\系统\镜像\定制\LTSC 2024\26100.4652\zh-cn_windows_11_enterprise_ltsc_2024_x64_dvd_cff9cd2d.iso"

#这些是可选设置：
$vhdxSize = 1TB        #动态增长，可以设置的比主机剩余硬盘空间大，不能超过64TB。
$switchName = "Default Switch"        #Windows Server主机默认虚拟网络交换机名称可能会有不同。
$index = 1        #用于设置Windows版本（如：家庭版、专业版），可以使用Dism++查看索引对应的Windows版本。
$exposeVirtualizationExtensions = $false        #控制是否启用嵌套虚拟化，可选值有"$true"和"$false"

#内存相关设置，也是可选设置
$memory = 8GB        #虚拟机启动时分配的内存
$enableDynamicMemory = $false        #控制是否启用动态内存，可选值有"$true"和"$false"
$minMemory = 512MB        #虚拟机可用的最小内存，启动动态内存时才生效
$maxMemory = 1048576MB        #虚拟机可用的最大内存，启用动态内存时才生效


##################################################
#只有上面的内容需要设置，下面的内容不要乱动。
##################################################


$vhdxPath = [System.IO.Path]::Combine($vhdxDirPath, "$($vmName).vhdx")
$Script:success = 1     #用于控制脚本是否继续执行。

function vhdxCreate {
    try {
        "创建虚拟硬盘`"$($vhdxPath)`"……"
        $null = New-VHD -Path $vhdxPath -SizeBytes $vhdxSize -Dynamic -ErrorAction Stop
        $Script:success = 1
    }
    catch {
        Write-Warning "$($_.Exception.Message)"
        "虚拟硬盘创建失败……"
        $Script:success = 0
    }
}

function vhdxPrepare {
    if ($Script:success -eq 1) {
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
                $Script:success = 0
            }
        }
        catch {
            Write-Warning $_.Exception.Message
            "虚拟硬盘挂载失败……"
            $Script:success = 0
        }
    }
}

function isoMount {
    if ($Script:success -eq 1) {
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
            $Script:success = 0
        }
    }
}

function installWindows {
    if ($Script:success -eq 1) {
        #将Windows安装镜像中的系统安装到虚拟硬盘的NTFS分区，并在EFI分区上设置引导。
        $Script:success = 0

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
                    $Script:success = 1
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
                    $Script:success = 1
                    "卸载Windows安装镜像……"
                    $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
                    $null = Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue
                }
            }
        } else {
            "找不到Windows映像文件……"
        }

        if ($Script:success -eq 0) {
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
    if ($Script:success -eq 1) {
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
                    $Script:success = 0
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
                    $Script:success = 0
                }
            } else {
                "内存设置失败……"
                $Script:success = 0
            }

        }
        catch {
            Write-Warning $($_.Exception.Message)
            $Script:success = 0
        }
        
        if ($Script:success -eq 1) {
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
            
        } elseif ($Script:success -eq 0) {
            "虚拟机创建失败……"
            "清理虚拟硬盘文件……"
            Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
        }
    }
}

#脚本主流程，先通过几次检测才开始正式执行脚本流程
if (Test-Path $isoPath) {
    if (Test-Path $vhdxDirPath) {
        if (Test-Path $vhdxPath) {
            "虚拟硬盘文件已经存在……"
        } else {
            vhdxCreate      #创建虚拟硬盘
            vhdxPrepare     #初始化虚拟硬盘，为虚拟硬盘分区
            isoMount        #挂载iso安装镜像
            installWindows  #从挂载的iso镜像中安装Windows到虚拟硬盘并添加引导项
            startVM         #创建并启动虚拟机
        }
    } else {
        "找不到虚拟硬盘存放目录……"
    }
} else {
    "找不到Windows安装镜像……"
}
