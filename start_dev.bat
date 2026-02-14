@echo off
setlocal

:: 获取当前脚本所在目录的绝对路径
set "PROJECT_ROOT=%~dp0"
set "SERVER_DIR=%PROJECT_ROOT%server"
set "CLIENT_DIR=%PROJECT_ROOT%client"

echo ========================================================
echo   Starting Intelli Note Dev Environment
echo   Root: %PROJECT_ROOT%
echo ========================================================
echo.

:: 1. 启动后端服务 (Unified CLI)
echo Starting Backend Services (Redis + Celery + API)...
echo Use "python manage.py down" to stop services.
echo.

:: 在新窗口启动 manage.py，并输出一次状态检查
start "Intelli Note Server CLI" cmd /k "cd /d "%SERVER_DIR%" && venv\Scripts\python manage.py up && venv\Scripts\python manage.py status"

echo Backend is launching in a new window.
echo.
echo [Optional] Press any key to launch Flutter Client (Windows)...
pause
cd /d "%CLIENT_DIR%"
flutter run -d windows
