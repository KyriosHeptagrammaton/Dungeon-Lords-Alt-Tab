@echo off
cd /d "%~dp0"
if not exist dlords_original.exe (echo No backup found - nothing to undo. & pause & exit /b 1)
copy /y dlords_original.exe dlords.exe >nul || (echo Could not write dlords.exe - right-click Uninstall.bat and choose "Run as administrator". & pause & exit /b 1)
echo Original dlords.exe restored.
pause
