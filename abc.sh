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
add_forward_rule() {
  read -p "請輸入需要被中轉的目標IP地址: " target_ip
  read -p "請輸入起始轉發端口: " start_port
  read -p "請輸入結尾轉發端口: " end_port

  # 自動獲取內網地址
  local_ip=$(detect_internal_ip)

  # 驗證輸入是否為有效的端口範圍
  if [[ $start_port -gt 0 && $start_port -le 65535 && $end_port -gt 0 && $end_port -le 65535 && $start_port -le $end_port ]]; then
    # 添加新的iptables規則
    echo "正在配置中轉規則，目標IP: $target_ip, 端口範圍: $start_port-$end_port"

    # 允許所有來自外部的 TCP 和 UDP 流量的轉發
    iptables -I FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT
    iptables -I FORWARD -p udp -j ACCEPT  # 允許所有的 UDP 流量進行轉發

    # 允許已建立和相關的連接，確保返回流量能正確通過
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # DNAT 將進入的連接轉發到目標IP
    iptables -t nat -A PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip"
    iptables -t nat -A PREROUTING -p udp -j DNAT --to-destination "$target_ip"  # 允許所有的 UDP 轉發到目標IP

    # SNAT 修改源地址為本地內網地址，確保回覆能正確返回
    iptables -t nat -A POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip"
    iptables -t nat -A POSTROUTING -d "$target_ip" -p udp -j SNAT --to-source "$local_ip"  # 對所有的 UDP 轉發進行源地址修改

    echo "中轉規則配置完成。"
  else
    echo "無效的端口範圍，請確保輸入的端口在 1 到 65535 之間，且起始端口小於或等於結束端口。"
  fi
}

# 清除所有設置的函數
clear_all_rules() {
  echo "正在清除所有防火牆規則..."
  iptables -t nat -F
  iptables -F FORWARD
  echo "所有防火牆規則已清除。"
}

# 清除指定端口設置的函數
clear_specific_rule() {
  read -p "請輸入需要清除的起始端口: " start_port
  read -p "請輸入需要清除的結尾端口: " end_port

  # 驗證輸入是否為有效的端口範圍
  if [[ $start_port -gt 0 && $start_port -le 65535 && $end_port -gt 0 && $end_port -le 65535 && $start_port -le $end_port ]]; then
    echo "正在清除端口範圍: $start_port-$end_port 的防火牆規則..."

    # 清除指定端口範圍的 FORWARD 規則
    iptables -D FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT
    iptables -D FORWARD -p udp --dport "$start_port":"$end_port" -j ACCEPT

    # 清除指定端口範圍的 PREROUTING 和 POSTROUTING 規則
    iptables -t nat -D PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT
    iptables -t nat -D PREROUTING -p udp --dport "$start_port":"$end_port" -j DNAT
    iptables -t nat -D POSTROUTING -p tcp --dport "$start_port":"$end_port" -j SNAT
    iptables -t nat -D POSTROUTING -p udp --dport "$start_port":"$end_port" -j SNAT

    echo "指定的防火牆規則已清除。"
  else
    echo "無效的端口範圍，請確保輸入的端口在 1 到 65535 之間，且起始端口小於或等於結束端口。"
  fi
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
      clear_specific_rule
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
