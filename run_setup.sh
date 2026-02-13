#!/bin/bash

# =========================================================
# 中转服务器设置脚本 - 完整修正版
# 包含功能：IP转发、BBR、规则管理（增/删/查/清空）
# =========================================================

# 全局变量文件
RULES_FILE="/var/tmp/port_rules"
UDP_FLAG_FILE="/var/tmp/udp_opened"

# 判断操作系統類型
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
  echo -e "\e[33m 中转服务器设置菜单 (修正完整版) \e[0m"
  echo -e "\e[36m==============================\e[0m"
  echo -e "\e[32m1. 安装或更新必要工具 (初始化环境)\e[0m"
  echo -e "\e[32m2. 添加中转规则 (TCP+UDP)\e[0m"
  echo -e "\e[32m3. 清除所有设置 (重置防火墙)\e[0m"
  echo -e "\e[32m4. 删除指定端口的转发规则\e[0m"
  echo -e "\e[32m5. 查看当前中转规则 (记录+实况)\e[0m"
  echo -e "\e[32m6. 开启/检查 BBR 加速\e[0m"
  echo -e "\e[32m0. 退出\e[0m"
  echo -e "\e[36m==============================\e[0m"
  echo -e "\e[35m脚本修正完成，功能已全部实装\e[0m"
  echo -e "\e[36m==============================\e[0m"
  echo ""
}

# 保存iptables规则函数
save_iptables_rules() {
  local os=$(detect_os)
  echo -e "\e[34m正在保存 iptables 规则...\e[0m"
  if [ "$os" == "Debian" ]; then
    if [ ! -d /etc/iptables ]; then mkdir -p /etc/iptables; fi
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
    netfilter-persistent save 2>/dev/null
  elif [ "$os" == "CentOS" ]; then
    service iptables save
  fi
  echo -e "\e[32m规则已保存，重启依然生效。\e[0m"
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

# 安装或更新必要工具的函数
install_update_tools() {
  local os=$(detect_os)
  
  echo -e "\e[34m正在安装或更新必要的工具...\e[0m"

  if [ "$os" == "Debian" ]; then
    DEBIAN_FRONTEND=noninteractive apt update -y
    DEBIAN_FRONTEND=noninteractive apt-get install -y iptables net-tools iptables-persistent netfilter-persistent

    if command -v ufw >/dev/null 2>&1; then
      if ufw status | grep -q 'active'; then
        ufw disable
        echo -e "\e[32mufw 已禁用。\e[0m"
      fi
    fi

  elif [ "$os" == "CentOS" ]; then
    yum update -y
    yum install -y iptables-services net-tools

    if systemctl is-active firewalld >/dev/null 2>&1; then
      systemctl stop firewalld
      systemctl disable firewalld
      echo -e "\e[32mfirewalld 已禁用。\e[0m"
    fi
    # 确保 iptables 服务启动
    systemctl enable iptables
    systemctl start iptables
  else
    echo -e "\e[31m不支持的操作系统。\e[0m"
    exit 1
  fi

  # 开启 IP 转发
  echo -e "\e[34m配置系统 IP 转发...\e[0m"
  if ! grep -q "net.ipv4.ip_forward = 1" /etc/sysctl.conf; then
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
  fi
  sysctl -p >/dev/null 2>&1

  echo -e "\e[32m工具安装与环境配置完成。\e[0m"
  echo ""
}

# 添加中转规则
add_forward_rule() {
  local_ip=$(detect_internal_ip)
  if [[ -z "$local_ip" ]]; then
    echo -e "\e[31m无法检测到内网IP，请检查网络配置。\e[0m"
    return
  fi

  read -p "请输入目标IP地址: " target_ip
  read -p "请输入起始端口 (例如 8000): " start_port
  read -p "请输入结束端口 (例如 8005，若单端口则输入相同的): " end_port

  # 验证端口
  if [[ ! "$start_port" =~ ^[0-9]+$ ]] || [[ ! "$end_port" =~ ^[0-9]+$ ]]; then
     echo -e "\e[31m端口必须是数字。\e[0m"
     return
  fi
  
  if [[ $start_port -gt 65535 || $end_port -gt 65535 || $start_port -gt $end_port ]]; then
    echo -e "\e[31m端口范围无效 (1-65535, 且起始<=结束)。\e[0m"
    return
  fi

  echo -e "\e[34m正在配置规则: 本机 $start_port:$end_port -> $target_ip\e[0m"

  # 1. 允许 TCP 转发 (FORWARD链)
  iptables -I FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT

  # 2. PREROUTING (DNAT: 进来的流量转给目标IP)
  iptables -t nat -A PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip"

  # 3. POSTROUTING (SNAT: 出去的流量伪装成本机IP，确保握手成功)
  iptables -t nat -A POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip"

  # 处理 UDP (保留原脚本逻辑：如果没开过UDP，则全局开启一次)
  if [ ! -f "$UDP_FLAG_FILE" ]; then
    echo -e "\e[34m检测到首次配置，添加 UDP 全局转发 (1500-65535)...\e[0m"
    iptables -I FORWARD -p udp --dport 1500:65535 -j ACCEPT
    # UDP 的 NAT 规则
    iptables -t nat -A PREROUTING -p udp -j DNAT --to-destination "$target_ip"
    iptables -t nat -A POSTROUTING -d "$target_ip" -p udp -j SNAT --to-source "$local_ip"
    touch "$UDP_FLAG_FILE"
  else
    # 如果已有UDP标记，针对该目标IP追加 UDP 规则 (可选，此处暂保持原逻辑只做TCP精准控制，UDP跟随之前的全局)
    # 若需精准控制UDP，可仿照TCP写规则
    :
  fi
  
  # 允许已建立连接
  iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  # 记录到文件 (格式: Start-End TargetIP)
  echo "$start_port-$end_port $target_ip" >> "$RULES_FILE"

  save_iptables_rules
  echo -e "\e[32m规则添加成功！\e[0m"
}

# 删除指定规则 (实现功能)
delete_specific_rule() {
  if [ ! -f "$RULES_FILE" ] || [ ! -s "$RULES_FILE" ]; then
    echo -e "\e[31m当前没有已记录的转发规则。\e[0m"
    return
  fi

  local_ip=$(detect_internal_ip)

  echo -e "\e[33m当前规则列表：\e[0m"
  # 显示带行号的规则
  nl -ba "$RULES_FILE"
  echo ""
  read -p "请输入要删除的规则序号 (输入 q 取消): " line_num

  if [[ "$line_num" == "q" ]]; then return; fi
  if [[ ! "$line_num" =~ ^[0-9]+$ ]]; then echo -e "\e[31m无效输入。\e[0m"; return; fi

  # 获取文件中的行内容
  rule_content=$(sed -n "${line_num}p" "$RULES_FILE")
  
  if [[ -z "$rule_content" ]]; then
    echo -e "\e[31m找不到该序号的规则。\e[0m"
    return
  fi

  # 解析 Start-End TargetIP
  # 格式如: 8080-8090 1.1.1.1
  ports=$(echo $rule_content | awk '{print $1}')
  target_ip=$(echo $rule_content | awk '{print $2}')
  
  start_port=$(echo $ports | cut -d'-' -f1)
  end_port=$(echo $ports | cut -d'-' -f2)

  echo -e "\e[34m正在删除规则: 端口 $ports -> $target_ip ...\e[0m"

  # 执行 iptables 删除命令 (参数需与添加时完全一致)
  # 1. 删除 FORWARD
  iptables -D FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT 2>/dev/null

  # 2. 删除 PREROUTING (DNAT)
  iptables -t nat -D PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip" 2>/dev/null

  # 3. 删除 POSTROUTING (SNAT)
  iptables -t nat -D POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip" 2>/dev/null

  # 从文件中删除该行
  sed -i "${line_num}d" "$RULES_FILE"

  save_iptables_rules
  echo -e "\e[32m规则已从 iptables 和记录文件中删除。\e[0m"
}

# 清除所有规则 (实现功能)
clear_all_rules() {
  echo -e "\e[31m警告：这将清除所有 iptables NAT 表规则和转发规则！\e[0m"
  read -p "确定要继续吗？(y/n): " confirm
  if [[ "$confirm" != "y" ]]; then return; fi

  echo -e "\e[34m正在重置防火墙规则...\e[0m"

  # 清空 NAT 表
  iptables -t nat -F
  iptables -t nat -X

  # 清空 Filter 表的 Forward 链 (注意不要把自己锁在外面，Input链通常不动)
  iptables -F FORWARD

  # 删除记录文件
  rm -f "$RULES_FILE"
  rm -f "$UDP_FLAG_FILE"

  # 重新应用基础配置 (允许已建立连接，避免断连)
  iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

  save_iptables_rules
  echo -e "\e[32m所有转发设置已清除。\e[0m"
}

# 查看规则 (优化版)
view_current_rules() {
  echo -e "\e[36m=== 脚本记录的规则 (/var/tmp/port_rules) ===\e[0m"
  if [ -f "$RULES_FILE" ]; then
    nl -ba "$RULES_FILE"
  else
    echo "无记录文件。"
  fi

  echo -e "\n\e[36m=== 系统实际生效的 NAT 规则 (PREROUTING) ===\e[0m"
  iptables -t nat -L PREROUTING -n -v --line-numbers | grep "DNAT"
  
  echo -e "\n\e[36m=== 系统实际生效的 NAT 规则 (POSTROUTING) ===\e[0m"
  iptables -t nat -L POSTROUTING -n -v --line-numbers | grep "SNAT"

  echo ""
  read -p "按回车键返回菜单..."
}

# 开启 BBR (实现功能)
enable_bbr() {
  echo -e "\e[34m正在检查并开启 BBR...\e[0m"
  
  # 检查内核版本
  kernel_version=$(uname -r | cut -d- -f1)
  major_version=$(echo $kernel_version | cut -d. -f1)
  minor_version=$(echo $kernel_version | cut -d. -f2)

  if [ "$major_version" -lt 4 ] || ([ "$major_version" -eq 4 ] && [ "$minor_version" -lt 9 ]); then
    echo -e "\e[31m错误：BBR 需要 Linux Kernel 4.9 或更高版本。当前版本: $kernel_version\e[0m"
    echo "请先升级内核。"
    return
  fi

  # 写入配置
  sed -i '/net.core.default_qdisc/d' /etc/sysctl.conf
  sed -i '/net.ipv4.tcp_congestion_control/d' /etc/sysctl.conf
  
  echo "net.core.default_qdisc = fq" >> /etc/sysctl.conf
  echo "net.ipv4.tcp_congestion_control = bbr" >> /etc/sysctl.conf
  
  sysctl -p >/dev/null 2>&1
  
  # 验证
  if sysctl net.ipv4.tcp_congestion_control | grep -q "bbr"; then
    echo -e "\e[32mBBR 已成功开启！\e[0m"
  else
    echo -e "\e[31mBBR 开启失败，请检查系统环境。\e[0m"
  fi
}

# 主循环
while true; do
  show_menu
  read -p "请选择一个选项 (0-6): " choice
  echo ""
  case $choice in
    1) install_update_tools ;;
    2) add_forward_rule ;;
    3) clear_all_rules ;;
    4) delete_specific_rule ;;
    5) view_current_rules ;;
    6) enable_bbr ;;
    0) echo -e "\e[32m退出程序。\e[0m"; exit 0 ;;
    *) echo -e "\e[31m无效的选项，请输入 0-6。\e[0m" ;;
  esac
done
