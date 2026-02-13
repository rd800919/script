#!/bin/bash

# =========================================================
# 脚本由 BYY 设计 - 2026 最新修正版 [Version: 第一修正版]
# WeChat: x7077796
# 适用系统：Debian / Ubuntu / CentOS
# =========================================================

# 全局变量文件
RULES_FILE="/var/tmp/port_rules"
UDP_FLAG_FILE="/var/tmp/udp_opened"

# 判断操作系统类型
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
  echo -e "\e[36m============================================\e[0m"
  echo -e "\e[33m         中转服务器设置菜单 (简体中文)      \e[0m"
  echo -e "\e[36m============================================\e[0m"
  echo -e "\e[32m 1. 安装或更新必要工具 (初始化环境)\e[0m"
  echo -e "\e[32m 2. 设置中转规则 (TCP+UDP)\e[0m"
  echo -e "\e[32m 3. 清除所有设置 (重置防火墙)\e[0m"
  echo -e "\e[32m 4. 删除指定端口的转发规则\e[0m"
  echo -e "\e[32m 5. 查看当前中转规则 (记录+实况)\e[0m"
  echo -e "\e[32m 6. 启动 BBR 加速\e[0m"
  echo -e "\e[32m 0. 退出\e[0m"
  echo -e "\e[36m============================================\e[0m"
  echo -e "\e[35m 脚本由 BYY 设计 - 2026 最新修正版\e[0m"
  echo -e "\e[35m 版本状态：[第一修正版] (功能已补全)\e[0m"
  echo -e "\e[35m WeChat: x7077796\e[0m"
  echo -e "\e[36m============================================\e[0m"
  echo ""
}

# 保存iptables规则函数
save_iptables_rules() {
  local os=$(detect_os)
  echo -e "\e[34m正在保存 iptables 规则以防重启丢失...\e[0m"
  if [ "$os" == "Debian" ]; then
    if [ ! -d /etc/iptables ]; then mkdir -p /etc/iptables; fi
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    netfilter-persistent save 2>/dev/null
  elif [ "$os" == "CentOS" ]; then
    service iptables save
  fi
  echo -e "\e[32m规则保存成功。\e[0m"
}

# 自动检测内网 IP
detect_internal_ip() {
  local interface=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
  if [[ -z "$interface" ]]; then
    echo ""
    return 1
  fi
  local ip_addr=$(ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  echo "$ip_addr"
}

# 1. 安装或更新工具
install_update_tools() {
  local os=$(detect_os)
  echo -e "\e[34m正在初始化环境...\e[0m"

  if [ "$os" == "Debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables net-tools iptables-persistent netfilter-persistent
    if command -v ufw >/dev/null 2>&1 && ufw status | grep -q 'active'; then
        echo -e "\e[33m禁用 ufw...\e[0m"
        ufw disable
    fi
  elif [ "$os" == "CentOS" ]; then
    yum update -y
    yum install -y iptables-services net-tools
    if systemctl is-active firewalld >/dev/null 2>&1; then
      echo -e "\e[33m禁用 firewalld...\e[0m"
      systemctl stop firewalld
      systemctl disable firewalld
    fi
    systemctl enable iptables
    systemctl start iptables
  else
    echo -e "\e[31m不支持的系统。\e[0m"; exit 1
  fi

  # 开启内核转发
  echo -e "\e[34m开启 IPv4 转发...\e[0m"
  sed -i '/net.ipv4.ip_forward/d' /etc/sysctl.conf
  echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1
  echo -e "\e[32m环境初始化完成。\e[0m\n"
}

# 2. 添加中转规则
add_forward_rule() {
  local_ip=$(detect_internal_ip)
  if [[ -z "$local_ip" ]]; then echo -e "\e[31m无法检测内网IP，请检查网络。\e[0m"; return; fi

  read -p "请输入目标(远程)IP地址: " target_ip
  read -p "请输入起始转发端口: " start_port
  read -p "请输入结束转发端口: " end_port

  # 校验输入
  if [[ ! "$start_port" =~ ^[0-9]+$ ]] || [[ $start_port -gt 65535 || $start_port -gt $end_port ]]; then
    echo -e "\e[31m输入的端口范围无效。\e[0m"; return
  fi

  echo -e "\e[34m配置 TCP 中转规则: $start_port-$end_port -> $target_ip\e[0m"
  # TCP 规则
  iptables -I FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT
  iptables -t nat -A PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip"
  iptables -t nat -A POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip"

  # UDP 规则 (检测是否首次开启全局 UDP)
  if [ ! -f "$UDP_FLAG_FILE" ]; then
    echo -e "\e[34m检测到首次配置，添加 UDP 全局转发规则 (1500-65535)...\e[0m"
    iptables -I FORWARD -p udp --dport 1500:65535 -j ACCEPT
    iptables -t nat -A PREROUTING -p udp -j DNAT --to-destination "$target_ip"
    iptables -t nat -A POSTROUTING -d "$target_ip" -p udp -j SNAT --to-source "$local_ip"
    touch "$UDP_FLAG_FILE"
  fi
  
  # 通用：允许已建立的连接
  iptables -I FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
  
  # 记录到本地文件
  echo "$start_port-$end_port $target_ip" >> "$RULES_FILE"
  save_iptables_rules
  echo -e "\e[32m规则配置完成并已生效。\e[0m\n"
}

# 3. 清除所有设置
clear_all_rules() {
  echo -e "\e[31m！！！警告：这将清空所有防火墙规则和转发设置！！！\e[0m"
  read -p "确认清空吗？(y/n): " confirm
  if [[ "$confirm" == "y" ]]; then
    iptables -F
    iptables -t nat -F
    iptables -X
    iptables -t nat -X
    rm -f "$RULES_FILE" "$UDP_FLAG_FILE"
    # 基础保护：依然允许已建立的连接
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    save_iptables_rules
    echo -e "\e[32m所有规则已成功清空。\e[0m\n"
  fi
}

# 4. 删除指定端口规则
delete_specific_rule() {
  if [ ! -s "$RULES_FILE" ]; then echo -e "\e[31m当前没有任何记录。\e[0m"; return; fi
  local_ip=$(detect_internal_ip)
  
  echo -e "\e[33m请选择要删除的规则序号：\e[0m"
  nl -ba "$RULES_FILE"
  read -p "请输入序号 (输入 q 退出): " line_num
  [[ "$line_num" == "q" ]] && return

  rule_content=$(sed -n "${line_num}p" "$RULES_FILE")
  if [[ -z "$rule_content" ]]; then echo -e "\e[31m序号不存在。\e[0m"; return; fi

  ports=$(echo $rule_content | awk '{print $1}')
  target_ip=$(echo $rule_content | awk '{print $2}')
  start_port=$(echo $ports | cut -d'-' -f1)
  end_port=$(echo $ports | cut -d'-' -f2)

  echo -e "\e[34m正在删除端口 $ports 的转发规则...\e[0m"
  iptables -D FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT 2>/dev/null
  iptables -t nat -D PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip" 2>/dev/null
  iptables -t nat -D POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip" 2>/dev/null
  
  sed -i "${line_num}d" "$RULES_FILE"
  save_iptables_rules
  echo -e "\e[32m删除成功。\e[0m\n"
}

# 5. 查看当前规则 (增强版)
view_current_rules() {
  echo -e "\e[36m=== 脚本历史记录 ($RULES_FILE) ===\e[0m"
  if [ -f "$RULES_FILE" ]; then nl -ba "$RULES_FILE"; else echo "无记录"; fi

  echo -e "\n\e[36m=== 实时：防火墙许可状态 (FORWARD 链) ===\e[0m"
  # 能够看到 UDP 1500:65535 的许可
  iptables -L FORWARD -n -v --line-numbers | grep -E "Chain|dpts|Target|udp"

  echo -e "\n\e[36m=== 实时：DNAT 转发 (PREROUTING) ===\e[0m"
  iptables -t nat -L PREROUTING -n -v --line-numbers | grep "DNAT"
  
  echo -e "\n\e[36m=== 实时：SNAT 伪装 (POSTROUTING) ===\e[0m"
  iptables -t nat -L POSTROUTING -n -v --line-numbers | grep "SNAT"
  echo ""
  read -p "按回车键返回菜单..."
}

# 6. 启动 BBR
enable_bbr() {
  echo -e "\e[34m正在检查并启动 BBR 加速...\e[0m"
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
  sysctl -p >/dev/null 2>&1
  
  if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo -e "\e[32mBBR 开启成功！\e[0m"
  else
    echo -e "\e[31m开启失败，可能内核版本过低或环境不支持。\e[0m"
  fi
}

# 主程序循环
while true; do
  show_menu
  read -p "请输入选项 (0-6): " choice
  case $choice in
    1) install_update_tools ;;
    2) add_forward_rule ;;
    3) clear_all_rules ;;
    4) delete_specific_rule ;;
    5) view_current_rules ;;
    6) enable_bbr ;;
    0) echo -e "\e[32m退出程序。\e[0m"; exit 0 ;;
    *) echo -e "\e[31m无效选项，请重新输入。\e[0m" ;;
  esac
done
