#!/bin/bash

# =========================================================
# 脚本由 BYY 设计 - 2026 最新修正版 [Version: 第一修正版]
# WeChat: x7077796
# 定制需求：游戏转发专用 + 全域 UDP 转发
# =========================================================

# 定义记录文件路径
RULES_FILE="/var/tmp/port_rules"
UDP_FLAG_FILE="/var/tmp/udp_opened"

# 检测操作系统
detect_os() {
  if [ -f /etc/debian_version ]; then
    echo "Debian"
  elif [ -f /etc/redhat-release ]; then
    echo "CentOS"
  else
    echo "Unsupported"
  fi
}

# 显示菜单
show_menu() {
  echo -e "\e[36m============================================\e[0m"
  echo -e "\e[33m         中转服务器设置菜单 (游戏专用版2)      \e[0m"
  echo -e "\e[36m============================================\e[0m"
  echo -e "\e[32m 1. 安装或更新必要工具 (初始化环境)\e[0m"
  echo -e "\e[32m 2. 设置中转规则 (TCP精准+UDP全域)\e[0m"
  echo -e "\e[32m 3. 清除所有设置 (重置防火墙)\e[0m"
  echo -e "\e[32m 4. 删除指定序号的转发规则\e[0m"
  echo -e "\e[32m 5. 查看当前转发状态 (记录+实况)\e[0m"
  echo -e "\e[32m 6. 启动 BBR 加速 (降低游戏延迟)\e[0m"
  echo -e "\e[32m 0. 退出\e[0m"
  echo -e "\e[36m============================================\e[0m"
  echo -e "\e[35m 脚本由 BYY 设计 - 2026 最新修正版\e[0m"
  echo -e "\e[35m 版本状态：[第一修正版]\e[0m"
  echo -e "\e[35m WeChat: x7077796\e[0m"
  echo -e "\e[36m============================================\e[0m"
  echo ""
}

# 自动保存防火墙规则
save_iptables() {
  local os=$(detect_os)
  echo -e "\e[34m正在永久保存规则...\e[0m"
  if [ "$os" == "Debian" ]; then
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    netfilter-persistent save >/dev/null 2>&1
  elif [ "$os" == "CentOS" ]; then
    service iptables save >/dev/null 2>&1
  fi
  echo -e "\e[32m[OK] 规则已保存，重启不会丢失。\e[0m"
}

# 获取本机内网 IP
get_local_ip() {
  local ip=$(ip -4 addr show $(ip -4 route ls | grep default | awk '{print $5}' | head -1) | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  echo "$ip"
}

# 1. 环境初始化
install_tools() {
  local os=$(detect_os)
  echo -e "\e[34m正在优化系统环境以适合游戏转发...\e[0m"
  
  if [ "$os" == "Debian" ]; then
    apt update -y && apt install -y iptables iptables-persistent netfilter-persistent net-tools
    if command -v ufw >/dev/null 2>&1; then ufw disable >/dev/null 2>&1; fi
  elif [ "$os" == "CentOS" ]; then
    yum install -y iptables-services net-tools
    systemctl disable firewalld && systemctl stop firewalld
    systemctl enable iptables && systemctl start iptables
  else
    echo -e "\e[31m不支持的操作系统。\e[0m"; exit 1
  fi

  # 开启内核转发
  echo -e "\e[34m配置内核 IPv4 转发参数...\e[0m"
  sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1

  # 【核心优化】MSS 锁定：防止游戏封包过大导致卡顿或掉线
  echo -e "\e[34m设置 TCPMSS 游戏环境优化...\e[0m"
  iptables -t mangle -F POSTROUTING
  iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1460
  
  save_iptables
  echo -e "\e[32m初始化完成！系统已调整至游戏转发最佳状态。\e[0m\n"
}

# 2. 添加规则
add_rule() {
  local_ip=$(get_local_ip)
  if [[ -z "$local_ip" ]]; then echo -e "\e[31m检测不到内网IP，请先执行选项1。\e[0m"; return; fi

  read -p "请输入目标(远程)IP地址: " target_ip
  read -p "请输入起始转发端口: " s_port
  read -p "请输入结束转发端口: " e_port

  if [[ ! "$s_port" =~ ^[0-9]+$ ]] || [ "$s_port" -gt "$e_port" ]; then
    echo -e "\e[31m输入错误：端口号必须为数字且起始端口不能大于结束端口。\e[0m"; return
  fi

  echo -e "\e[34m正在应用规则: TCP $s_port-$e_port -> $target_ip\e[0m"
  
  # TCP 转发 (使用 -I 插入到最前，保证最高优先级)
  iptables -t nat -I PREROUTING -p tcp --dport "$s_port":"$e_port" -j DNAT --to-destination "$target_ip"
  iptables -t nat -I POSTROUTING -p tcp -d "$target_ip" --dport "$s_port":"$e_port" -j SNAT --to-source "$local_ip"
  iptables -I FORWARD -p tcp --dport "$s_port":"$e_port" -j ACCEPT

  # 全域 UDP 转发 (根据您的要求：保持全域 1500-65535)
  if [ ! -f "$UDP_FLAG_FILE" ]; then
    echo -e "\e[33m首次设置：正在开启全域 UDP 转发 (1500-65535) 以适配所有游戏端口...\e[0m"
    iptables -t nat -I PREROUTING -p udp --dport 1500:65535 -j DNAT --to-destination "$target_ip"
    iptables -t nat -I POSTROUTING -p udp -d "$target_ip" --dport 1500:65535 -j SNAT --to-source "$local_ip"
    iptables -I FORWARD -p udp --dport 1500:65535 -j ACCEPT
    touch "$UDP_FLAG_FILE"
  fi

  # 允许已建立的连线通行
  iptables -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # 记录到文件
  echo "$s_port-$e_port $target_ip" >> "$RULES_FILE"
  save_iptables
  echo -e "\e[32m中转规则添加成功！游戏转发已生效。\e[0m\n"
}

# 3. 清除设置
clear_all() {
  read -p "确定要清空所有规则吗？这会导致当前所有中转中断 (y/n): " choice
  if [ "$choice" == "y" ]; then
    echo -e "\e[34m正在重置防火墙...\e[0m"
    iptables -F
    iptables -t nat -F
    iptables -t mangle -F
    iptables -X
    iptables -t nat -X
    rm -f "$RULES_FILE" "$UDP_FLAG_FILE"
    # 重新应用基础优化，防止掉线
    iptables -t mangle -A POSTROUTING -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1460
    save_iptables
    echo -e "\e[32m所有规则已成功清空。\e[0m\n"
  fi
}

# 4. 删除指定规则
delete_rule() {
  if [ ! -s "$RULES_FILE" ]; then echo -e "\e[31m当前没有记录。\e[0m"; return; fi
  local_ip=$(get_local_ip)
  
  echo -e "\e[33m当前已生效的 TCP 转发列表：\e[0m"
  nl -ba "$RULES_FILE"
  read -p "请输入要删除的规则序号: " num
  
  content=$(sed -n "${num}p" "$RULES_FILE")
  if [ -z "$content" ]; then echo -e "\e[31m无效序号。\e[0m"; return; fi

  ports=$(echo $content | awk '{print $1}')
  tip=$(echo $content | awk '{print $2}')
  s_p=$(echo $ports | cut -d'-' -f1)
  e_p=$(echo $ports | cut -d'-' -f2)

  echo -e "\e[34m正在删除 TCP 规则: $ports ...\e[0m"
  iptables -t nat -D PREROUTING -p tcp --dport "$s_p":"$e_p" -j DNAT --to-destination "$tip" 2>/dev/null
  iptables -t nat -D POSTROUTING -p tcp -d "$tip" --dport "$s_p":"$e_p" -j SNAT --to-source "$local_ip" 2>/dev/null
  iptables -D FORWARD -p tcp --dport "$s_p":"$e_p" -j ACCEPT 2>/dev/null

  sed -i "${num}d" "$RULES_FILE"
  save_iptables
  echo -e "\e[32m该条规则已成功删除。\e[0m\n"
}

# 5. 查看规则
view_rules() {
  echo -e "\e[36m=== 脚本历史记录 (TCP) ===\e[0m"
  if [ -f "$RULES_FILE" ]; then nl -ba "$RULES_FILE"; else echo "无记录"; fi
  
  echo -e "\n\e[36m=== 实时 NAT 映射实况 (包含 UDP 全域) ===\e[0m"
  iptables -t nat -L PREROUTING -n -v --line-numbers | grep -E "DNAT|udp|tcp"
  
  echo -e "\n\e[36m=== 游戏优化状态 (MSS) ===\e[0m"
  iptables -t mangle -L POSTROUTING -n -v | grep "TCPMSS"
  echo ""
  read -p "按回车键返回主菜单..."
}

# 6. 启动 BBR
run_bbr() {
  echo -e "\e[34m正在启动内核 BBR 加速以降低波动与延迟...\e[0m"
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1
  
  if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo -e "\e[32mBBR 加速开启成功！建议重启服务器以达到最佳效果。\e[0m\n"
  else
    echo -e "\e[31mBBR 开启失败，请检查内核版本是否高于 4.9。\e[0m\n"
  fi
}

# 运行主循环
while true; do
  show_menu
  read -p "请输入选项序号 [0-6]: " opt
  case $opt in
    1) install_tools ;;
    2) add_rule ;;
    3) clear_all ;;
    4) delete_rule ;;
    5) view_rules ;;
    6) run_bbr ;;
    0) 
      echo -e "\e[1;35m------------------------------------------------\e[0m"
      echo -e "\e[1;32m温馨提示：以后在任意路径输入 \e[1;33mbyy\e[1;32m 即可进入本菜单\e[0m"
      echo -e "\e[1;35m------------------------------------------------\e[0m"
      echo -e "\e[32m退出程序。祝您游戏愉快！\e[0m"
      exit 0 
      ;;
    *) echo -e "\e[31m输入错误，请输入 0 到 6 之间的数字。\e[0m" ;;
  esac
done
