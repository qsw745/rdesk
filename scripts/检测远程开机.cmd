@echo off
chcp 65001 >nul
echo 正在读取主板、网卡与电源状态；不会修改设置或发送开机指令。
powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "%~dp0collect-wake-readiness.ps1"
if errorlevel 1 (
  echo 检测未完成，请保留以上错误信息。
) else (
  echo 完成。请打开桌面的 RDesk-Wake-Check 文件夹查看检测结果。
)
pause
