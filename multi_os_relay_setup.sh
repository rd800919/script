#!/bin/bash

# 判斷操作系統類型
detect_os() {
  if [ -f /etc/debian_version ]; then
    echo "Debian"
  elif [ -f /etc/redhat-release ]; then
    echo "CentOS"
  else
    echo "Unsupported"
  fi
}

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
  echo -e "\e[35m脚本由 BYY 设计-v005\e[0m"
  echo -e "\e[35mWeChat: x7077796\e[0m"
  echo -e "\e[36m==============================\e[0m"
  echo ""
}

# 安装或更新必要工具的函数
install_update_tools() {
  local os=$(detect_os)
  
  echo -e "\e[34m正在安装或更新必要的工具...\e[0m"

  if [ "$os" == "Debian" ]; then
    # 更新包管理器并安装iptables、net-tools和iptables-persistent（如果尚未安装）
    DEBIAN_FRONTEND=noninteractive apt update -y && apt upgrade -y -o 'APT::Get::Assume-Yes=true'
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables net-tools iptables-persistent

    # 禁用 ufw 防火墙（如果存在且激活）
    if command -v ufw >/dev/null 2>&1; then
      ufw_status=$(ufw status | grep -o 'active')
      if [[ "$ufw_status" == "active" ]]; then
        echo -e "\e[33m发现 ufw 防火墙正在运行，正在禁用...\e[0m"
        ufw disable
        echo -e "\e[32mufw 已禁用。\e[0m"
      fi
    fi

  elif [ "$os" == "CentOS" ]; then
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
  else
    echo -e "\e[31m不支持的操作系统。\e[0m"
    exit 1
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

# 保存iptables规则函数
save_iptables_rules() {
  local os=$(detect_os)
  if [ "$os" == "Debian" ]; then
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
  elif [ "$os" == "CentOS" ]; then
    service iptables save
  fi
}

# 其余函数（例如：detect_internal_ip、add_forward_rule 等）保持不变，只需要保存规则的部分根据系统不同来调用相应的保存函数。

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
    save_iptables_rules

    echo -e "\e[32m中转规则配置完成。\e[0m"
    echo ""
  else
    echo -e "\e[31m无效的端口范围，请确保输入的端口在 1 到 65535 之间，且起始端口小于或等于结束端口。\e[0m"
    echo ""
  fi
}

# 主程序循環保持一致
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
