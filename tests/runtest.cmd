@echo off

set CoreRT_TestRoot=%~dp0
set CoreRT_CliDir=%CoreRT_TestRoot%../Tools/dotnetcli
set CoreRT_BuildArch=x64
set CoreRT_BuildType=Debug
set CoreRT_BuildOS=Windows_NT
set CoreRT_TestRun=true
set CoreRT_TestCompileMode=ryujit
set CoreRT_RunCoreCLRTests=

:ArgLoop
if "%1" == "" goto :ArgsDone
if /i "%1" == "/?" goto :Usage
if /i "%1" == "x64"    (set CoreRT_BuildArch=x64&&shift&goto ArgLoop)
if /i "%1" == "x86"    (set CoreRT_BuildArch=x86&&shift&goto ArgLoop)
if /i "%1" == "arm"    (set CoreRT_BuildArch=arm&&shift&goto ArgLoop)

if /i "%1" == "debug"    (set CoreRT_BuildType=Debug&shift&goto ArgLoop)
if /i "%1" == "release"  (set CoreRT_BuildType=Release&shift&goto ArgLoop)
if /i "%1" == "/coreclr"  (set CoreRT_RunCoreCLRTests=true&shift&goto ArgLoop)
if /i "%1" == "/mode" (set CoreRT_TestCompileMode=%2&shift&shift&goto ArgLoop)
if /i "%1" == "/runtest" (set CoreRT_TestRun=%2&shift&shift&goto ArgLoop)
if /i "%1" == "/dotnetclipath" (set CoreRT_CliDir=%2&shift&shift&goto ArgLoop)

echo Invalid command line argument: %1
goto :Usage

:Usage
echo %0 [OS] [arch] [flavor] [/extrepo] [/mode] [/runtest]
echo     /mode         : Compilation mode. Specify cpp/ryujit. Default: ryujit
echo     /runtest      : Should just compile or run compiled binary? Specify: true/false. Default: true.
echo     /coreclr      : Download and run the CoreCLR repo tests
exit /b 2

:ArgsDone

call %CoreRT_TestRoot%testenv.cmd

set CoreRT_RspTemplateDir=%CoreRT_TestRoot%..\bin\obj\%CoreRT_BuildOS%.%CoreRT_BuildArch%.%CoreRT_BuildType%

setlocal EnableDelayedExpansion
set __BuildStr=%CoreRT_BuildOS%.%CoreRT_BuildArch%.%CoreRT_BuildType%
set __CoreRTTestBinDir=%CoreRT_TestRoot%..\bin\tests
set __LogDir=%CoreRT_TestRoot%\..\bin\Logs\%__BuildStr%\tests

call "!VS140COMNTOOLS!\..\..\VC\vcvarsall.bat" %CoreRT_BuildArch%

if "%CoreRT_RunCoreCLRTests%"=="true" goto :TestExtRepo

if /i "%__BuildType%"=="Debug" (
    set __LinkLibs=msvcrtd.lib
) else (
    set __LinkLibs=msvcrt.lib
)

echo. > %__CoreRTTestBinDir%\testResults.tmp

set /a __CppTotalTests=0
set /a __CppPassedTests=0
set /a __JitTotalTests=0
set /a __JitPassedTests=0
for /f "delims=" %%a in ('dir /s /aD /b src\*') do (
    set __SourceFolder=%%a
    set __SourceFileName=%%~na
    set __RelativePath=!__SourceFolder:%CoreRT_TestRoot%=!
    if exist "!__SourceFolder!\!__SourceFileName!.csproj" (

        set __Mode=Jit
        call :CompileFile !__SourceFolder! !__SourceFileName! %__LogDir%\!__RelativePath!
        set /a __JitTotalTests=!__JitTotalTests!+1

        if not exist "!__SourceFolder!\no_cpp" (
            set __Mode=Cpp
            call :CompileFile !__SourceFolder! !__SourceFileName! %__LogDir%\!__RelativePath!
            set /a __CppTotalTests=!__CppTotalTests!+1
        )
    )
)
set /a __CppFailedTests=%__CppTotalTests%-%__CppPassedTests%
set /a __JitFailedTests=%__JitTotalTests%-%__JitPassedTests%
set /a __TotalTests=%__JitTotalTests%+%__CppTotalTests%
set /a __PassedTests=%__JitPassedTests%+%__CppPassedTests%
set /a __FailedTests=%__JitFailedTests%+%__CppFailedTests%

echo ^<?xml version="1.0" encoding="utf-8"?^> > %__CoreRTTestBinDir%\testResults.xml
echo ^<assemblies^>  >> %__CoreRTTestBinDir%\testResults.xml
echo ^<assembly name="ILCompiler" total="%__TotalTests%" passed="%__PassedTests%" failed="%__FailedTests%" skipped="0"^>  >> %__CoreRTTestBinDir%\testResults.xml
echo ^<collection total="%__TotalTests%" passed="%__PassedTests%" failed="%__FailedTests%" skipped="0"^>  >> %__CoreRTTestBinDir%\testResults.xml
type %__CoreRTTestBinDir%\testResults.tmp >> %__CoreRTTestBinDir%\testResults.xml
echo ^</collection^>  >> %__CoreRTTestBinDir%\testResults.xml
echo ^</assembly^>  >> %__CoreRTTestBinDir%\testResults.xml
echo ^</assemblies^>  >> %__CoreRTTestBinDir%\testResults.xml

echo.
set __JitStatusPassed=0
if %__JitTotalTests% EQU %__JitPassedTests% (set __JitStatusPassed=1)
if %__JitTotalTests% EQU 0 (set __JitStatusPassed=0)
call :PassFail %__JitStatusPassed% "JIT - TOTAL: %__JitTotalTests% PASSED: %__JitPassedTests%"

set __CppStatusPassed=0
if %__CppTotalTests% EQU %__CppPassedTests% (set __CppStatusPassed=1)
if %__CppTotalTests% EQU 0 (set __CppStatusPassed=0)
call :PassFail %__CppStatusPassed% "CPP - TOTAL: %__CppTotalTests% PASSED: %__CppPassedTests%"

if not %__JitStatusPassed% EQU 1 (exit /b 1)
if not %__CppStatusPassed% EQU 1 (exit /b 1)
exit /b 0

:PassFail
set __Green=%~1
set __OutStr=%~2
if "%__Green%"=="1" (
    powershell -Command Write-Host %__OutStr% -foreground "Black" -background "Green"
) else ( 
    powershell -Command Write-Host %__OutStr% -foreground "White" -background "Red"
)
goto :eof

:CompileFile
    echo.
    set __SourceFolder=%~1
    set __SourceFileName=%~2
    set __CompileLogPath=%~3

    echo Compiling directory !__SourceFolder! !__Mode!
    echo.

    if not exist "!__CompileLogPath!" (mkdir !__CompileLogPath!)
    set __SourceFile=!__SourceFolder!\!__SourceFileName!

    if exist "!__SourceFolder!\bin" rmdir /s /q !__SourceFolder!\bin
    if exist "!__SourceFolder!\obj" rmdir /s /q !__SourceFolder!\obj

    setlocal
    set extraArgs=
    if /i "%__Mode%" == "cpp" (
        set extraArgs=!extraArgs! /p:NativeCodeGen=cpp
        if /i "%CoreRT_BuildType%" == "debug" (
            set extraArgs=!extraArgs! /p:AdditionalCppCompilerFlags=/MTd
        )
    )

    echo msbuild /ConsoleLoggerParameters:ForceNoAlign "/p:IlcPath=%CoreRT_ToolchainDir%" "/p:Configuration=%CoreRT_BuildType%" !extraArgs! !__SourceFile!.csproj
    echo.
    msbuild /ConsoleLoggerParameters:ForceNoAlign "/p:IlcPath=%CoreRT_ToolchainDir%" "/p:Configuration=%CoreRT_BuildType%" !extraArgs! !__SourceFile!.csproj
    endlocal

    set __SavedErrorLevel=%ErrorLevel%
    if "%CoreRT_TestRun%"=="false" (goto :SkipTestRun)

    if "%__SavedErrorLevel%"=="0" (
        echo.
        echo Running test !__SourceFileName!
        call !__SourceFile!.cmd !__SourceFolder!\bin\%CoreRT_BuildType%\native !__SourceFileName!.exe
        set __SavedErrorLevel=!ErrorLevel!
    )

:SkipTestRun
    if "%__SavedErrorLevel%"=="0" (
        set /a __%__Mode%PassedTests=!__%__Mode%PassedTests!+1
        echo ^<test name="!__SourceFile!" type="!__SourceFileName!:%__Mode%" method="Main" result="Pass" /^> >> %__CoreRTTestBinDir%\testResults.tmp
    ) ELSE (
        echo ^<test name="!__SourceFile!" type="!__SourceFileName!:%__Mode%" method="Main" result="Fail"^> >> %__CoreRTTestBinDir%\testResults.tmp
        echo ^<failure exception-type="Exit code: %ERRORLEVEL%" ^> >> %__CoreRTTestBinDir%\testResults.tmp
        echo     ^<message^>See !__SourceFile! \bin or \obj for logs ^</message^> >> %__CoreRTTestBinDir%\testResults.tmp
        echo ^</failure^> >> %__CoreRTTestBinDir%\testResults.tmp
        echo ^</test^> >> %__CoreRTTestBinDir%\testResults.tmp
    )
    goto :eof

:DeleteFile
    if exist %1 del %1
    goto :eof

:Fail
    echo.
    powershell -Command Write-Host %1 -foreground "red"
    exit /b -1

:RestoreCoreCLRTests

    set TESTS_SEMAPHORE=%CoreRT_TestExtRepo%\init-tests.completed

    :: If sempahore exists do nothing
    if exist "%TESTS_SEMAPHORE%" (
      echo Tests are already initialized.
      goto :EOF
    )

    if exist "%CoreRT_TestExtRepo%" rmdir /S /Q "%CoreRT_TestExtRepo%"
    mkdir "%CoreRT_TestExtRepo%"

    set /p TESTS_REMOTE_URL=< "%~dp0..\CoreCLRTestsURL.txt"
    set TESTS_LOCAL_ZIP=%CoreRT_TestExtRepo%\tests.zip
    set INIT_TESTS_LOG=%~dp0..\init-tests.log
    echo Restoring tests (this may take a few minutes)..
    echo Installing '%TESTS_REMOTE_URL%' to '%TESTS_LOCAL_ZIP%' >> "%INIT_TESTS_LOG%"
    powershell -NoProfile -ExecutionPolicy unrestricted -Command "$retryCount = 0; $success = $false; do { try { (New-Object Net.WebClient).DownloadFile('%TESTS_REMOTE_URL%', '%TESTS_LOCAL_ZIP%'); $success = $true; } catch { if ($retryCount -ge 6) { throw; } else { $retryCount++; Start-Sleep -Seconds (5 * $retryCount); } } } while ($success -eq $false); Add-Type -Assembly 'System.IO.Compression.FileSystem' -ErrorVariable AddTypeErrors; if ($AddTypeErrors.Count -eq 0) { [System.IO.Compression.ZipFile]::ExtractToDirectory('%TESTS_LOCAL_ZIP%', '%CoreRT_TestExtRepo%') } else { (New-Object -com shell.application).namespace('%CoreRT_TestExtRepo%').CopyHere((new-object -com shell.application).namespace('%TESTS_LOCAL_ZIP%').Items(),16) }" >> "%INIT_TESTS_LOG%"
    if errorlevel 1 (
      echo ERROR: Could not download CoreCLR tests correctly. See '%INIT_TESTS_LOG%' for more details. 1>&2
      exit /b 1
    )

    echo Tests restored.
    echo CoreCLR tests restored from %TESTS_REMOTE_URL% > %TESTS_SEMAPHORE%
    exit /b 0

:TestExtRepo
    echo Running external tests
    if "%CoreRT_TestExtRepo%" == "" (
        set CoreRT_TestExtRepo=%CoreRT_TestRoot%\..\tests_downloaded\CoreCLR
        call :RestoreCoreCLRTests
        if errorlevel 1 (
            exit /b 1
        )
    )

    if not exist "%CoreRT_TestExtRepo%" ((call :Fail "%CoreRT_TestExtRepo% does not exist") & exit /b 1)

    echo.
    set CLRCustomTestLauncher=%CoreRT_TestRoot%\CoreCLR\build-and-run-test.cmd
    set XunitTestBinBase=!CoreRT_TestExtRepo!
    set CORE_ROOT=%CoreRT_TestRoot%\..\Tools\dotnetcli\shared\Microsoft.NETCore.App\1.0.0
    echo CORE_ROOT IS NOW %CORE_ROOT%
    pushd %CoreRT_TestRoot%\CoreCLR\runtest
 
    msbuild src\TestWrappersConfig\XUnitTooling.depproj
    if errorlevel 1 (
        exit /b 1
    )

    call runtest.cmd %CoreRT_BuildArch% %CoreRT_BuildType% exclude %CoreRT_TestRoot%\Top100Tests.issues.targets
    set __SavedErrorLevel=%ErrorLevel%
    popd
    exit /b %__SavedErrorLevel%
