#!/bin/bash

# 设置下载 URL
URL="https://raw.githubusercontent.com/rd800919/script/refs/heads/main/iptables-setup2.sh"

# 设置保存的文件名
FILE="iptables-setup2.sh"

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
