; 随控 (RDesk) installer Simplified Chinese messages (Inno Setup 6.7).
; Loaded after compiler:Default.isl, so anything not listed here falls back
; to English. Covers every page and prompt the installer can show.

[LangOptions]
LanguageName=简体中文
LanguageID=$0804
LanguageCodePage=0
DialogFontName=Microsoft YaHei UI
DialogFontSize=9
WelcomeFontName=Microsoft YaHei UI
WelcomeFontSize=14

[Messages]
SetupAppTitle=安装
SetupWindowTitle=安装%1
UninstallAppTitle=卸载
UninstallAppFullTitle=卸载%1
InformationTitle=提示
ConfirmTitle=确认
ErrorTitle=错误

SetupLdrStartupMessage=将要安装%1，是否继续？
LdrCannotCreateTemp=无法创建临时文件，安装已中止
LdrCannotExecTemp=无法运行临时目录中的文件，安装已中止
LastErrorMessage=%1。%n%n错误 %2：%3
SetupFileMissing=安装目录缺少文件 %1。请重新下载安装包。
SetupFileCorrupt=安装文件已损坏。请重新下载安装包。
SetupFileCorruptOrWrongVer=安装文件已损坏或与当前安装程序不兼容。请重新下载安装包。
InvalidParameter=命令行参数无效：%n%n%1
SetupAlreadyRunning=安装程序已在运行。
WindowsVersionNotSupported=随控不支持当前的 Windows 版本。
OnlyOnTheseArchitectures=随控只能安装在以下处理器架构的 Windows 上：%n%n%1
WinVersionTooLowError=随控需要 %1 %2 或更高版本。
SetupAppRunningError=随控正在运行。%n%n请先退出随控，然后点“确定”继续；点“取消”退出安装。
UninstallAppRunningError=随控正在运行。%n%n请先退出随控，然后点“确定”继续；点“取消”退出卸载。

ErrorCreatingDir=无法创建文件夹“%1”
ExitSetupTitle=退出安装
ExitSetupMessage=安装尚未完成。现在退出，随控将不会被安装。%n%n以后可以重新运行安装程序完成安装。%n%n确定退出吗？
AboutSetupMenuItem=关于安装程序(&A)...
AboutSetupTitle=关于安装程序
AboutSetupMessage=%1 版本 %2%n%3%n%n%1 主页：%n%4

ButtonBack=< 上一步(&B)
ButtonNext=下一步(&N) >
ButtonInstall=立即安装(&I)
ButtonOK=确定
ButtonCancel=取消
ButtonYes=是(&Y)
ButtonYesToAll=全部是(&A)
ButtonNo=否(&N)
ButtonNoToAll=全部否(&O)
ButtonFinish=完成(&F)
ButtonBrowse=浏览(&B)...
ButtonWizardBrowse=更改(&R)...
ButtonNewFolder=新建文件夹(&M)

ClickNext=点“下一步”继续，或点“取消”退出安装。
BrowseDialogTitle=选择文件夹
BrowseDialogLabel=在下面的列表中选择一个文件夹，然后点“确定”。
NewFolderName=新建文件夹

WelcomeLabel1=欢迎安装[name]
WelcomeLabel2=随控可以远程控制你的其他设备，也能帮家里的电脑远程开机。%n%n即将安装[name/ver]。

WizardSelectDir=选择安装位置
SelectDirDesc=随控要安装到哪里？
SelectDirLabel3=随控将安装到下面的文件夹。
SelectDirBrowseLabel=点“下一步”继续。如需更换位置，点“更改”。
DiskSpaceGBLabel=至少需要 [gb] GB 可用磁盘空间。
DiskSpaceMBLabel=至少需要 [mb] MB 可用磁盘空间。
CannotInstallToNetworkDrive=不能安装到网络驱动器。
CannotInstallToUNCPath=不能安装到 UNC 路径。
InvalidPath=请输入带盘符的完整路径，例如：%n%nC:\Apps
InvalidDrive=所选驱动器不存在或无法访问，请重新选择。
DiskSpaceWarningTitle=磁盘空间不足
DiskSpaceWarning=安装至少需要 %1 KB 可用空间，但所选驱动器只有 %2 KB。%n%n仍要继续吗？
DirNameTooLong=文件夹名称或路径太长。
InvalidDirName=文件夹名称无效。
BadDirName32=文件夹名称不能包含以下字符：%n%n%1
DirExistsTitle=文件夹已存在
DirExists=文件夹：%n%n%1%n%n已经存在。仍要安装到这里吗？
DirDoesntExistTitle=文件夹不存在
DirDoesntExist=文件夹：%n%n%1%n%n不存在。要创建它吗？

WizardSelectTasks=安装选项
SelectTasksDesc=按需要选择，之后也可以在随控「设置 → 常规」中修改。
SelectTasksLabel2=

WizardReady=准备安装
ReadyLabel1=已准备好在这台电脑上安装[name]。
ReadyLabel2a=点“立即安装”开始安装，或点“上一步”修改选项。
ReadyLabel2b=点“立即安装”开始安装。
ReadyMemoDir=安装位置：
ReadyMemoTasks=安装选项：

WizardPreparing=准备安装
PreparingDesc=正在准备安装[name]。
PreviousInstallNotCompleted=上一次安装或卸载尚未完成，需要重启电脑。%n%n重启后请重新运行安装程序完成 [name] 的安装。
CannotContinue=安装无法继续，请点“取消”退出。
ApplicationsFound=以下程序正在使用需要更新的文件，建议让安装程序自动关闭它们。
ApplicationsFound2=以下程序正在使用需要更新的文件，建议让安装程序自动关闭它们。安装完成后会尝试重新打开。
CloseApplications=自动关闭这些程序(&A)
DontCloseApplications=不关闭(&D)
ErrorCloseApplications=无法自动关闭所有程序。继续前请先手动退出随控。
PrepareToInstallNeedsRestart=需要重启电脑。重启后请重新运行安装程序完成[name]的安装。%n%n现在重启吗？

WizardInstalling=正在安装
InstallingLabel=正在安装[name]，请稍候…

FinishedHeadingLabel=随控已准备就绪
FinishedLabelNoIcons=[name]已安装完成。
FinishedLabel=[name]已安装完成，可以从开始菜单或桌面快捷方式打开。
ClickFinish=点“完成”关闭安装程序。
FinishedRestartLabel=需要重启电脑才能完成[name]的安装。现在重启吗？
FinishedRestartMessage=需要重启电脑才能完成[name]的安装。%n%n现在重启吗？
YesRadio=现在重启(&Y)
NoRadio=稍后手动重启(&N)
RunEntryExec=打开%1
RunEntryShellExec=查看%1

SetupAborted=安装未完成。%n%n请解决问题后重新运行安装程序。
AbortRetryIgnoreSelectAction=请选择
AbortRetryIgnoreRetry=重试(&T)
AbortRetryIgnoreIgnore=忽略错误并继续(&I)
AbortRetryIgnoreCancel=取消安装
RetryCancelSelectAction=请选择
RetryCancelRetry=重试(&T)
RetryCancelCancel=取消

StatusClosingApplications=正在关闭程序…
StatusCreateDirs=正在创建文件夹…
StatusExtractFiles=正在复制文件…
StatusCreateIcons=正在创建快捷方式…
StatusCreateRegistryEntries=正在写入设置…
StatusSavingUninstall=正在保存卸载信息…
StatusRunProgram=正在完成安装…
StatusRestartingApplications=正在重新打开程序…
StatusRollback=正在撤销更改…

ErrorInternal2=内部错误：%1
ErrorFunctionFailedNoCode=%1 失败
ErrorFunctionFailed=%1 失败，代码 %2
ErrorFunctionFailedWithMessage=%1 失败，代码 %2。%n%3
ErrorExecutingProgram=无法运行文件：%n%1
ErrorRegOpenKey=打开注册表项出错：%n%1\%2
ErrorRegCreateKey=创建注册表项出错：%n%1\%2
ErrorRegWriteKey=写入注册表项出错：%n%1\%2
FileAbortRetryIgnoreSkipNotRecommended=跳过此文件(&S)（不推荐）
FileAbortRetryIgnoreIgnoreNotRecommended=忽略错误并继续(&I)（不推荐）
SourceIsCorrupted=源文件已损坏
SourceDoesntExist=源文件“%1”不存在
ExistingFileReadOnly2=现有文件是只读的，无法替换。
ExistingFileReadOnlyRetry=去掉只读属性后重试(&R)
ExistingFileReadOnlyKeepExisting=保留现有文件(&K)
ErrorReadingExistingDest=读取现有文件时出错：
FileExistsSelectAction=请选择
FileExists2=文件已存在。
FileExistsOverwriteExisting=覆盖现有文件(&O)
FileExistsKeepExisting=保留现有文件(&K)
FileExistsOverwriteOrKeepAll=之后的冲突都这样处理(&D)
ExistingFileNewerSelectAction=请选择
ExistingFileNewer2=现有文件比要安装的文件更新。
ExistingFileNewerOverwriteExisting=覆盖现有文件(&O)
ExistingFileNewerKeepExisting=保留现有文件(&K)（推荐）
ExistingFileNewerOverwriteOrKeepAll=之后的冲突都这样处理(&D)
ErrorChangingAttr=修改现有文件属性时出错：
ErrorCreatingTemp=在安装目录中创建文件时出错：
ErrorReadingSource=读取源文件时出错：
ErrorCopying=复制文件时出错：
ErrorReplacingExistingFile=替换现有文件时出错：
ErrorRestartReplace=重启替换失败：
ErrorRenamingTemp=重命名安装目录中的文件时出错：
ErrorRestartingComputer=无法自动重启电脑，请手动重启。

UninstallDisplayNameMark=%1（%2）
UninstallDisplayNameMarks=%1（%2，%3）
UninstallDisplayNameMark32Bit=32 位
UninstallDisplayNameMark64Bit=64 位
UninstallDisplayNameMarkAllUsers=所有用户
UninstallDisplayNameMarkCurrentUser=当前用户
UninstallNotFound=文件“%1”不存在，无法卸载。
UninstallOpenError=无法打开文件“%1”，无法卸载
UninstallUnsupportedVer=卸载日志“%1”的格式无法识别，无法卸载
UninstallUnknownEntry=卸载日志中有未知条目（%1）
ConfirmUninstall=确定要从这台电脑移除%1吗？%n%n账号、设备列表等云端数据不会被删除。
UninstallOnlyOnWin64=只能在 64 位 Windows 上卸载。
UninstallStatusLabel=正在移除%1，请稍候…
UninstalledAll=%1已从这台电脑移除。
UninstalledMost=%1卸载完成。%n%n有些文件无法删除，可以手动移除。
UninstalledAndNeedsRestart=需要重启电脑才能完成%1的卸载。%n%n现在重启吗？
UninstallDataCorrupted=文件“%1”已损坏，无法卸载
WizardUninstalling=卸载
StatusUninstalling=正在卸载%1…
ShutdownBlockReasonInstallingApp=正在安装%1。
ShutdownBlockReasonUninstallingApp=正在卸载%1。

[CustomMessages]
NameAndVersion=%1 版本 %2
CreateDesktopIcon=创建桌面快捷方式(&D)
LaunchProgram=打开%1
UninstallProgram=卸载%1
AutoStartProgram=开机后自动启动%1
AutoStartProgramHint=开机后自动启动随控（远程开机后电脑能自动上线）
