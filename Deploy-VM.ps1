##################################################

#设置部分
$vmName = "Windows 11"
$isoPath = "D:\Files\系统\镜像\定制\LTSC 2024\26100.4946\zh-cn_windows_11_enterprise_ltsc_2024_x64_dvd_cff9cd2d.iso"
$imageIndex = 1

##################################################

#可选设置，绝大多数情况下不需要修改，Windows Server主机用户需要修改switchName
$switchName = "Default Switch"
$vmProcessorCount = [Int16]([System.Environment]::ProcessorCount / 2)
$vhdxPath = [System.IO.Path]::Combine("$((Get-VMHost).VirtualHardDiskPath)", "$vmName.vhdx")
$vmGeneration = 2
$vhdxSize = 1TB
$unattendedFilePath = "$($PSScriptRoot)\autounattend.xml"
$memory = 512MB

##################################################

#设置脚本遇到异常情况的默认行为
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSDefaultParameterValues = @{'*:ErrorAction'='Stop'}

##################################################

#函数定义部分
function vmCreate {
    param (
        [string]$vmName,
        [string]$vhdxPath,
        [Int64]$vhdxSize,
        [string]$switchName,
        [Int16]$vmGeneration
    )
    $vmInfo = @{
        Name = $vmName
        NewVHDPath = $vhdxPath
        NewVHDSizeBytes = $vhdxSize
        Generation = $vmGeneration
        BootDevice = "VHD"
        SwitchName = $switchName
    }
    Write-Host "新建虚拟机和虚拟硬盘……" -ForegroundColor DarkGray
    $null = New-VM @vmInfo 
}
function vmSet {
    param (
        [string]$vmName,
        [Int16]$vmProcessorCount,
        [Int64]$memory
    )
    $vmSetting = @{
        Name = $vmName
        ProcessorCount = $vmProcessorCount
        MemoryStartupBytes = $memory
    }
    Write-Host "调整虚拟机设置……" -ForegroundColor DarkGray
    $null = Set-VM @vmSetting
}
function installWindows {
    param (
        [string]$isoPath,
        [string]$vhdxPath,
        [int16]$imageIndex,
        [string]$unattendedFilePath
    )
    Write-Host "挂载 iso 镜像……" -ForegroundColor DarkGray
    $image = Mount-DiskImage -ImagePath $isoPath -PassThru

    #定义将要用到的变量
    $installer = Get-Volume -DiskImage $image | Select-Object -First 1
    $windowsImage = "$($installer.DriveLetter):\sources\install.esd"
    if (-not (Test-Path $windowsImage)) {
        $windowsImage = "$($installer.DriveLetter):\sources\install.wim"
    }
    #$version = Get-WindowsImage -ImagePath $windowsImage

    Write-Host "挂载虚拟硬盘……" -ForegroundColor DarkGray
    $vhdx = Mount-VHD -Path $vhdxPath -Passthru     #vhdx对象，vhdx的挂载情况
    $disk = Get-Disk -Number $vhdx.DiskNumber       #disk对象，disk的具体信息

    Write-Host "初始化虚拟硬盘……" -ForegroundColor DarkGray
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT

    Write-Host "为虚拟硬盘新建引导分区……" -ForegroundColor DarkGray
    $efi = New-Partition -DiskNumber $disk.Number -Size 100MB -GptType "{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}" -AssignDriveLetter
    $null = Format-Volume -Partition $efi -FileSystem FAT32

    Write-Host "为虚拟硬盘新建系统分区……" -ForegroundColor DarkGray
    $ntfs = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    $null = Format-Volume -Partition $ntfs -FileSystem NTFS -NewFileSystemLabel $vmName

    Write-Host "安装 Windows 到虚拟硬盘……" -ForegroundColor DarkGray
    $windowsDir = "$((Get-Volume -Partition $ntfs).DriveLetter):\"
    $null = $windowsDir

    #Dism /Apply-Image /index:"$imageIndex" /ImageFile:"$windowsImage" /ApplyDir:"$windowsDir"
    #使用wimlib加速应用映像
    & "$($PSScriptRoot)\wimlib-imagex.exe" apply "$($windowsImage)" $imageIndex "$($windowsDir)"
    if ($LASTEXITCODE -ne 0) {throw "Windows 安装失败……"}

    Write-Host "为虚拟硬盘添加 Windows 启动引导……" -ForegroundColor DarkGray
    $efiDir = "$((Get-Volume -Partition $efi).DriveLetter):\"
    $null = $efiDir
    $windowsPath = [System.IO.Path]::Combine($windowsDir, "Windows")
    bcdboot "$windowsPath" /s "$efiDir" /f UEFI /l zh-CN *>$null
    if ($LASTEXITCODE -ne 0) {throw "引导项添加失败……"}

    Write-Host "尝试搜索并应用 Autounattend.xml……" -ForegroundColor DarkGray
    if (Test-Path -Path $unattendedFilePath) {
        $null = New-Item -Path "$($windowsPath)\Panther\" -ItemType Directory
        $null = Copy-Item -Path "$unattendedFilePath" -Destination "$($windowsPath)\Panther\unattend.xml"
    }

    Write-Host "卸载 iso 镜像和虚拟硬盘……" -ForegroundColor DarkGray
    $null = Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue
    $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
}
function vmStart {
    param (
        [string]$vmName
    )
    Write-Host "正在启动虚拟机……" -ForegroundColor DarkGray
    $null = Start-VM -Name $vmName
    Start-Process -FilePath "vmconnect.exe" -ArgumentList "`"$env:COMPUTERNAME`"", "`"$vmName`""
}

##################################################

#参数设置部分
$vmCreateParam = @{
    vmName = $vmName
    vhdxPath = $vhdxPath
    vhdxSize = $vhdxSize
    switchName = $switchName
    vmGeneration = $vmGeneration
}
$vmSetParam = @{
    vmName = $vmName
    vmProcessorCount = $vmProcessorCount
    memory = $memory
}
$installWindowsParam = @{
    isoPath = $isoPath
    vhdxPath = $vhdxPath
    imageIndex = $imageIndex
    unattendedFilePath = $unattendedFilePath
}

##################################################

#函数执行部分
[void]($vmExist = Get-VM -Name $vmName -ErrorAction SilentlyContinue)
if (Test-Path -Path $vhdxPath) {
    Write-Host "虚拟硬盘文件 `"$($vhdxPath)`" 已存在……" -ForegroundColor Red
} elseif ($vmExist) {
    Write-Host "存在同名虚拟机 `"$($vmName)`"……" -ForegroundColor Red
} else {
    try {
        $start = Get-Date
        vmCreate @vmCreateParam
        vmSet @vmSetParam
        installWindows @installWindowsParam
        vmStart $vmName
        $end = Get-Date
        $time = $end - $start
        Write-Host "虚拟机部署完成，耗时 $([Int16]$($time.TotalSeconds)) 秒" -ForegroundColor Green
    }
    catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        Write-Host "正在清理……" -ForegroundColor DarkGray
        $null = Dismount-VHD -Path $vhdxPath -ErrorAction SilentlyContinue
        $null = Dismount-DiskImage -ImagePath $isoPath -ErrorAction SilentlyContinue
        Stop-VM -Name $vmName -ErrorAction SilentlyContinue *>$null
        $null = Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
        $null = Remove-Item -Path $vhdxPath -ErrorAction SilentlyContinue
    }
}

##################################################