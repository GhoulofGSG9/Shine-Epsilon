@echo off
REM Offline tests for the readyroomqueue plugin. No game server needed.
REM
REM Needs the LuaJIT binary from the engine repo and a checkout of upstream Shine for its
REM Map/Set implementations:
REM   C:\Git\ns2-engine\utils\lua\luajit.exe
REM   C:\Git\Shine
REM   C:\Git\ns2 (core\lua\dkjson.lua)
REM
REM Set RRQUEUE_PLUGIN_FILE to point the suite at a different revision of the plugin.

setlocal

set LUAJIT=C:\Git\ns2-engine\utils\lua\luajit.exe

if not exist "%LUAJIT%" (
    echo Could not find %LUAJIT%
    echo Adjust the LUAJIT path in this script to point at a LuaJIT 2.1 binary.
    exit /b 1
)

if not exist "C:\Git\Shine\lua\shine\lib\objects\map.lua" (
    echo Could not find upstream Shine at C:\Git\Shine
    echo The tests use the real Shine.Map/Shine.Set implementations.
    exit /b 1
)

if not exist "C:\Git\ns2\core\lua\dkjson.lua" (
    echo Could not find C:\Git\ns2\core\lua\dkjson.lua
    echo The seed queue tests use the game's json implementation.
    exit /b 1
)

pushd "%~dp0"
"%LUAJIT%" test\readyroomqueue\run.lua
set RESULT=%ERRORLEVEL%
popd

endlocal & exit /b %RESULT%
