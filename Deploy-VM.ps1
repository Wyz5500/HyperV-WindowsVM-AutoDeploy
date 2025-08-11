#设置虚拟机名称：
$vmName = "Windows 11"

#设置cpu核心数，不能超过主机逻辑核心数。
$cpuCore = '4'

#设置虚拟网络交换机
$switchName = "Default Switch"

#设置保存虚拟硬盘的目录，末尾要有'\'。
$VHDXDirPath = "D:\Virtual Hard Disks\"

#设置虚拟机虚拟硬盘最大空间，不能超过2048TB，单位可以是'GB'、'TB'。
$VHDXSize = "64GB"

#设置Windows安装镜像位置。
$isoPath = "D:\Files\系统\镜像\原版\zh-cn_windows_11_enterprise_ltsc_2024_x64_dvd_cff9cd2d.iso"

#设置索引，用于指定Windows版本，可以用Dism++查看Windows版本对应的索引。或者使用命令："Dism /Get-ImageInfo /ImageFile:<install.wim/install.esd文件所在路径>"。
$index = 1

#设置Windows用户名，不想选就用"$env:USERNAME"，即当前用户的用户名。可以自己修改，要加双引号。
$userName = "$env:USERNAME"

#设置Windows用户登录密码。
$password = "2333"

#设置为虚拟机启动时分配的内存，不能超过物理机内存上限，一般不需要设置
#$ram = 8GB

##################################################
#只有上面需要设置，下面的东西不要乱动
##################################################
function unattendProcess {
    $tempXmlPath = "$($PSScriptRoot)\fihbfaygfwiygfiuawgfuawygf.xml"
    $targetDirPath = "$($ntfsDriverLetter):\Windows\Panther\"
    $targetPath = "$($targetDirPath)Unattend.xml"

    $xmlContent = @'
<?xml version="1.0" encoding="utf-8"?>
<unattend xmlns="urn:schemas-microsoft-com:unattend" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
	<settings pass="offlineServicing"></settings>
	<settings pass="windowsPE">
		<component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
			<SetupUILanguage>
				<UILanguage>zh-CN</UILanguage>
			</SetupUILanguage>
			<InputLocale>0804:{81d4e9c9-1d3b-41bc-9e6c-4b40bf79e35e}{fa550b04-5ad7-411f-a5ac-ca038ec515d7};0409:00000409</InputLocale>
			<SystemLocale>zh-Hans-CN</SystemLocale>
			<UILanguage>zh-CN</UILanguage>
			<UserLocale>zh-Hans-CN</UserLocale>
		</component>
		<component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
			<UserData>
				<ProductKey>
					<Key>00000-00000-00000-00000-00000</Key>
					<WillShowUI>Always</WillShowUI>
				</ProductKey>
				<AcceptEula>true</AcceptEula>
			</UserData>
			<UseConfigurationSet>false</UseConfigurationSet>
		</component>
	</settings>
	<settings pass="generalize"></settings>
	<settings pass="specialize">
		<component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
			<RunSynchronous>
				<RunSynchronousCommand wcm:action="add">
					<Order>1</Order>
					<Path>powershell.exe -WindowStyle Normal -NoProfile -Command "$xml = [xml]::new(); $xml.Load('C:\Windows\Panther\unattend.xml'); $sb = [scriptblock]::Create( $xml.unattend.Extensions.ExtractScript ); Invoke-Command -ScriptBlock $sb -ArgumentList $xml;"</Path>
				</RunSynchronousCommand>
				<RunSynchronousCommand wcm:action="add">
					<Order>2</Order>
					<Path>powershell.exe -WindowStyle Normal -NoProfile -Command "Get-Content -LiteralPath 'C:\Windows\Setup\Scripts\Specialize.ps1' -Raw | Invoke-Expression;"</Path>
				</RunSynchronousCommand>
			</RunSynchronous>
		</component>
	</settings>
	<settings pass="auditSystem"></settings>
	<settings pass="auditUser"></settings>
	<settings pass="oobeSystem">
		<component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
			<InputLocale>0804:{81d4e9c9-1d3b-41bc-9e6c-4b40bf79e35e}{fa550b04-5ad7-411f-a5ac-ca038ec515d7};0409:00000409</InputLocale>
			<SystemLocale>zh-Hans-CN</SystemLocale>
			<UILanguage>zh-CN</UILanguage>
			<UserLocale>zh-Hans-CN</UserLocale>
		</component>
		<component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS">
			<UserAccounts>
				<LocalAccounts>
					<LocalAccount wcm:action="add">
						<Name>${userName}</Name>
						<DisplayName></DisplayName>
						<Group>Administrators</Group>
						<Password>
							<Value>${password}</Value>
							<PlainText>true</PlainText>
						</Password>
					</LocalAccount>
				</LocalAccounts>
			</UserAccounts>
			<AutoLogon>
				<Username>${userName}</Username>
				<Enabled>true</Enabled>
				<LogonCount>1</LogonCount>
				<Password>
					<Value>${password}</Value>
					<PlainText>true</PlainText>
				</Password>
			</AutoLogon>
			<OOBE>
				<ProtectYourPC>3</ProtectYourPC>
				<HideEULAPage>true</HideEULAPage>
				<HideWirelessSetupInOOBE>true</HideWirelessSetupInOOBE>
				<HideOnlineAccountScreens>false</HideOnlineAccountScreens>
			</OOBE>
			<FirstLogonCommands>
				<SynchronousCommand wcm:action="add">
					<Order>1</Order>
					<CommandLine>powershell.exe -WindowStyle Normal -NoProfile -Command "Get-Content -LiteralPath 'C:\Windows\Setup\Scripts\FirstLogon.ps1' -Raw | Invoke-Expression;"</CommandLine>
				</SynchronousCommand>
			</FirstLogonCommands>
		</component>
	</settings>
	<Extensions xmlns="https://schneegans.de/windows/unattend-generator/">
		<ExtractScript>
param(
    [xml] $Document
);

foreach( $file in $Document.unattend.Extensions.File ) {
    $path = [System.Environment]::ExpandEnvironmentVariables( $file.GetAttribute( 'path' ) );
    mkdir -Path( $path | Split-Path -Parent ) -ErrorAction 'SilentlyContinue';
    $encoding = switch( [System.IO.Path]::GetExtension( $path ) ) {
        { $_ -in '.ps1', '.xml' } { [System.Text.Encoding]::UTF8; }
        { $_ -in '.reg', '.vbs', '.js' } { [System.Text.UnicodeEncoding]::new( $false, $true ); }
        default { [System.Text.Encoding]::Default; }
    };
    $bytes = $encoding.GetPreamble() + $encoding.GetBytes( $file.InnerText.Trim() );
    [System.IO.File]::WriteAllBytes( $path, $bytes );
}
		</ExtractScript>
		<File path="C:\Windows\Setup\Scripts\Specialize.ps1">
$scripts = @(
	{
		net.exe accounts /maxpwage:UNLIMITED;
	};
);

&amp; {
  [float] $complete = 0;
  [float] $increment = 100 / $scripts.Count;
  foreach( $script in $scripts ) {
    Write-Progress -Activity 'Running scripts to customize your Windows installation. Do not close this window.' -PercentComplete $complete;
    '*** Will now execute command &#xAB;{0}&#xBB;.' -f $(
      $str = $script.ToString().Trim() -replace '\s+', ' ';
      $max = 100;
      if( $str.Length -le $max ) {
        $str;
      } else {
        $str.Substring( 0, $max - 1 ) + '&#x2026;';
      }
    );
    $start = [datetime]::Now;
    &amp; $script;
    '*** Finished executing command after {0:0} ms.' -f [datetime]::Now.Subtract( $start ).TotalMilliseconds;
    "`r`n" * 3;
    $complete += $increment;
  }
} *&gt;&amp;1 &gt;&gt; "C:\Windows\Setup\Scripts\Specialize.log";
		</File>
		<File path="C:\Windows\Setup\Scripts\FirstLogon.ps1">
$scripts = @(
	{
		Set-ItemProperty -LiteralPath 'Registry::HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name 'AutoLogonCount' -Type 'DWord' -Force -Value 0;
	};
);

&amp; {
  [float] $complete = 0;
  [float] $increment = 100 / $scripts.Count;
  foreach( $script in $scripts ) {
    Write-Progress -Activity 'Running scripts to finalize your Windows installation. Do not close this window.' -PercentComplete $complete;
    '*** Will now execute command &#xAB;{0}&#xBB;.' -f $(
      $str = $script.ToString().Trim() -replace '\s+', ' ';
      $max = 100;
      if( $str.Length -le $max ) {
        $str;
      } else {
        $str.Substring( 0, $max - 1 ) + '&#x2026;';
      }
    );
    $start = [datetime]::Now;
    &amp; $script;
    '*** Finished executing command after {0:0} ms.' -f [datetime]::Now.Subtract( $start ).TotalMilliseconds;
    "`r`n" * 3;
    $complete += $increment;
  }
} *&gt;&amp;1 &gt;&gt; "C:\Windows\Setup\Scripts\FirstLogon.log";
		</File>
	</Extensions>
</unattend>
'@

    #创建临时文件，用于将原内容替换为设置的内容
    Set-Content -Path $tempXmlPath -Value $xmlContent -Encoding utf8
    $result = Get-Content -LiteralPath $tempXmlPath | ForEach-Object {
        $line = $_
        $line = $line.Replace('${userName}',"$userName")
        $line = $line.Replace('${password}',"$password")
        #$line = $line.Replace('${vmName}', "$vmName")
        $line
    }

    #将替换后的内容写入应答文件
    "写入应答文件……"
    $unattendDir = New-Item -Path $targetDirPath -ItemType Directory
    $unattendFile = New-item -Path $targetPath
    Set-Content -LiteralPath $targetPath -Value $result

    #删除临时文件
    Remove-Item -Path $tempXmlPath
}

function startVM {
    #新建虚拟机
    New-VM -Name $vmName `
    -Generation 2 `
    -SwitchName $SwitchName `
    -VHDPath $VHDXPath `
    #-MemoryStartupBytes $ram `

    #设置虚拟机参数
    Set-VMProcessor -VMName $vmName -Count $cpuCore
    $VMHD = Get-VMHardDiskDrive -VMName $vmName
    Set-VMFirmware -VMName $vmName -FirstBootDevice $VMHD
    Set-VMFirmware -VMName $vmName -EnableSecureBoot On
    Start-VM -VMName $vmName
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
    $VHDXInfo = New-VHD -Path $VHDXPath -SizeBytes $VHDXSize -Dynamic

    #挂载虚拟硬盘并选中。
    $VHDX = Mount-VHD -Path $VHDXPath -Passthru
    $disk = Get-Disk -Number $VHDX.DiskNumber 

    #初始化虚拟硬盘。
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT

    #分区，100MB的EFI分区和剩余所有空间的NTFS分区，保存分区对象。
    $efiPartition = New-Partition -DiskNumber $disk.Number -Size 200MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
    "为虚拟硬盘新建EFI分区……"
    $efiPartitionInfo = Format-Volume -Partition $efiPartition -FileSystem FAT32 -NewFileSystemLabel 'System' -Force -Confirm:$false
    "为虚拟硬盘新建MSR分区……"
    $msrPartition = New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
    $ntfsPartition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    "为虚拟硬盘新建NTFS分区……"
    $ntfsPartitionInfo = Format-Volume -Partition $ntfsPartition -FileSystem NTFS -NewFileSystemLabel $vmName -Force -Confirm:$false

    #从分区对象获取EFI分区和NTFS分区卷标。
    $efiDriverLetter = $(Get-Volume -Partition $efiPartition).DriveLetter
    $ntfsDriverLetter = $(Get-Volume -Partition $ntfsPartition).DriveLetter



    #将Windows安装镜像中的系统安装到虚拟硬盘的NTFS分区，并在EFI分区上设置引导。
    if (Test-Path $wimPath) {
        Dism /Apply-Image /index:$index /ImageFile:"$wimPath" /ApplyDir:"$($ntfsDriverLetter):\"
        if ($LASTEXITCODE -ne 0) {
            "Windows安装失败，正在清理……"
            $isoInfo = Dismount-DiskImage -ImagePath $isoPath
            Dismount-VHD -Path $VHDXPath
            Remove-Item -Path $VHDXPath
        } else {
            bcdboot "$($ntfsDriverLetter):\Windows" /s "$($efiDriverLetter):" /f UEFI /l zh-CN
            if ($LASTEXITCODE -ne 0) {
                "Windows引导添加失败，正在清理……"
                $isoInfo = Dismount-DiskImage -ImagePath $isoPath
                Dismount-VHD -Path $VHDXPath
                Remove-Item -Path $VHDXPath
            } else {
                unattendProcess
                $isoInfo = Dismount-DiskImage -ImagePath $isoPath
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
            $isoInfo = Dismount-DiskImage -ImagePath $isoPath
            Dismount-VHD -Path $VHDXPath
            Remove-Item -Path $VHDXPath
        } else {
            bcdboot "$($ntfsDriverLetter):\Windows" /s "$($efiDriverLetter):" /f UEFI /l zh-CN
            if ($LASTEXITCODE -ne 0) {
                "Windows引导添加失败，正在清理……"
                $isoInfo = Dismount-DiskImage -ImagePath $isoPath
                Dismount-VHD -Path $VHDXPath
                Remove-Item -Path $VHDXPath
            } else {
                unattendProcess
                $isoInfo = Dismount-DiskImage -ImagePath $isoPath
                "卸载Windows安装镜像……"
                Dismount-VHD -Path $VHDXPath
                "正在启动虚拟机……"
                startVM
            }
        }
    } else {
        "找不到Windows映像文件，安装失败，正在清理……"
        $isoInfo = Dismount-DiskImage -ImagePath $isoPath
        $VHDXInfo = Dismount-VHD -Path $VHDXPath
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
