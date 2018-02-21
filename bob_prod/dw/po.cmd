@ECHO OFF

@REM **************************************************************************
@REM Usage: po [fully qualified Perforce filename]
@REM 
@REM This script will output the Perforce file to a temporary file, then open
@REM the file in either your default editor or the application associated
@REM with that file type.
@REM 
@REM If your default editor is *not* Notepad, set a system variable to control
@REM this, i.e.:           DefaultEditor=notepad++.exe
@REM 
@REM DON'T USE THIS SCRIPT TO EDIT FILES THAT ARE CHECKED OUT--it's not smart
@REM enough to figure that out!
@REM **************************************************************************

@REM Check usage

    if "%1"=="" goto Usage
    if "%1"=="/?" goto Usage
    if "%1"=="-?" goto Usage
    if "%1"=="/h" goto Usage
    if "%1"=="-h" goto Usage

@REM If you haven't set the variable DefaultEditor for your system, set it to be notepad

    if "%DefaultEditor%"=="" set DefaultEditor=notepad

@REM Some Perforce files have spaces in the name!!! Hope there aren't more than 8 spaces or we're doomed...

    if NOT "%9"=="" set p4FQN="%1 %2 %3 %4 %5 %6 %7 %8 %9" & set p4tempfile="%1%2%3%4%5%6%7%8%9" & goto p4FQNDone
    if NOT "%8"=="" set p4FQN="%1 %2 %3 %4 %5 %6 %7 %8" & set p4tempfile="%1%2%3%4%5%6%7%8" & goto p4FQNDone
    if NOT "%7"=="" set p4FQN="%1 %2 %3 %4 %5 %6 %7" & set p4tempfile="%1%2%3%4%5%6%7" & goto p4FQNDone
    if NOT "%6"=="" set p4FQN="%1 %2 %3 %4 %5 %6" & set p4tempfile="%1%2%3%4%5%6" & goto p4FQNDone
    if NOT "%5"=="" set p4FQN="%1 %2 %3 %4 %5" & set p4tempfile="%1%2%3%4%5" & goto p4FQNDone
    if NOT "%4"=="" set p4FQN="%1 %2 %3 %4" & set p4tempfile="%1%2%3%4" & goto p4FQNDone
    if NOT "%3"=="" set p4FQN="%1 %2 %3" & set p4tempfile="%1%2%3" & goto p4FQNDone
    if NOT "%2"=="" set p4FQN="%1 %2" & set p4tempfile="%1%2" & goto p4FQNDone
    set p4FQN="%1" & set p4tempfile="%1" & goto p4FQNDone
    
:p4FQNDone

    set p4tempfile=%p4tempfile:/=\%
    set p4tempfile=%p4tempfile:\\=\%

    for %%i in (%p4tempfile%) do set p4tempfileNAME=%%~ni
    for %%i in (%p4tempfile%) do set p4tempfileEXT=%%~xi

@REM This assumes you want .sql files to be opened by the default application, MS SSMS -- if not, remove
@REM the first line below

    if /i "%p4tempfileEXT%"==".sql" goto OpenAsDefault
    if /i "%p4tempfileEXT%"==".doc" goto OpenAsDefault
    if /i "%p4tempfileEXT%"==".docx" goto OpenAsDefault
    if /i "%p4tempfileEXT%"==".xls" goto OpenAsDefault
    if /i "%p4tempfileEXT%"==".xlsx" goto OpenAsDefault
    if /i "%p4tempfileEXT%"==".vsd" goto OpenAsDefault
    if /i "%p4tempfileEXT%"==".ppt" goto OpenAsDefault
    if /i "%p4tempfileEXT%"==".pptx" goto OpenAsDefault

:OpenAsText

@REM Open all other files with your editor

    p4 print -o %temp%\p4temp\%p4tempfileNAME%%p4tempfileEXT% %p4FQN% & %DefaultEditor% %temp%\p4temp\%p4tempfileNAME%%p4tempfileEXT%

goto Cleanup

:OpenAsDefault

@REM Open files using the application associated with the file type

    p4 print -o %temp%\p4temp\%p4tempfileNAME%%p4tempfileEXT% %p4FQN% & start %temp%\p4temp\%p4tempfileNAME%%p4tempfileEXT%

:Cleanup

@REM Clean up the temp folder

    del /f /q %temp%\p4temp\*.*
    
goto End

:Usage

@ECHO.
@ECHO Usage:
@ECHO    po [fully qualified Perforce filename]
@ECHO.
@ECHO Example:
@ECHO    po //depot/Tools/dw/cl.cmd
@ECHO.

:End