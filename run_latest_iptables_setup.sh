#!/bin/bash

# 设置下载 URL
URL="https://raw.githubusercontent.com/rd800919/script/refs/heads/main/iptables-setup2.sh"

# 设置保存的文件名
FILE="iptables-setup2.sh"

# 下载文件
echo "正在下载最新的脚本..."
wget -O $FILE $URL

# 赋予脚本执行权限
chmod +x $FILE

# 提示下载完成
echo "下载完成。"

# 运行脚本
echo "运行脚本..."
./$FILE
