# Read-only local Windows diagnostics. Does not change BIOS, NIC, registry,
# firewall, power settings, services or accounts; never sends a wake packet.
param([string]$OutputDirectory = '', [switch]$LibraryOnly)
$ErrorActionPreference = 'Stop'

function Convert-HardwareSummary {
    param($System, $Board, $CPU, $OS)
    # Explicit whitelist: no host/user names, serials, UUIDs or Windows keys.
    [ordered]@{
        computer = [ordered]@{manufacturer=[string]$System.Manufacturer; model=[string]$System.Model}
        board = [ordered]@{manufacturer=[string]$Board.Manufacturer; product=[string]$Board.Product; version=[string]$Board.Version}
        processors = @($CPU | ForEach-Object { [string]$_.Name })
        windows = [ordered]@{caption=[string]$OS.Caption; version=[string]$OS.Version; build=[string]$OS.BuildNumber; architecture=[string]$OS.OSArchitecture}
        remote_management = [ordered]@{
            status='not_verified'
            note='CPU/ME/LMS presence alone does not prove Intel AMT or configured out-of-band access. Check exact platform and firmware.'
        }
    }
}
function Convert-WakeAdapter {
    param($Adapter, $Power, $WakeArmed, $Properties)
    $magic='unknown'; $armed='unknown'; $shutdown='unknown'
    if ([string]$Power.WakeOnMagicPacket -eq 'Enabled') {$magic='enabled'}
    elseif ([string]$Power.WakeOnMagicPacket -eq 'Disabled') {$magic='disabled'}
    if ($null -ne $WakeArmed) {
        if (@($WakeArmed | ForEach-Object {$_.Trim()}) -contains [string]$Adapter.InterfaceDescription) {$armed='enabled'}
        # Localized powercfg names can differ from InterfaceDescription.
        # No exact match is not reliable negative evidence.
    }
    $values=@($Properties | Where-Object {$_.RegistryKeyword -in @('ShutdownWakeOnLan','S5WakeOnLan')} | ForEach-Object {$_.RegistryValue})
    if ($values.Count -gt 0) {
        $unique=@($values | Select-Object -Unique)
        if ($unique.Count -eq 1 -and [string]$unique[0] -eq '1') {$shutdown='enabled'}
        elseif ($unique.Count -eq 1 -and [string]$unique[0] -eq '0') {$shutdown='disabled'}
    }
    [ordered]@{
        description=[string]$Adapter.InterfaceDescription
        interface_type=[string]$Adapter.InterfaceType
        physical_medium=[string]$Adapter.PhysicalMediaType
        link_state=[string]$Adapter.Status
        driver_version=[string]$Adapter.DriverVersion
        wake_magic_packet=$magic
        wake_armed=$armed
        shutdown_wake=$shutdown
    }
}
if ($LibraryOnly) {return}

# Each CIM operation has a deadline and failures remain explicitly unavailable.
$issues=New-Object 'System.Collections.Generic.List[string]'
function Read-LocalCim([string]$Class) {
    try {Get-CimInstance -ClassName $Class -OperationTimeoutSec 5 -ErrorAction Stop}
    catch {$issues.Add('unavailable_'+$Class); return $null}
}
function Read-PowerCfg([string]$Arguments) {
    try {
        $info=New-Object System.Diagnostics.ProcessStartInfo
        $info.FileName=Join-Path $env:SystemRoot 'System32\powercfg.exe'
        $info.Arguments=$Arguments
        $info.UseShellExecute=$false
        $info.CreateNoWindow=$true
        $info.RedirectStandardOutput=$true
        $info.RedirectStandardError=$true
        $process=New-Object System.Diagnostics.Process
        $process.StartInfo=$info
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync()
        $stderr=$process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(5000)) {try {$process.Kill()} catch {}; $issues.Add('powercfg_timeout');return $null}
        if ($process.ExitCode -ne 0) {$issues.Add('powercfg_unavailable');return $null}
        return $stdout.GetAwaiter().GetResult().Trim()
    } catch {$issues.Add('powercfg_unavailable');return $null}
    finally {if ($process) {$process.Dispose()}}
}
$system=Read-LocalCim 'Win32_ComputerSystem'
$board=Read-LocalCim 'Win32_BaseBoard'
$cpu=@(Read-LocalCim 'Win32_Processor')
$os=Read-LocalCim 'Win32_OperatingSystem'
$hardware=Convert-HardwareSummary -System $system -Board $board -CPU $cpu -OS $os
$armedText=Read-PowerCfg '/devicequery wake_armed'
$armed=$null
if ($null -ne $armedText) {$armed=@($armedText -split "`r?`n")}
$sleep=Read-PowerCfg '/a'
$nics=@()
try {
    foreach ($nic in @(Get-NetAdapter -Physical -ErrorAction Stop)) {
        $power=$null; $properties=@()
        try {$power=$nic | Get-NetAdapterPowerManagement -ErrorAction Stop} catch {$issues.Add('adapter_power_unavailable')}
        try {$properties=@($nic | Get-NetAdapterAdvancedProperty -AllProperties -ErrorAction Stop)} catch {$issues.Add('adapter_properties_unavailable')}
        $nics+=Convert-WakeAdapter -Adapter $nic -Power $power -WakeArmed $armed -Properties $properties
    }
} catch {$issues.Add('physical_adapter_scan_unavailable')}
$fastStartup='unknown'
try {
    $raw=Get-ItemPropertyValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -ErrorAction Stop
    if ($raw -eq 1) {$fastStartup='enabled'} elseif ($raw -eq 0) {$fastStartup='disabled'}
} catch {$issues.Add('fast_startup_unavailable')}
$report=[ordered]@{
    schema_version=1
    collected_at=[DateTimeOffset]::Now.ToString('o')
    mode='read_only_no_wake_packet'
    hardware=$hardware
    adapters=$nics
    fast_startup_config=$fastStartup
    fast_startup_effective='not_verified'
    available_power_states=$sleep
    unavailable=@($issues | Select-Object -Unique)
    limits=@('BIOS and standby NIC power are not verified by this report.','Enabled WOL settings do not prove internet delivery or physical wake.','No automatic AMT or S5 support verdict; hardware and live acceptance are required.')
}
if (!$OutputDirectory) {
    $OutputDirectory=Join-Path ([Environment]::GetFolderPath('Desktop')) ('RDesk-Wake-Check-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,6))
}
if (Test-Path $OutputDirectory) {throw 'Output directory already exists; choose a new empty path.'}
[void](New-Item -Path $OutputDirectory -ItemType Directory)
$encoding=New-Object System.Text.UTF8Encoding($true)
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'wake-readiness.json'),($report | ConvertTo-Json -Depth 10),$encoding)
$text=@(
    'RDesk 远程开机只读检测'
    '本工具没有更改任何系统、网卡或电源设置，没有发出开机指令。'
    ''
    ('主板：'+$hardware.board.manufacturer+' '+$hardware.board.product+' '+$hardware.board.version)
    ('整机：'+$hardware.computer.manufacturer+' '+$hardware.computer.model)
    ('CPU：'+($hardware.processors -join '; '))
    ('Windows：'+$hardware.windows.caption+' '+$hardware.windows.build)
    ''
    '以下状态：enabled=已开启，disabled=未开启，unknown=未能确定。'
    ('快速启动注册表配置：'+$fastStartup+'（不代表当前电源状态支持或实际生效）')
)
foreach ($nic in $nics) {
    $text+=@('';('网卡：'+$nic.description);('连接：'+$nic.link_state+'；接口类型：'+$nic.interface_type);('魔术包唤醒：'+$nic.wake_magic_packet);('系统已授权唤醒：'+$nic.wake_armed);('驱动关机唤醒选项：'+$nic.shutdown_wake))
}
$text+=@('';'重要：这些设置不等于外网一定能开机。仍需路由器/常在线设备代发，或支持并配置了硬件带外管理的电脑。';'CPU 型号不能单独证明支持 AMT；本报告不自动宣称支持。';'BIOS、关机网卡供电和真实开机结果需另行核验。';'报告不包含电脑名称、账号、序列号、Windows 产品密钥、MAC 或 IP 地址。';('未能读取：'+($report.unavailable -join ', ')))
[IO.File]::WriteAllLines((Join-Path $OutputDirectory '检测结果.txt'),[string[]]$text,$encoding)
Write-Output '只读报告已保存。没有修改系统设置，也没有发送开机指令。'
