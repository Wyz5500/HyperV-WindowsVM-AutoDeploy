$vmName = "Windows VM"
$cpuCore = '4'
$switchName = "Default Switch"
$VHDXDirPath = "C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\"
$VHDXSize = "1TB"
$isoPath = ""
$index = 1

##################################################
#只有上面需要设置，下面的东西不要乱动
##################################################

#自动搜索脚本所在目录下的"unattend.xml"作为应答文件
function unattendProcess {
    $files = Get-ChildItem -Path $PSScriptRoot -Filter *.xml
    foreach ($file in $files) {
        if ($file.Name -eq "autounattend.xml") {
            "在$($PSScriptRoot)中找到应答文件……"
            $null = New-Item -Path "$($ntfsDriverLetter):\Windows\Panther\" -ItemType Directory
            $null = Copy-Item -Path "$($PSScriptRoot)\autounattend.xml" -Destination "$($ntfsDriverLetter):\Windows\Panther\unattend.xml"
        }
    }
}

function startVM {
    #新建虚拟机
    $VM = @{
        Name = $vmName
        Generation = 2
        SwitchName = $SwitchName
        VHDPath = $VHDXPath
    }
    $null = New-VM @VM

    #调整虚拟机设置
    $VMHD = Get-VMHardDiskDrive -VMName $vmName
    Set-VMFirmware -VMName $vmName -FirstBootDevice $VMHD
    Set-VMProcessor -VMName $vmName -Count $cpuCore
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On
    $null = Start-VM -VMName $vmName

    #启动虚拟机
    $null = Start-Process -FilePath "vmconnect.exe" -ArgumentList $('"' + $env:COMPUTERNAME + '"'), $('"' + $vmName + '"')
}

function installWindows {
    #挂载Windows安装镜像并选中。
    "挂载Windows安装镜像……"
    $image = Mount-DiskImage -ImagePath $isoPath -PassThru
    $installer = Get-Volume -DiskImage $image
    #获取Windows映像文件路径，用于Dism安装Windows。
    $wimPath = "$($installer.DriveLetter):\sources\install.wim"
    $esdPath = "$($installer.DriveLetter):\sources\install.esd"

    #新建虚拟硬盘。
    $VHDXPath = "$($VHDXDirPath)$($vmName).vhdx"
    "新建虚拟硬盘……"
    $null = New-VHD -Path $VHDXPath -SizeBytes $VHDXSize -Dynamic

    #挂载虚拟硬盘并选中。
    $VHDX = Mount-VHD -Path $VHDXPath -Passthru
    $disk = Get-Disk -Number $VHDX.DiskNumber 

    #初始化虚拟硬盘。
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT

    #分区，100MB的EFI分区和剩余所有空间的NTFS分区，保存分区对象。
    $efiPartition = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
    "为虚拟硬盘新建EFI分区……"
    $null = Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel 'System' -Force -Confirm:$false
    "为虚拟硬盘新建MSR分区……"
    $null = New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
    $ntfsPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    "为虚拟硬盘新建NTFS分区……"
    $null = Format-Volume -Partition $ntfsPartition -FileSystem NTFS -NewFileSystemLabel $vmName -Force -Confirm:$false

    #从分区对象获取EFI分区和NTFS分区卷标。
    $efiDriverLetter = $(Get-Volume -Partition $efiPartition).DriveLetter
    $ntfsDriverLetter = $(Get-Volume -Partition $ntfsPartition).DriveLetter



    #将Windows安装镜像中的系统安装到虚拟硬盘的NTFS分区，并在EFI分区上设置引导。
    if (Test-Path $wimPath) {
        Dism /Apply-Image /index:$index /ImageFile:"$wimPath" /ApplyDir:"$($ntfsDriverLetter):\"
        if ($LASTEXITCODE -ne 0) {
            "Windows安装失败，正在清理……"
            $null = Dismount-DiskImage -ImagePath $isoPath
            Dismount-VHD -Path $VHDXPath
            Remove-Item -Path $VHDXPath
        } else {
            bcdboot "$($ntfsDriverLetter):\Windows" /s "$($efiDriverLetter):" /f UEFI /l zh-CN
            if ($LASTEXITCODE -ne 0) {
                "Windows引导添加失败，正在清理……"
                $null = Dismount-DiskImage -ImagePath $isoPath
                Dismount-VHD -Path $VHDXPath
                Remove-Item -Path $VHDXPath
            } else {
                unattendProcess
                $null = Dismount-DiskImage -ImagePath $isoPath
                "卸载Windows安装镜像……"
                Dismount-VHD -Path $VHDXPath
                "正在启动虚拟机……"
                startVM
            }
        }
    } elseif (Test-Path $esdPath) {
        Dism /Apply-Image /index:$index /ImageFile:"$esdPath" /ApplyDir:"$($ntfsDriverLetter):\"
        if ($LASTEXITCODE -ne 0) {
            "Windows安装失败，正在清理……"
            $null = Dismount-DiskImage -ImagePath $isoPath
            Dismount-VHD -Path $VHDXPath
            Remove-Item -Path $VHDXPath
        } else {
            bcdboot "$($ntfsDriverLetter):\Windows" /s "$($efiDriverLetter):" /f UEFI /l zh-CN
            if ($LASTEXITCODE -ne 0) {
                "Windows引导添加失败，正在清理……"
                $null = Dismount-DiskImage -ImagePath $isoPath
                Dismount-VHD -Path $VHDXPath
                Remove-Item -Path $VHDXPath
            } else {
                unattendProcess
                $null = Dismount-DiskImage -ImagePath $isoPath
                "卸载Windows安装镜像……"
                Dismount-VHD -Path $VHDXPath
                "正在启动虚拟机……"
                startVM
            }
        }
    } else {
        "找不到Windows映像文件，安装失败，正在清理……"
        $null = Dismount-DiskImage -ImagePath $isoPath
        $null = Dismount-VHD -Path $VHDXPath
        Remove-Item -Path $VHDXPath
    }
}



if (Test-Path $isoPath) {
    if (Test-Path $VHDXDirPath) {
        if (Test-Path "$($VHDXDirPath)$($vmName).vhdx") {
            "虚拟硬盘文件已经存在……"
        } else {
            installWindows
        }
    } else {
        "找不到虚拟硬盘存放目录……"
    }
} else {
    "找不到Windows安装镜像……"
}
