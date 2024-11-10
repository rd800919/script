#!/bin/bash

# 定义显示菜单的函数
show_menu() {
  echo "=============================="
  echo " 中转服务器设置菜单2 "
  echo "=============================="
  echo "1. 安装或更新必要工具"
  echo "2. 设置中转规则"
  echo "3. 清除所有设置"
  echo "4. 删除指定端口的转发规则"
  echo "5. 查看当前中转规则"
  echo "6. 退出"
  echo "=============================="
  echo "脚本由 BYY 设计-v001"
  echo "WeChat: x7077796"
  echo "=============================="
}

# 安装或更新必要工具的函数
install_update_tools() {
  echo "正在安装或更新必要的工具..."
  # 更新包管理器并安装iptables和net-tools（如果尚未安装）
  apt update -y && apt upgrade -y -o 'APT::Get::Assume-Yes=true'
  apt-get install -y iptables net-tools
  
  # 禁用 ufw 防火墙（如果存在且激活）
  if command -v ufw >/dev/null 2>&1; then
    ufw_status=$(ufw status | grep -o 'active')
    if [[ "$ufw_status" == "active" ]]; then
      echo "发现 ufw 防火墙正在运行，正在禁用..."
      ufw disable
      echo "ufw 已禁用。"
    fi
  fi
  
  # 配置基本的防火墙规则和 IP 转发
  echo "配置基本的防火墙规则和 IP 转发..."
  echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
  sysctl -p
  
  echo "工具安装或更新完成。"
}

# 自动检测内网 IP 和网卡名称的函数
detect_internal_ip() {
  local interface=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
  
  if [[ -z "$interface" ]]; then
    echo "未能自动检测到网卡。"
    exit 1
  fi

  local ip_addr=$(ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
  
  if [[ -z "$ip_addr" ]]; then
    echo "未能自动检测到内网 IP。"
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
    echo "正在配置中转规则，目标IP: $target_ip, 端口范围: $start_port-$end_port"

    # 检查并添加新的 FORWARD 规则，确保没有重复
    if ! iptables -C FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT 2>/dev/null; then
      iptables -A FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT
    fi

    # 如果是第一次设置中转规则，且UDP规则尚未添加，开启全局 UDP 端口 1500-65535 的转发
    if [ "$udp_opened" = false ]; then
      if ! iptables -C FORWARD -p udp --dport 1500:65535 -j ACCEPT 2>/dev/null; then
        echo "正在配置 UDP 全局转发，范围: 1500-65535"
        iptables -A FORWARD -p udp --dport 1500:65535 -j ACCEPT
        touch "$udp_opened_file"
      fi
    fi

    # 允许已建立和相关的连接，确保返回流量能正确通过
    if ! iptables -C FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null; then
      iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
    fi

    # DNAT 将进入的连接转发到目标IP
    if ! iptables -t nat -C PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip" 2>/dev/null; then
      iptables -t nat -A PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip"
    fi

    if [ "$udp_opened" = false ]; then
      if ! iptables -t nat -C PREROUTING -p udp -j DNAT --to-destination "$target_ip" 2>/dev/null; then
        iptables -t nat -A PREROUTING -p udp -j DNAT --to-destination "$target_ip"
      fi
    fi

    # SNAT 修改源地址为本地内网地址，确保回复能正确返回
    if ! iptables -t nat -C POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip" 2>/dev/null; then
      iptables -t nat -A POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip"
    fi

    if [ "$udp_opened" = false ]; then
      if ! iptables -t nat -C POSTROUTING -d "$target_ip" -p udp -j SNAT --to-source "$local_ip" 2>/dev/null; then
        iptables -t nat -A POSTROUTING -d "$target_ip" -p udp -j SNAT --to-source "$local_ip"
      fi
    fi

    # 将规则记录到文件中以便后续管理
    echo "$start_port-$end_port $target_ip" >> /var/tmp/port_rules

    echo "中转规则配置完成。"
  else
    echo "无效的端口范围，请确保输入的端口在 1 到 65535 之间，且起始端口小于或等于结束端口。"
  fi
}

# 清除所有设置的函数
clear_all_rules() {
  read -p "确定要清除所有防火墙规则吗？(y/n): " confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo "操作已取消。"
    return
  fi

  echo "正在清除所有防火墙规则..."
  iptables -t nat -F
  iptables -F FORWARD

  # 清除记录 UDP 全局开启的标志
  rm -f /var/tmp/udp_opened
  rm -f /var/tmp/port_rules

  echo "所有防火墙规则已清除。"
}

# 清除指定的 PREROUTING 和 POSTROUTING 规则的函数
clear_prerouting_postrouting() {
  echo "当前的 PREROUTING 和 POSTROUTING 规则:"
  iptables -t nat -L PREROUTING --line-numbers
  iptables -t nat -L POSTROUTING --line-numbers

  read -p "请输入要清除的规则行号 (按Enter取消): " rule_num
  if [[ -z "$rule_num" ]]; then
    echo "操作已取消。"
    return
  elif [[ -n "$rule_num" ]]; then
    iptables -t nat -D PREROUTING $rule_num
    iptables -t nat -D POSTROUTING $rule_num
    echo "PREROUTING 和 POSTROUTING 规则已删除。"
  else
    echo "无效的规则行号，请重试。"
  fi

  # 保存变更以确保重启后生效
  iptables-save > /etc/iptables/rules.v4
  ip6tables-save > /etc/iptables/rules.v6
}

# 查看当前中转规则的函数
view_current_rules() {
  echo "当前的中转规则:"
  if [[ -f /var/tmp/port_rules ]]; then
    cat /var/tmp/port_rules
  else
    echo "没有已设置的中转规则。"
  fi
}

# 主循环
while true; do
  show_menu
  read -p "请选择一个选项 (1-6): " choice
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
      echo "退出程序。"
      exit 0
      ;;
    *)
      echo "无效的选项，请输入 1, 2, 3, 4, 5 或 6。"
      ;;
  esac
done
