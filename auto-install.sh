#!/bin/bash

# 切换到root用户
sudo -i

# 更新系统和安装curl、wget
apt update -y
apt install -y curl
apt-get install wget -y

# 配置BBR
echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
sysctl -p
lsmod | grep bbr

# 安装x-ui并执行后续操作
bash <(curl -Ls https://github.com/rd800919/script/raw/refs/heads/main/xui-install.sh)

# 切换目录并删除x-ui.db
cd
rm -f /etc/x-ui/x-ui.db

# 下载新的x-ui.db文件
wget -P /etc/x-ui -N https://github.com/rd800919/script/raw/refs/heads/main/x-ui.db

# 重启并启用x-ui服务
systemctl restart x-ui
systemctl enable x-ui

# 安装make和git
apt install make git -y

# 克隆wondershaper项目并安装
git clone https://github.com/magnific0/wondershaper.git
cd wondershaper
make install

# 返回主目录并执行wondershaper
cd
wondershaper -a eth0 -d 7000 -u 7000
