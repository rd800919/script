#!/bin/bash

# 確保腳本以 root 用戶運行
if [[ $EUID -ne 0 ]]; then
  echo "請使用 root 權限運行此腳本"
  exit 1
fi

# 檢查並安裝所需軟件包
install_if_missing() {
  if ! dpkg -l | grep -q $1; then
    echo "$1 未安裝，正在安裝..."
    apt install -y $1
  else
    echo "$1 已安裝，跳過..."
  fi
}

# 更新系統和安裝所需軟件包
apt update -y
install_if_missing curl
install_if_missing wget
install_if_missing make
install_if_missing git

# 配置BBR
if ! sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
  echo "配置BBR..."
  echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
  sysctl -p
  lsmod | grep bbr
else
  echo "BBR 已配置，跳過..."
fi

# 安裝 x-ui 並執行後續操作
bash <(curl -Ls https://github.com/rd800919/script/raw/refs/heads/main/xui-install.sh)

# 等待安裝完成，切換到主目錄並刪除 x-ui.db
if [ -f "/etc/x-ui/x-ui.db" ]; then
  echo "刪除舊的 x-ui.db 文件..."
  rm -f /etc/x-ui/x-ui.db
fi

# 下載新的 x-ui.db 文件
wget -N https://github.com/rd800919/script/raw/refs/heads/main/x-ui.db

# 重啟 x-ui 並設置開機自啟
systemctl restart x-ui
systemctl enable x-ui

# 如果 wondershaper 文件夾已經存在，則強制刪除
if [ -d "/root/wondershaper" ]; then
  echo "刪除舊的 wondershaper 文件夾..."
  rm -rf /root/wondershaper
fi

# 如果 systemd 中已有 wondershaper 服務文件，則刪除
if [ -f "/etc/systemd/system/wondershaper.service" ]; then
  echo "刪除舊的 wondershaper.service 文件..."
  rm -f /etc/systemd/system/wondershaper.service
fi

# 克隆 wondershaper 並安裝
git clone https://github.com/magnific0/wondershaper.git /root/wondershaper
cd /root/wondershaper
make install

# 創建 wondershaper systemd 服務文件
cat <<EOL > /etc/systemd/system/wondershaper.service
[Unit]
Description=Set bandwidth limits using wondershaper
After=network.target network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/wondershaper -a eth0 -d 7000 -u 7000
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOL

# 重新加載 systemd 並啟用服務
systemctl daemon-reload
systemctl enable wondershaper.service
systemctl restart wondershaper.service

# 設置完成提示
echo "所有操作完成，x-ui 已安裝並配置好，網絡帶寬限制也已設置，且在重啟後仍有效。"
