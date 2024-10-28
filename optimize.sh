#!/bin/bash

# 备份现有配置
backup_configs() {
    echo "Creating backups..."
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d)
    cp /etc/security/limits.conf /etc/security/limits.conf.backup.$(date +%Y%m%d)
}

# 恢复配置
restore_configs() {
    local backup_date="$1"
    if [ -f "/etc/sysctl.conf.backup.${backup_date}" ]; then
        cp "/etc/sysctl.conf.backup.${backup_date}" /etc/sysctl.conf
        cp "/etc/security/limits.conf.backup.${backup_date}" /etc/security/limits.conf
        sysctl -p
        echo "Configuration restored from ${backup_date} backup"
    else
        echo "Backup from ${backup_date} not found"
    fi
}

# 应用VPN优化配置
apply_vpn_optimizations() {
    # 清理旧配置
    sed -i '/net.ipv4/d' /etc/sysctl.conf
    sed -i '/net.core/d' /etc/sysctl.conf
    sed -i '/fs.file-max/d' /etc/sysctl.conf

    # 写入新配置
    cat >> /etc/sysctl.conf << EOF
# VPN Performance Optimizations
net.ipv4.ip_forward = 1
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# Connection and Queue Optimizations
net.core.somaxconn = 16384
net.core.netdev_max_backlog = 16384
net.ipv4.tcp_max_syn_backlog = 8192
net.ipv4.ip_local_port_range = 1024 65000

# Security Measures
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# Memory Optimizations
net.ipv4.tcp_mem = 786432 1048576 1572864
net.ipv4.tcp_rmem = 4096 87380 16777216
net.ipv4.tcp_wmem = 4096 87380 16777216
EOF

    # 更新文件限制
    cat > /etc/security/limits.conf << EOF
*               soft    nofile          65535
*               hard    nofile          65535
root            soft    nofile          65535
root            hard    nofile          65535
EOF

    # 应用配置
    sysctl -p

    # 检查BBR是否可用并启用
    if modprobe tcp_bbr 2>/dev/null; then
        echo "tcp_bbr" > /etc/modules-load.d/bbr.conf
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    fi
}

# 主函数
main() {
    echo "VPN Server Optimization Script"
    echo "1. Apply optimizations (with backup)"
    echo "2. Restore from backup"
    echo "3. Exit"
    read -p "Choose an option (1-3): " choice

    case $choice in
        1)
            backup_configs
            apply_vpn_optimizations
            echo "Optimizations applied successfully"
            echo "Backup created with date: $(date +%Y%m%d)"
            ;;
        2)
            read -p "Enter backup date (YYYYMMDD): " backup_date
            restore_configs "$backup_date"
            ;;
        3)
            exit 0
            ;;
        *)
            echo "Invalid option"
            exit 1
            ;;
    esac
}

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root"
    exit 1
fi

main
