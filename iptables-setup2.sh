#!/bin/bash

# 设置基本的防火墙配置和 IP 转发
function setup_firewall {
    echo "更新系统中..."
    yum update -y

    echo "禁用 firewalld 并启用 iptables 服务..."
    systemctl stop firewalld
    systemctl disable firewalld
    yum install iptables-services -y
    systemctl enable iptables
    systemctl start iptables

    echo "配置基本的防火墙规则和 IP 转发..."
    echo "net.ipv4.ip_forward = 1" | tee -a /etc/sysctl.conf
    sysctl -p

    # 添加转发流量规则，仅需运行一次
    iptables -I FORWARD -i eth0 -j ACCEPT

    # 保存当前 iptables 配置并重启 iptables 服务
    service iptables save
    systemctl restart iptables

    echo "防火墙设置和 IP 转发配置已完成！"
}

# 配置端口转发
function configure_nat {
    read -p "请输入需要中转的外部 IP: " target_ip
    read -p "请输入TCP/UDP起始端口: " start_port
    read -p "请输入TCP/UDP结束端口: " end_port

    echo "获取内网 IP 地址..."
    internal_ip=$(ip -4 addr show eth0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
    echo "检测到的内网 IP 地址: $internal_ip"

    echo "设置 iptables 转发规则..."
    # 配置 DNAT 规则（入站流量转发）
    iptables -t nat -A PREROUTING -p tcp --dport $start_port:$end_port -j DNAT --to-destination $target_ip
    iptables -t nat -A PREROUTING -p udp --dport $start_port:$end_port -j DNAT --to-destination $target_ip

    # 配置 SNAT 规则（出站流量源地址转换）
    iptables -t nat -A POSTROUTING -d $target_ip -p tcp -m tcp --dport $start_port:$end_port -j SNAT --to-source $internal_ip
    iptables -t nat -A POSTROUTING -d $target_ip -p udp -m udp --dport $start_port:$end_port -j SNAT --to-source $internal_ip

    echo "转发设置已完成!"
}

# 清除指定的转发规则
function clear_specific_nat {
    echo "当前 NAT 规则："
    iptables -t nat -L PREROUTING --line-numbers
    read -p "请输入要删除的规则行号: " line_number
    if [[ -n $line_number ]]; then
        iptables -t nat -D PREROUTING $line_number
        echo "规则已删除"
    fi
}

# 清除所有转发规则
function clear_all_nat {
    echo "清除所有 NAT 转发规则..."
    iptables -t nat -F

    # 重新添加转发流量规则
    iptables -I FORWARD -i eth0 -j ACCEPT

    echo "所有转发规则已清除并重新设置基本转发规则!"
}

# 主菜单
function display_menu {
    clear
    echo "脚本由 BYY 设计-v001"
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
