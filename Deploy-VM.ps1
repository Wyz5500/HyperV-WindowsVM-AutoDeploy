$VHDXDirPath = "$((Get-VMHost).VirtualHardDiskPath)\"
$vmName = "Windows 10"
$cpuCore = 10
$switchName = "Default Switch"
$VHDXSize = 64GB
$isoPath = "D:\Files\系统\镜像\原版\zh-cn_windows_10_enterprise_ltsc_2021_x64_dvd_033b7312.iso"
$index = 1

##################################################
#只有上面需要设置，下面的东西不要乱动
##################################################

$VHDXPath = "$($VHDXDirPath)$($vmName).vhdx"
$Script:success = 1

function vhdxCreate {
    try {
        "创建虚拟硬盘`"$($VHDXPath)`"……"
        $null = New-VHD -Path $VHDXPath -SizeBytes $VHDXSize -Dynamic -ErrorAction Stop
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
            $VHDX = Mount-VHD -Path $VHDXPath -Passthru -ErrorAction Stop
            $disk = Get-Disk -Number $VHDX.DiskNumber -ErrorAction Stop

            try {
                #初始化虚拟硬盘。
                Initialize-Disk -Number $disk.Number -PartitionStyle GPT -ErrorAction Stop

                #分区，200MB的EFI分区和剩余所有空间的NTFS分区，保存分区对象。
                $efiPartition = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter -ErrorAction Stop
                "为虚拟硬盘新建EFI分区……"
                $null = Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel 'SYSTEM' -Force -Confirm:$false -ErrorAction Stop
                "为虚拟硬盘新建MSR分区……"
                $null = New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}' -ErrorAction Stop
                $ntfsPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter -ErrorAction Stop
                "为虚拟硬盘新建NTFS分区……"
                $null = Format-Volume -Partition $ntfsPartition -FileSystem NTFS -NewFileSystemLabel $vmName -Force -Confirm:$false -ErrorAction Stop

                #从分区对象获取EFI分区和NTFS分区卷标。
                $Script:efiDriverLetter = $(Get-Volume -Partition $efiPartition).DriveLetter
                $Script:ntfsDriverLetter = $(Get-Volume -Partition $ntfsPartition).DriveLetter

                $Script:success = 1
            }
            catch {
                Write-Warning $_.Exception.Message
                "虚拟硬盘分区失败……"
                "清理虚拟硬盘文件……"
                $null = Dismount-VHD -Path $VHDXPath
                Remove-Item -Path $VHDXPath -ErrorAction SilentlyContinue
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
            $Script:success = 1
        }
        catch {
            Write-Warning $_.Exception.Message
            "挂载Windows安装镜像失败……"
            "清理虚拟硬盘文件……"
            $null = Dismount-VHD -Path $VHDXPath
            Remove-Item -Path $VHDXPath -ErrorAction SilentlyContinue
            $Script:success = 0
        }
    }
}

function installWindows {
    if ($Script:success -eq 1) {
        #将Windows安装镜像中的系统安装到虚拟硬盘的NTFS分区，并在EFI分区上设置引导。
        $Script:success = 0
        if (Test-Path $wimPath) {
            Dism /Apply-Image /index:$index /ImageFile:"$wimPath" /ApplyDir:"$($ntfsDriverLetter):\"
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
                    $null = Dismount-DiskImage -ImagePath $isoPath
                    $null = Dismount-VHD -Path $VHDXPath
                }
            }
        } elseif (Test-Path $esdPath) {
            Dism /Apply-Image /index:$index /ImageFile:"$esdPath" /ApplyDir:"$($ntfsDriverLetter):\"
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
                    $null = Dismount-DiskImage -ImagePath $isoPath
                    $null = Dismount-VHD -Path $VHDXPath
                }
            }
        } else {
            "找不到Windows映像文件……"
        }

        if ($Script:success -eq 0) {
            "卸载Windows安装镜像……"
            $null = Dismount-DiskImage -ImagePath $isoPath
            "清理虚拟硬盘文件……"
            $null = Dismount-VHD -Path $VHDXPath
            Remove-Item -Path $VHDXPath -ErrorAction SilentlyContinue
        }
    }
}

function unattendProcess {
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
        $VM = @{
            Name = $vmName              #虚拟机名称
            Generation = 2              #虚拟机代数，一般选2
            SwitchName = $SwitchName    #虚拟交换机名称
            VHDPath = $VHDXPath         #虚拟硬盘路径
        }

        try {
            "创建虚拟机……"
            $null = New-VM @VM -ErrorAction Stop
            $VMHD = Get-VMHardDiskDrive -VMName $vmName                             #获取虚拟机内部VHDX信息
            Set-VMFirmware -VMName $vmName -FirstBootDevice $VMHD                   #设置启动固件为VHDX
            Set-VMProcessor -VMName $vmName -Count $cpuCore                         #设置CPU核心数量
            Set-VMFirmware -VMName $vmName -EnableSecureBoot On                     #设置虚拟机使用安全启动
            Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true   #开启虚拟机的嵌套虚拟化
            $Script:success = 1
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
                Remove-VM -Name $vmName -Force
                "清理虚拟硬盘文件……"
                Remove-Item -Path $VHDXPath -ErrorAction SilentlyContinue
            }
            
        } elseif ($Script:success -eq 0) {
            "虚拟机创建失败……"
            "清理虚拟硬盘文件……"
            Remove-Item -Path $VHDXPath -ErrorAction SilentlyContinue
        }
    }
}

if (Test-Path $isoPath) {
    if (Test-Path $VHDXDirPath) {
        if (Test-Path $VHDXPath) {
            "虚拟硬盘文件已经存在……"
        } else {
            vhdxCreate
            vhdxPrepare
            isoMount
            installWindows
            startVM
        }
    } else {
        "找不到虚拟硬盘存放目录……"
    }
} else {
    "找不到Windows安装镜像……"
}
