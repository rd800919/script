#!/bin/bash

# 设置基本的防火墙配置和 IP 转发
function setup_firewall {
    echo "更新系统中..."
    apt update -y && apt upgrade -y -o 'APT::Get::Assume-Yes=true'

    echo "确保 iptables 服务已安装并允许 SSH..."
    DEBIAN_FRONTEND=noninteractive apt install -y iptables iptables-persistent

    # 启用并启动 iptables-persistent 以持久化规则
    systemctl enable netfilter-persistent
    systemctl start netfilter-persistent

    # 添加允许 SSH 连接的规则，以防止 SSH 断开
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT

    echo "配置基本的防火墙规则和 IP 转发..."
    echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
    sysctl -p

    # 设置默认 FORWARD 策略为 DROP 确保未指定的端口不转发
    iptables -P FORWARD DROP

    # 清除 NAT 表中任何残留规则
    iptables -t nat -F

    # 保存当前 iptables 配置
    netfilter-persistent save
    systemctl restart netfilter-persistent

    echo "防火墙设置和 IP 转发配置已完成！"
}

# 自动检测内网 IP 和网卡名称
function detect_internal_ip {
    local interface=$(ip -4 route ls | grep default | awk '{print $5}' | head -1)
    
    if [[ -z "$interface" ]]; then
        echo "未能自动检测到网卡。请手动输入内网 IP。"
        return 1
    fi

    local ip_addr=$(ip -4 addr show "$interface" | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    
    if [[ -z "$ip_addr" ]]; then
        echo "未能自动检测到内网 IP，请手动输入。"
        return 1
    fi

    echo "$ip_addr"
    return 0
}

# 配置端口转发
function configure_nat {
    read -p "请输入需要中转的外部 IP: " target_ip
    read -p "请输入TCP/UDP起始端口: " start_port
    read -p "请输入TCP/UDP结束端口: " end_port

    # 自动检测或手动输入内网 IP 地址
    read -p "请输入内网 IP 地址（直接按 Enter 自动检测）: " internal_ip
    if [ -z "$internal_ip" ]; then
        internal_ip=$(detect_internal_ip)
        if [ $? -ne 0 ] || [ -z "$internal_ip" ]; then
            read -p "自动检测失败，请手动输入有效的内网 IP: " internal_ip
            if [ -z "$internal_ip" ]; then
                echo "未提供有效的内网 IP，操作中止。"
                return 1
            fi
        else
            echo "检测到的内网 IP 地址: $internal_ip"
        fi
    fi

    echo "设置 iptables 转发规则..."
    # 配置 DNAT 规则（入站流量转发），带起始和结束端口范围
    iptables -t nat -A PREROUTING -p tcp --dport $start_port:$end_port -j DNAT --to-destination $target_ip
    iptables -t nat -A PREROUTING -p udp --dport $start_port:$end_port -j DNAT --to-destination $target_ip

    # 配置 SNAT 规则（出站流量源地址转换）
    iptables -t nat -A POSTROUTING -d $target_ip -p tcp --dport $start_port:$end_port -j SNAT --to-source $internal_ip
    iptables -t nat -A POSTROUTING -d $target_ip -p udp --dport $start_port:$end_port -j SNAT --to-source $internal_ip

    # 精确 FORWARD 规则以仅允许特定端口范围
    iptables -A FORWARD -p tcp --dport $start_port:$end_port -j ACCEPT
    iptables -A FORWARD -p udp --dport $start_port:$end_port -j ACCEPT

    # 保存规则
    netfilter-persistent save
    echo "转发设置已完成!"
}

# 清除指定的转发规则
function clear_specific_nat {
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
    # 强制保存并重启 netfilter-persistent
    netfilter-persistent save
    systemctl restart netfilter-persistent
}

# 清除所有转发规则
function clear_all_nat {
    echo "清除所有 NAT 转发规则..."
    iptables -t nat -F
    iptables -F FORWARD

    # 重新添加 SSH 规则
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT
    iptables -P FORWARD DROP  # 确保默认的 FORWARD 策略为拒绝

    # 强制保存并重启 netfilter-persistent
    netfilter-persistent save
    systemctl restart netfilter-persistent
    echo "所有转发规则已清除并重新设置基本转发规则!"
}

# 主菜单
function display_menu {
    clear
    echo "脚本由 BYY 设计-v005"
    echo "WeChat: x7077796"
    echo "============================"
    echo "选择要执行的操作："
    echo "1. 执行事前准备和安装"
    echo "2. 设置转发"
    echo "3. 清除指定转发"
    echo "4. 清除所有转发"
    echo "5. 退出"
    echo "============================"
}

while true; do
    display_menu
    read -p "请输入选项 (1, 2, 3, 4 或 5): " choice
    case $choice in
        1)
            setup_firewall
            read -p "按任意键继续..." key
            ;;
        2)
            configure_nat
            read -p "按任意键继续..." key
            ;;
        3)
            clear_specific_nat
            read -p "按任意键继续..." key
            ;;
        4)
            clear_all_nat
            read -p "按任意键继续..." key
            ;;
        5)
            echo "退出脚本..."
            exit 0
            ;;
        *)
            echo "无效的选项。请输入 1, 2, 3, 4 或 5。"
            read -p "按任意键继续..." key
            ;;
    esac
done
