REM ###########################################################################
REM #  
REM # Author      : Awen zhu
REM # CreateDate  : 2012-9-7
REM # Description : Stage instance, Create bundle and stage it to stage area 
REM # ChangeHist  : 2012-9-7 Init checkin.
REM #
REM # Depedencies : ExitCode:
REM #               0 success
REM #				1 Failed to create folder on stage area
REM #				2 Failed to create bundle files
REM #				4 Failed to zip self-extract file 
REM #				8 Failed to copy bundle to stage area
REM ###########################################################################

echo off
@set _Raids=%1
@set _BundleName=%2
@set _RaidsType=%3
@set _Stage=%4
@set _InsName=%5
@set _ExitCode=0
@set _BobRoot=D:\Bob
@set _BundleRootDir=D:\raids
@set _StageArea=\\chc-filidx\DSTest\EDW\EDW_HF\%date:~10,4%%date:~4,2%%date:~7,2%
@echo %P4PASSWD%|p4 login
echo on
@cd /d d:\raids
@if exist %_BundleName% rmdir /S /Q %_BundleName%
@if not exist %_BundleName% md %_BundleName%
if %errorlevel% neq 0 set _ExitCode=1
@cd %_BundleName%

@IF /I "%_Stage%" == "only" ( goto only ) else ( goto build )

:only
@IF /I "%_RaidsType%" == "edw" ( goto EDW ) else ( goto LDW )

:EDW
perl %_BobRoot%\bin\BundleBuild.pl -raids %_Raids% -triagegroup edw -debug > %_BundleRootDir%\StageLogs\CBundle%_BundleName%.txt
@if %errorlevel% neq 0 (
set _ExitCode=2
goto problem )

goto Continue

:LDW
perl %_BobRoot%\bin\BundleBuild.pl -raids %_Raids% -debug > %_BundleRootDir%\StageLogs\CBundle%_BundleName%.txt
@if %errorlevel% neq 0 (
set _ExitCode=2
goto problem )

goto Continue

:build
echo removing bundle logs
@cd /d d:\raids\%_InsName%
robocopy . ../%_BundleName% * /E
for /R %%i in (../%_BundleName%/*.CLEAN) do del /F /Q %%i
rmdir /Q /S ..\%_BundleName%\BusinessSystems\Common\DBBuild\db\release\ApplyBundledHotfixes_LOG
@if %errorlevel% neq 0 (
set _ExitCode=8
)

goto Continue

:Continue
@p4 logout
rem call "C:\Program Files (x86)\WinRAR\rar.exe" a -sfx %_BundleName%.exe .
call 7z.exe a %_BundleName%.exe -sfx ../%_BundleName%
if %errorlevel% neq 0 (
set _ExitCode=4
goto problem )
robocopy . %_StageArea% %_BundleName%.exe /MOV
exit 0
:problem
exit /B %_ExitCode%