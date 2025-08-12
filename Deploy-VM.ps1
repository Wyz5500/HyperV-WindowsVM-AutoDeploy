$VHDXDirPath = "$((Get-VMHost).VirtualHardDiskPath)\"
$vmName = "Windows 11"
$cpuCore = '4'
$switchName = "Default Switch"
$VHDXSize = "1TB"
$isoPath = ""
$index = 1


##################################################
#只有上面需要设置，下面的东西不要乱动
##################################################

$VHDXPath = "$($VHDXDirPath)$($vmName).vhdx"

function vhdxPrepare {
    #挂载Windows安装镜像并选中。
    "挂载Windows安装镜像……"
    $image = Mount-DiskImage -ImagePath $isoPath -PassThru
    $installer = Get-Volume -DiskImage $image
    #获取Windows映像文件路径，用于Dism安装Windows。
    $Script:wimPath = "$($installer.DriveLetter):\sources\install.wim"
    $Script:esdPath = "$($installer.DriveLetter):\sources\install.esd"

    "新建虚拟硬盘`"$($VHDXPath)`"……"
    $null = New-VHD -Path $VHDXPath -SizeBytes $VHDXSize -Dynamic

    #挂载虚拟硬盘并选中。
    $VHDX = Mount-VHD -Path $VHDXPath -Passthru
    $disk = Get-Disk -Number $VHDX.DiskNumber 

    #初始化虚拟硬盘。
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT

    #分区，100MB的EFI分区和剩余所有空间的NTFS分区，保存分区对象。
    $efiPartition = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
    "为虚拟硬盘新建EFI分区……"
    $null = Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel 'SYSTEM' -Force -Confirm:$false
    "为虚拟硬盘新建MSR分区……"
    $null = New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
    $ntfsPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    "为虚拟硬盘新建NTFS分区……"
    $null = Format-Volume -Partition $ntfsPartition -FileSystem NTFS -NewFileSystemLabel $vmName -Force -Confirm:$false

    #从分区对象获取EFI分区和NTFS分区卷标。
    $Script:efiDriverLetter = $(Get-Volume -Partition $efiPartition).DriveLetter
    $Script:ntfsDriverLetter = $(Get-Volume -Partition $ntfsPartition).DriveLetter
}

function installWindows {
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
            }
        }
    } else {
        "找不到Windows映像文件……"
    }
}

function unattendProcess {
    $files = Get-ChildItem -Path $PSScriptRoot -Filter *.xml
    foreach ($file in $files) {
        if ($file.Name -eq "autounattend.xml") {
            "在`"$($PSScriptRoot)`"中找到`"autounattend.xml`"……"
            $null = New-Item -Path "$($ntfsDriverLetter):\Windows\Panther\" -ItemType Directory
            $null = Copy-Item -Path "$($PSScriptRoot)\autounattend.xml" -Destination "$($ntfsDriverLetter):\Windows\Panther\unattend.xml"
        } else {
            "没有在`"$($PSScriptRoot)`"中找到`"autounattend.xml`"……"
        }
    }
}

function freeResources {
    #释放不再需要的资源
    "卸载Windows安装镜像……"
    $null = Dismount-DiskImage -ImagePath $isoPath
    $null = Dismount-VHD -Path $VHDXPath

    if ($success -eq 1) {
        "启动虚拟机……"
        startVM
    } else {
        "清理虚拟硬盘文件……"
        Remove-Item -Path $VHDXPath
    }
}

function startVM {
    #设置虚拟机创建信息
    $VM = @{
        Name = $vmName              #虚拟机名称
        Generation = 2              #虚拟机代数，一般选2
        SwitchName = $SwitchName    #虚拟交换机名称
        VHDPath = $VHDXPath         #虚拟硬盘路径
    }

    #创建虚拟机
    $null = New-VM @VM              

    #调整虚拟机设置
    $VMHD = Get-VMHardDiskDrive -VMName $vmName                             #获取虚拟机内部VHDX信息
    Set-VMFirmware -VMName $vmName -FirstBootDevice $VMHD                   #设置启动固件为VHDX
    Set-VMProcessor -VMName $vmName -Count $cpuCore                         #设置CPU核心数量
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On                     #设置虚拟机使用安全启动
    Set-VMProcessor -VMName $vmName -ExposeVirtualizationExtensions $true   #开启虚拟机的嵌套虚拟化
    $null = Start-VM -VMName $vmName                                        #启动虚拟机

    #打开虚拟机连接会话
    $null = Start-Process -FilePath "vmconnect.exe" -ArgumentList $('"' + $env:COMPUTERNAME + '"'), $('"' + $vmName + '"')
}

if (Test-Path $isoPath) {
    if (Test-Path $VHDXDirPath) {
        if (Test-Path $VHDXPath) {
            "虚拟硬盘文件已经存在……"
        } else {
            vhdxPrepare
            installWindows
            freeResources
        }
    } else {
        "找不到虚拟硬盘存放目录……"
    }
} else {
    "找不到Windows安装镜像……"
}
