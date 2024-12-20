#!/bin/bash

# 定义显示菜单的函数
show_menu() {
  echo -e "\e[36m==============================\e[0m"
  echo -e "\e[33m 中转服务器设置菜单 \e[0m"
  echo -e "\e[36m==============================\e[0m"
  echo -e "\e[32m1. 安装或更新必要工具\e[0m"
  echo -e "\e[32m2. 设置中转规则\e[0m"
  echo -e "\e[32m3. 清除所有设置\e[0m"
  echo -e "\e[32m4. 删除指定端口的转发规则\e[0m"
  echo -e "\e[32m5. 查看当前中转规则\e[0m"
  echo -e "\e[32m6. 启动BBR\e[0m"
  echo -e "\e[32m0. 退出\e[0m"
  echo -e "\e[36m==============================\e[0m"
  echo -e "\e[35m脚本由 BYY 设计-v004\e[0m"
  echo -e "\e[35mWeChat: x7077796\e[0m"
  echo -e "\e[36m==============================\e[0m"
  echo ""
}

# 安装或更新必要工具的函数
install_update_tools() {
  echo -e "\e[34m正在安装或更新必要的工具...\e[0m"
  # 更新包管理器并安装iptables、net-tools（如果尚未安装）
  yum update -y
  yum install -y iptables-services net-tools
  
  # 禁用 firewalld 防火墙（如果存在且激活）
  if systemctl is-active firewalld >/dev/null 2>&1; then
    echo -e "\e[33m发现 firewalld 防火墙正在运行，正在禁用...\e[0m"
    systemctl stop firewalld
    systemctl disable firewalld
    echo -e "\e[32mfirewalld 已禁用。\e[0m"
  fi
  
  # 配置基本的防火墙规则和 IP 转发
  echo -e "\e[34m配置基本的防火墙规则和 IP 转发...\e[0m"
  sysctl_conf="/etc/sysctl.conf"
  if ! grep -q "net.ipv4.ip_forward = 1" "$sysctl_conf"; then
    echo "net.ipv4.ip_forward = 1" | tee -a "$sysctl_conf"
  fi
  sysctl -p

  echo -e "\e[32m工具安装或更新完成。\e[0m"
  echo ""
}

# 自动检测内网 IP 和网卡名称的函数
detect_internal_ip() {
  local interface=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
  
  if [[ -z "$interface" ]]; then
    echo -e "\e[31m未能自动检测到网卡。\e[0m"
    exit 1
  fi

  local ip_addr=$(ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  
  if [[ -z "$ip_addr" ]]; then
    echo -e "\e[31m未能自动检测到内网 IP。\e[0m"
    exit 1
  fi

  echo "$ip_addr"
}

# 添加中转规则的函数
add_forward_rule() {
  read -p "请输入需要被中转的目标IP地址: " target_ip
  read -p "请输入起始转发端口: " start_port
  read -p "请输入结尾转发端口: " end_port

  # 自动获取内网地址
  local_ip=$(detect_internal_ip)

  # 记录 UDP 是否已经全局开启
  local udp_opened_file="/var/tmp/udp_opened"
  udp_opened=false
  if [[ -f "$udp_opened_file" ]]; then
    udp_opened=true
  fi

  # 验证输入是否为有效的端口范围
  if [[ $start_port -gt 0 && $start_port -le 65535 && $end_port -gt 0 && $end_port -le 65535 && $start_port -le $end_port ]]; then
    # 添加新的iptables规则
    echo -e "\e[34m正在配置中转规则，目标IP: $target_ip, 端口范围: $start_port-$end_port\e[0m"

    # 允许所有来自外部的 TCP 流量的转发
    iptables -I FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT

    # 如果是第一次设置中转规则，且UDP规则尚未添加，开启全局 UDP 端口 1500-65535 的转发
    if [ "$udp_opened" = false ]; then
      if ! iptables -C FORWARD -p udp --dport 1500:65535 -j ACCEPT 2>/dev/null; then
        echo -e "\e[34m正在配置 UDP 全局转发，范围: 1500-65535\e[0m"
        iptables -I FORWARD -p udp --dport 1500:65535 -j ACCEPT
        touch "$udp_opened_file"
      fi
    fi

    # 允许已建立和相关的连接，确保返回流量能正确通过
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # DNAT 将进入的连接转发到目标IP
    iptables -t nat -A PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip"
    if [ "$udp_opened" = false ]; then
      iptables -t nat -A PREROUTING -p udp -j DNAT --to-destination "$target_ip"
    fi

    # SNAT 修改源地址为本地内网地址，确保回复能正确返回
    iptables -t nat -A POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip"
    if [ "$udp_opened" = false ]; then
      iptables -t nat -A POSTROUTING -d "$target_ip" -p udp -j SNAT --to-source "$local_ip"
    fi

    # 将规则记录到文件中以便后续管理
    echo "$start_port-$end_port $target_ip" >> /var/tmp/port_rules

    # 保存变更以确保重启后生效
    service iptables save

    echo -e "\e[32m中转规则配置完成。\e[0m"
    echo ""
  else
    echo -e "\e[31m无效的端口范围，请确保输入的端口在 1 到 65535 之间，且起始端口小于或等于结束端口。\e[0m"
    echo ""
  fi
}

# 清除所有设置的函数
clear_all_rules() {
  echo -e "\e[33m正在清除所有防火墙规则...\e[0m"
  iptables -t nat -F
  iptables -F FORWARD

  # 清除记录 UDP 全局开启的标志
  rm -f /var/tmp/udp_opened
  rm -f /var/tmp/port_rules

  # 保存变更以确保重启后生效
  service iptables save

  echo -e "\e[32m所有防火墙规则已清除。\e[0m"
  echo ""
}

# 清除指定的 PREROUTING 和 POSTROUTING 规则的函数
clear_prerouting_postrouting() {
  echo -e "\e[36m当前的 PREROUTING 和 POSTROUTING 规则:\e[0m"
  iptables -t nat -L PREROUTING --line-numbers
  iptables -t nat -L POSTROUTING --line-numbers
  echo ""

  read -p "请输入要清除的规则行号: " rule_num
  if [[ -n "$rule_num" ]]; then
    iptables -t nat -D PREROUTING $rule_num
    iptables -t nat -D POSTROUTING $rule_num
    echo -e "\e[32mPREROUTING 和 POSTROUTING 规则已删除。\e[0m"
  else
    echo -e "\e[31m无效的规则行号，请重试。\e[0m"
  fi

  # 保存变更以确保重启后生效
  service iptables save
  echo ""
}

# 查看当前中转规则的函数
view_current_rules() {
  echo -e "\e[36m当前的中转规则:\e[0m"
  if [[ -f /var/tmp/port_rules ]]; then
    cat /var/tmp/port_rules
  else
    echo -e "\e[31m没有已设置的中转规则。\e[0m"
  fi
  echo ""
}

# 启动BBR的函数
enable_bbr() {
  if lsmod | grep -q "bbr"; then
    echo -e "\e[32mBBR 已经启用，无需再次启用。\e[0m"
  else
    echo -e "\e[33m警告: 启动BBR将会清除所有现有的转发规则！\e[0m"
    read -p "是否继续? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      clear_all_rules
      echo -e "\e[34m正在启用 BBR...\e[0m"
      echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
      echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
      sysctl -p
      if lsmod | grep -q "bbr"; then
        echo -e "\e[32mBBR 已成功启用。\e[0m"
      else
        echo -e "\e[31mBBR 启用失败。\e[0m"
      fi
    else
      echo -e "\e[31m操作已取消。\e[0m"
    fi
  fi
  echo ""
}

# 主循环
while true; do
  show_menu
  read -p "请选择一个选项 (0-6): " choice
  echo ""
  case $choice in
    1)
      install_update_tools
      ;;
    2)
      add_forward_rule
      ;;
    3)
      clear_all_rules
      ;;
    4)
      clear_prerouting_postrouting
      ;;
    5)
      view_current_rules
      ;;
    6)
      enable_bbr
      ;;
    0)
      echo -e "\e[32m退出程序。\e[0m"
      exit 0
      ;;
    *)
      echo -e "\e[31m无效的选项，请输入 0, 1, 2, 3, 4, 5 或 6。\e[0m"
      ;;
  esac
done
