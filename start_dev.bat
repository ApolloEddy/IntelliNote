@echo off
setlocal

:: 设置项目路径
set SERVER_DIR=%~dp0server
cd /d "%SERVER_DIR%"

echo ========================================================
echo   Starting IntelliNote Server Infrastructure
echo ========================================================
echo.

:: 1. 启动 Redis (在新窗口中)
echo [1/3] Starting Redis Broker...
start "IntelliNote - Redis" /min cmd /k "color 47 && echo Redis Broker Running... && .	oolsedisedis-server.exe"

:: 等待 Redis 启动
timeout /t 2 /nobreak >nul

:: 2. 启动 Celery Worker (在新窗口中)
echo [2/3] Starting Celery Worker...
start "IntelliNote - Celery Worker" cmd /k "color 20 && echo Celery Worker Running... && .\venv\Scripts\celery.exe -A app.worker.celery_app worker --loglevel=info -P solo"

:: 3. 启动 FastAPI Server (在当前窗口或新窗口)
echo [3/3] Starting FastAPI Server...
start "IntelliNote - API Server" cmd /k "color 17 && echo FastAPI Server Running... && .\venv\Scripts\python.exe main.py"

echo.
echo All services started in separate windows.
echo You can close this window now, or keep it open.
echo.
pause
