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

  # 記錄 UDP 是否已經全局開啟
  local udp_opened_file="/var/tmp/udp_opened"
  udp_opened=false
  if [[ -f "$udp_opened_file" ]]; then
    udp_opened=true
  fi

  # 驗證輸入是否為有效的端口範圍
  if [[ $start_port -gt 0 && $start_port -le 65535 && $end_port -gt 0 && $end_port -le 65535 && $start_port -le $end_port ]]; then
    # 添加新的iptables規則
    echo "正在配置中轉規則，目標IP: $target_ip, 端口範圍: $start_port-$end_port"

    # 允許所有來自外部的 TCP 流量的轉發
    iptables -I FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT

    # 如果是第一次設置中轉規則，開啟全局 UDP 端口 1500-65535 的轉發
    if [ "$udp_opened" = false ]; then
      echo "正在配置 UDP 全局轉發，範圍: 1500-65535"
      iptables -I FORWARD -p udp --dport 1500:65535 -j ACCEPT
      touch "$udp_opened_file"
    fi

    # 允許已建立和相關的連接，確保返回流量能正確通過
    iptables -A FORWARD -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT

    # DNAT 將進入的連接轉發到目標IP
    iptables -t nat -A PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip"
    iptables -t nat -A PREROUTING -p udp -j DNAT --to-destination "$target_ip"

    # SNAT 修改源地址為本地內網地址，確保回覆能正確返回
    iptables -t nat -A POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip"
    iptables -t nat -A POSTROUTING -d "$target_ip" -p udp -j SNAT --to-source "$local_ip"

    # 將規則記錄到文件中以便後續管理
    echo "$start_port-$end_port" >> /var/tmp/port_rules

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

  # 清除記錄 UDP 全局開啟的標誌
  rm -f /var/tmp/udp_opened
  rm -f /var/tmp/port_rules

  echo "所有防火牆規則已清除。"
}

# 清除指定的轉發端口的函數
clear_specific_rule() {
  if [[ ! -f /var/tmp/port_rules ]]; then
    echo "目前沒有任何已設定的轉發規則。"
    return
  fi

  echo "當前的轉發規則:"
  cat -n /var/tmp/port_rules

  read -p "請選擇要清除的規則編號: " rule_number
  selected_rule=$(sed -n "${rule_number}p" /var/tmp/port_rules)

  if [[ -n "$selected_rule" ]]; then
    start_port=$(echo "$selected_rule" | cut -d'-' -f1)
    end_port=$(echo "$selected_rule" | cut -d'-' -f2)
    echo "正在清除 TCP 轉發規則，端口範圍: $start_port-$end_port"

    # 清除 FORWARD 中的 TCP 規則
    while iptables -C FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT 2>/dev/null; do
      iptables -D FORWARD -p tcp --dport "$start_port":"$end_port" -j ACCEPT
    done
    
    # 清除 PREROUTING 和 POSTROUTING 中的 TCP 規則
    while iptables -t nat -C PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination 2>/dev/null; do
      iptables -t nat -D PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT
    done
    while iptables -t nat -C POSTROUTING -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source 2>/dev/null; do
      iptables -t nat -D POSTROUTING -p tcp --dport "$start_port":"$end_port" -j SNAT
    done

    # 從文件中移除該規則
    sed -i "${rule_number}d" /var/tmp/port_rules

    # 保存變更以確保重啟後生效
    iptables-save > /etc/iptables/rules.v4
    ip6tables-save > /etc/iptables/rules.v6

    echo "TCP 轉發規則已清除。"
  else
    echo "無效的規則編號，請重試。"
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
