#!/bin/bash

# 设置下载 URL
URL="https://raw.githubusercontent.com/rd800919/script/refs/heads/main/centos_network_tool.sh"

# 设置保存的文件名
FILE="abc.sh"

# 检查并安装 wget（适用于 CentOS 7.6）
echo "检查 wget 是否安装..."
if ! command -v wget &> /dev/null; then
    echo "未安装 wget，正在安装..."
    yum install -y wget
else
    echo "wget 已安装。"
fi

# 确认并删除旧文件
if [ -f "$FILE" ]; then
    echo "旧文件存在，正在删除..."
    rm -f "$FILE"
fi

# 下载文件
echo "正在下载最新的脚本..."
if wget -O "$FILE" "$URL"; then
    echo "下载完成。"

    # 赋予脚本执行权限
    chmod +x "$FILE"

    # 运行脚本
    echo "运行脚本..."
    ./"$FILE"
else
    echo "下载失败，请检查网络连接或URL是否正确。"
fi
