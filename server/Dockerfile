# 使用轻量级 Python 3.11 镜像
FROM python:3.11-slim

# 设置工作目录
WORKDIR /app

# 设置环境变量
# 防止 Python 生成 .pyc 文件
ENV PYTHONDONTWRITEBYTECODE=1
# 确保日志直接输出到控制台
ENV PYTHONUNBUFFERED=1

# 安装系统依赖 (编译依赖等)
RUN apt-get update && apt-get install -y --no-install-recommends 
    build-essential 
    curl 
    && rm -rf /var/lib/apt/lists/*

# 复制依赖文件
COPY requirements.txt .

# 安装 Python 依赖
RUN pip install --no-cache-dir --upgrade pip && 
    pip install --no-cache-dir -r requirements.txt

# 复制项目代码
COPY . .

# 暴露端口 (仅供文档说明，实际由 compose 映射)
EXPOSE 8000

# 默认启动命令 (会被 docker-compose 覆盖)
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
