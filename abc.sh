#!/bin/bash

# 定義顯示選單的函數
show_menu() {
  echo "=============================="
  echo " 中轉服務器設置選單-2 "
  echo "=============================="
  echo "1. 安裝或更新必要工具"
  echo "2. 設置中轉規則"
  echo "3. 退出"
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
  read -p "請輸入結束轉發端口: " end_port

  # 自動獲取內網地址
  local_ip=$(detect_internal_ip)

  # 驗證輸入是否為有效的端口範圍
  if [[ $start_port -gt 0 && $start_port -le 65535 && $end_port -gt 0 && $end_port -le 65535 && $start_port -le $end_port ]]; then
    # 清除舊的規則，確保未設置的端口無法通行
    iptables -t nat -F
    iptables -F FORWARD

    # 添加新的iptables規則
    echo "正在配置中轉規則，目標IP: $target_ip, 端口範圍: $start_port-$end_port"

    # 允許轉發指定端口範圍的TCP流量
    iptables -A FORWARD -p tcp -d "$target_ip" --dport "$start_port":"$end_port" -j ACCEPT
    iptables -A FORWARD -p udp -d "$target_ip" --dport "$start_port":"$end_port" -j ACCEPT

    # DNAT 將進入的連接轉發到目標IP
    iptables -t nat -A PREROUTING -p tcp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip"
    iptables -t nat -A PREROUTING -p udp --dport "$start_port":"$end_port" -j DNAT --to-destination "$target_ip"

    # SNAT 修改源地址為本地內網地址，確保回覆能正確返回
    iptables -t nat -A POSTROUTING -d "$target_ip" -p tcp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip"
    iptables -t nat -A POSTROUTING -d "$target_ip" -p udp --dport "$start_port":"$end_port" -j SNAT --to-source "$local_ip"

    echo "中轉規則配置完成。"
  else
    echo "無效的端口範圍，請確保輸入的端口在 1 到 65535 之間，且起始端口小於或等於結束端口。"
  fi
}

# 主循環
while true; do
  show_menu
  read -p "請選擇一個選項 (1-3): " choice
  case $choice in
    1)
      install_update_tools
      ;;
    2)
      add_forward_rule
      ;;
    3)
      echo "退出程序。"
      exit 0
      ;;
    *)
      echo "無效的選項，請輸入 1, 2 或 3。"
      ;;
  esac
done
