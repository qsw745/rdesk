# Run on a local Windows machine or local VM. Never dispatch a cloud build.
param([string]$Flutter = 'flutter', [string]$InnoSetup = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$pubspec = Get-Content (Join-Path $root 'flutter_client\pubspec.yaml') -Raw
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') { throw 'Missing app version' }
$version = $Matches[1]
$build = $Matches[2]
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$vs = & $vswhere -latest -version '[17.0,18.0)' -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (!$vs) { throw 'Visual Studio 2022 C++ tools are required for the current plugins' }
$cmake = Join-Path $vs 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
$nativeBuild = Join-Path $root 'flutter_client\build\windows\x64-vs2022'
Push-Location (Join-Path $root 'flutter_client')
try {
    & $Flutter pub get --enforce-lockfile
    if ($LASTEXITCODE -ne 0) { throw 'Locked dependency resolution failed' }
    & $Flutter build windows --release --config-only --no-pub "--build-name=$version" "--build-number=$build"
    if ($LASTEXITCODE -ne 0) { throw 'Flutter project configuration failed' }
    & $cmake -S windows -B $nativeBuild -G 'Visual Studio 17 2022' -A x64 "-DCMAKE_GENERATOR_INSTANCE=$vs" -DFLUTTER_TARGET_PLATFORM=windows-x64
    if ($LASTEXITCODE -ne 0) { throw 'VS 2022 configuration failed' }
    & $cmake --build $nativeBuild --config Release --target INSTALL
    if ($LASTEXITCODE -ne 0) { throw 'VS 2022 build failed' }
} finally { Pop-Location }
$bundle = Join-Path $nativeBuild 'runner\Release'
$exe = Join-Path $bundle 'rdesk.exe'
if (!(Test-Path $exe)) { throw 'Expected local x64 artifact is missing' }
$bytes = [IO.File]::ReadAllBytes($exe)
$pe = [BitConverter]::ToInt32($bytes, 0x3c)
if ([BitConverter]::ToUInt16($bytes, $pe + 4) -ne 0x8664) { throw 'Expected x64 PE executable' }
$crt = Get-ChildItem "$vs\VC\Redist\MSVC" -Directory -Recurse | Where-Object { $_.Name -eq 'Microsoft.VC143.CRT' -and $_.FullName -match '\\x64\\' } | Select-Object -First 1
if (!$crt) { throw 'VC++ x64 runtime missing' }
Copy-Item "$($crt.FullName)\*.dll" $bundle
$process = Start-Process $exe -PassThru
Start-Sleep -Seconds 8
if ($process.HasExited) { throw "App exited during startup: $($process.ExitCode)" }
Stop-Process -Id $process.Id
$dist = Join-Path $root 'dist'
New-Item $dist -ItemType Directory -Force | Out-Null
Compress-Archive -Path "$bundle\*" -DestinationPath "$dist\RDesk-$version-windows-x64-portable.zip" -Force
& $InnoSetup "/DAppVersion=$version" "/DBundleDir=$bundle" (Join-Path $PSScriptRoot 'windows-installer.iss')
if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
$dest = Join-Path $env:TEMP "rdesk-install-smoke-$version"
$setup = Start-Process "$dist\RDesk-$version-windows-x64-setup.exe" -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$dest" -PassThru -Wait
if ($setup.ExitCode -ne 0 -or !(Test-Path "$dest\rdesk.exe")) { throw 'Installation failed' }
if ((Get-FileHash "$dest\rdesk.exe").Hash -ne (Get-FileHash $exe).Hash) { throw 'Installed executable differs from the build' }
Get-ChildItem $dist -File | Where-Object { $_.Extension -in '.exe', '.zip' } | Get-FileHash -Algorithm SHA256 | ForEach-Object { $_.Hash.ToLower() + '  ' + (Split-Path $_.Path -Leaf) } | Set-Content "$dist\SHA256SUMS.txt"
Write-Output "Local build, x64 architecture, startup and installer checks passed: $dist"
