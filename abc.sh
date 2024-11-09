#!/bin/bash

# 定義顯示選單的函數
show_menu() {
  echo "=============================="
  echo " 中轉服務器設置選單 "
  echo "=============================="
  echo "1. 安裝或更新必要工具"
  echo "2. 設置中轉規則"
  echo "3. 清除所有設置"
  echo "4. 清除指定的轉發端口"
  echo "5. 退出"
  echo "=============================="
}

# 安裝或更新必要工具的函數
install_update_tools() {
  echo "正在安裝或更新必要的工具..."
  # 更新包管理器並安裝iptables和net-tools（如果尚未安裝）
  apt update -y && apt upgrade -y -o 'APT::Get::Assume-Yes=true'
  apt-get install -y iptables net-tools
  
  # 禁用 ufw 防火牆（如果存在且激活）
  if command -v ufw >/dev/null 2>&1; then
    ufw_status=$(ufw status | grep -o 'active')
    if [[ "$ufw_status" == "active" ]]; then
      echo "發現 ufw 防火牆正在運行，正在禁用..."
      ufw disable
      echo "ufw 已禁用。"
    fi
  fi
  
  # 配置基本的防火牆規則和 IP 轉發
  echo "配置基本的防火牆規則和 IP 轉發..."
  echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
  sysctl -p
  
  echo "工具安裝或更新完成。"
}

# 自動檢測內網 IP 和網卡名稱的函數
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

# 添加中轉規則的函數

    # 保存规则
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6
  else
    echo "無效的端口範圍，請確保輸入的端口在 1 到 65535 之間，且起始端口小於或等於結束端口。"
  fi
}

# 清除所有設置的函數

  # 保存规则
  iptables-save > /etc/iptables/rules.v4
  ip6tables-save > /etc/iptables/rules.v6
}

# 清除指定端口設置的函數
clear_specific_nat() {
  echo "当前 NAT 规则 (PREROUTING、POSTROUTING 和 FORWARD)："
  iptables -t nat -L PREROUTING --line-numbers
  iptables -t nat -L POSTROUTING --line-numbers
  iptables -L FORWARD --line-numbers

  read -p "请输入要删除的规则行号: " line_number
  if [[ -n $line_number ]]; then
    # 删除 PREROUTING 和 POSTROUTING 中的指定规则
    iptables -t nat -D PREROUTING $line_number 2>/dev/null && echo "PREROUTING 规则已删除"
    iptables -t nat -D POSTROUTING $line_number 2>/dev/null && echo "POSTROUTING 规则已删除"

    # 删除 FORWARD 中的指定规则
    iptables -D FORWARD $line_number 2>/dev/null && echo "FORWARD 规则已删除"
  else
    echo "未输入有效的规则行号。返回主菜单。"
  fi
  # 保存规则
  iptables-save > /etc/iptables/rules.v4
  ip6tables-save > /etc/iptables/rules.v6
}

# 主循環
while true; do
  show_menu
  read -p "請選擇一個選項 (1-5): " choice
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
      clear_specific_nat
      ;;
    5)
      echo "退出程序。"
      exit 0
      ;;
    *)
      echo "無效的選項，請輸入 1, 2, 3, 4 或 5。"
      ;;
  esac
done
