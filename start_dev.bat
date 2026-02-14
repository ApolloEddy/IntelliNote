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

:: 1. 启动后端服务 (前台联动日志模式)
echo Starting Backend Services (Redis + Celery + API)...
echo Press Ctrl+C in server window to stop all services.
echo.

:: 在新窗口启动 manage.py（默认前台模式：三进程合流日志）
start "Intelli Note Server CLI" cmd /k "cd /d "%SERVER_DIR%" && venv\Scripts\python manage.py"

echo Backend is launching in a new window.
echo.
echo [Optional] Press any key to launch Flutter Client (Windows)...
pause
cd /d "%CLIENT_DIR%"
flutter run -d windows
