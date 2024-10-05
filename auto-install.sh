#!/bin/bash

# 確保腳本以 root 用戶運行
if [[ $EUID -ne 0 ]]; then
  echo "請使用 root 權限運行此腳本"
  exit 1
fi

# 更新系統和安裝 curl、wget
apt update -y
apt install -y curl
apt install -y wget

# 配置BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
lsmod | grep bbr

# 安裝x-ui並執行後續操作
bash <(curl -Ls https://github.com/rd800919/script/raw/refs/heads/main/xui-install.sh)

# 等待安裝完成，切換到主目錄並刪除 x-ui.db
cd /etc/x-ui/
rm -f x-ui.db

# 下載新的 x-ui.db 文件
wget -N https://github.com/rd800919/script/raw/refs/heads/main/x-ui.db

# 重啟 x-ui 並設置開機自啟
systemctl restart x-ui
systemctl enable x-ui

# 安裝 make 和 git
apt install make git -y

# 克隆 wondershaper 並安裝
cd /root
git clone https://github.com/magnific0/wondershaper.git
cd wondershaper
make install

# 設置網絡帶寬限制
wondershaper -a eth0 -d 7000 -u 7000

# 完成所有操作
echo "所有操作完成，x-ui 已安裝並配置好，網絡帶寬限制也已設置。"
