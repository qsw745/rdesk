$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\collect-wake-readiness.ps1') -LibraryOnly

function Assert-True($Condition, $Message) {
    if (!$Condition) { throw $Message }
}
$board = Convert-HardwareSummary -System ([pscustomobject]@{Manufacturer='Test';Model='Desktop';Name='SECRET_HOST';UserName='SECRET_USER'}) -Board ([pscustomobject]@{Manufacturer='Board';Product='Example';Version='1';SerialNumber='SECRET_SERIAL'}) -CPU @([pscustomobject]@{Name='Intel test processor';ProcessorId='SECRET_CPU_ID'}) -OS ([pscustomobject]@{Caption='Windows';Version='10.0';BuildNumber='123';OSArchitecture='64-bit';SerialNumber='SECRET_OS_SERIAL'})
$json=$board | ConvertTo-Json -Depth 10
Assert-True (!$json.Contains('SECRET')) 'Hardware report leaked a unique identifier'
Assert-True ($board.board.product -eq 'Example') 'Board model missing'
Assert-True ($board.remote_management.status -eq 'not_verified') 'CPU brand must not establish AMT support'
$missing=Convert-HardwareSummary -System $null -Board $null -CPU @() -OS $null
Assert-True ($missing.remote_management.status -eq 'not_verified') 'Missing data must stay unknown'
Assert-True ($missing.board.product -eq '') 'Missing hardware should remain empty'
$nic=Convert-WakeAdapter -Adapter ([pscustomobject]@{InterfaceDescription='Ethernet';Status='Up';MediaType='802.3';PhysicalMediaType='Unspecified';InterfaceType=6;MacAddress='SECRET_MAC';InterfaceGuid='SECRET_GUID';Name='SECRET_CUSTOM_NAME';DriverVersion='1.2'}) -Power ([pscustomobject]@{WakeOnMagicPacket='Enabled'}) -WakeArmed $null -Properties @()
Assert-True ($nic.wake_magic_packet -eq 'enabled') 'Magic packet state missing'
Assert-True ($nic.wake_armed -eq 'unknown') 'Unreadable wake-armed state must be unknown'
Assert-True ($nic.shutdown_wake -eq 'unknown') 'Unexposed shutdown property must be unknown'
Assert-True (!(($nic | ConvertTo-Json -Depth 10).Contains('SECRET'))) 'Adapter report leaked identifiers'
$disabled=Convert-WakeAdapter -Adapter ([pscustomobject]@{InterfaceDescription='Ethernet';InterfaceType=6}) -Power ([pscustomobject]@{WakeOnMagicPacket='Disabled'}) -WakeArmed @('Ethernet') -Properties @([pscustomobject]@{RegistryKeyword='S5WakeOnLan';RegistryValue=@('0')})
Assert-True ($disabled.wake_magic_packet -eq 'disabled') 'Disabled state lost'
Assert-True ($disabled.wake_armed -eq 'enabled') 'Armed adapter missed'
Assert-True ($disabled.shutdown_wake -eq 'disabled') 'Shutdown driver state missed'
$ambiguous=Convert-WakeAdapter -Adapter ([pscustomobject]@{InterfaceDescription='Ethernet'}) -Power $null -WakeArmed @() -Properties @([pscustomobject]@{RegistryKeyword='S5WakeOnLan';RegistryValue=@('7')})
Assert-True ($ambiguous.shutdown_wake -eq 'unknown') 'Unknown vendor driver value must not become supported'
Assert-True ($ambiguous.wake_armed -eq 'unknown') 'Missing localized powercfg name must not prove wake is disabled'
Write-Output 'PASS: hardware whitelist, unknown-state handling, wake settings, no false AMT capability.'
