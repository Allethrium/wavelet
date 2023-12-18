# Powershell script which in theory should be suitable for converting a standard windows client into an UltraGrid/Wavelet decoder.
# Not recommended - The aggressive update installation and automated restarts enforced by Microsoft will likely result in unpredictable system resets.

Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service sshd -StartupType Automatic


# rename machine
# get device serial number and generate a sha256 hash
Get-WmiObject -Class Win32_BIOS | Select-Object -Property SerialNumber
$hasher = [System.Security.Cryptography.HashAlgorithm]::Create('sha256')
$hash = $hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($ClearString))
$hashString = [System.BitConverter]::ToString($hash)
$hashString.Replace('-', '')
$str in ($hashString) {
    $str.subString(0, [System.Math]::Min(4, $str.Length))
}
Rename-Computer "$str.wavelet.local"

# Download UG Windows Client
# Source URL
$url = "https://github.com/CESNET/UltraGrid/releases/download/continuous/UltraGrid-continuous-win64.zip"

# Destation file
$dest = [Environment]::GetFolderPath("Downloads")
# Download the file
Invoke-WebRequest -Uri $url -OutFile $dest
# Extract and place in appropriate installation directory
Expand-Archive UltraGrid-continuous-win64.zip -DestinationPath $dest\UltraGrid-Continuous


# add UltraGrid to safe programs on smartscreen
# ??  turn it off?  sounds like a bad idea.


#connect to wifi
netsh wlan add profile filename=Wi-Fi-Wavelet-1.xml user=all


#enable autologin & set second-stage (IE normal startup operations script)
$Registry = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
Set-ItemProperty $RegistryPath 'AutoAdminLogon' -Value "1" -Type String 
Set-ItemProperty $RegistryPath 'DefaultUsername' -Value "ug" -type String 
Set-ItemProperty $RegistryPath 'DefaultPassword' -Value "60C:ultragrid" -type String


#Generate task
$action = New-ScheduledTaskAction -Execute 'uv -d vulkan_sdl2:fs'
$trigger = New-ScheduledTaskTrigger -AtLogOn -User ug 
Register-SheduledTask -Action $action -Trigger $trigger -TaskPath "ugTasks" -TaskName "UltraGrid Decoder" -Description "Runs the UltraGrid client to run as a Wavelet system decoder"

# Reboot
Restart-Computer -Force
