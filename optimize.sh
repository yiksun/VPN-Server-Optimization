#!/bin/bash

# 检查root权限
if [ "$(id -u)" != "0" ]; then
    echo "需要root权限运行此脚本"
    exit 1
fi

# 备份配置
backup_configs() {
    echo "创建配置备份..."
    cp /etc/sysctl.conf /etc/sysctl.conf.backup.$(date +%Y%m%d)
    cp /etc/security/limits.conf /etc/security/limits.conf.backup.$(date +%Y%m%d)
}

# 优化内核参数
optimize_kernel() {
    cat > /etc/sysctl.conf << EOF
# 基础网络参数优化
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_retries2 = 8
net.ipv4.tcp_fin_timeout = 15
net.ipv4.ip_forward = 1

# TCP拥塞控制和缓冲区优化
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 87380 67108864
net.ipv4.tcp_mem = 786432 2097152 67108864
net.ipv4.tcp_window_scaling = 1

# 连接优化
net.ipv4.tcp_max_syn_backlog = 32768
net.core.somaxconn = 32768
net.core.netdev_max_backlog = 32768
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_max_orphans = 32768
net.ipv4.tcp_orphan_retries = 3
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_timestamps = 0
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2

# TIME_WAIT优化
net.ipv4.tcp_tw_reuse = 1

# 端口范围优化
net.ipv4.ip_local_port_range = 1024 65535

# TCP keepalive优化
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# BBR相关
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 提高UDP性能
net.core.rmem_default = 8388608
net.core.wmem_default = 8388608
EOF

    # 应用新的sysctl参数
    sysctl -p

    # 优化系统限制
    cat > /etc/security/limits.conf << EOF
*               soft    nofile          1000000
*               hard    nofile          1000000
*               soft    nproc           1000000
*               hard    nproc           1000000
EOF

    # 优化系统文件句柄
    echo "fs.file-max = 1000000" >> /etc/sysctl.conf
    echo "fs.inotify.max_user_instances = 8192" >> /etc/sysctl.conf
    sysctl -p
}

# 安装并配置BBR
setup_bbr() {
    echo "检查并启用BBR..."
    if ! lsmod | grep -q bbr; then
        modprobe tcp_bbr
        echo "tcp_bbr" >> /etc/modules-load.d/modules.conf
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    fi
}

# 优化网络接口
optimize_network_interface() {
    # 获取主网卡名称
    MAIN_INTERFACE=$(ip route get 8.8.8.8 | awk '{print $5; exit}')
    
    if [ ! -z "$MAIN_INTERFACE" ]; then
        echo "优化网络接口: $MAIN_INTERFACE"
        # 设置网卡队列长度
        ip link set $MAIN_INTERFACE txqueuelen 10000
        # 开启网卡多队列（如果支持）
        QUEUES=$(ethtool -l $MAIN_INTERFACE 2>/dev/null | grep -i "combined" | head -n1 | awk '{print $2}')
        if [ ! -z "$QUEUES" ] && [ $QUEUES -gt 1 ]; then
            ethtool -L $MAIN_INTERFACE combined $QUEUES
        fi
    fi
}

# 优化DNS
optimize_dns() {
    # 使用知名DNS服务器
    cat > /etc/resolv.conf << EOF
nameserver 8.8.8.8
nameserver 1.1.1.1
EOF
    
    # 防止其他程序修改DNS设置
    chattr +i /etc/resolv.conf
}

# 清理系统缓存
clear_cache() {
    echo "清理系统缓存..."
    sync; echo 3 > /proc/sys/vm/drop_caches
    sync; echo 2 > /proc/sys/vm/drop_caches
    sync; echo 1 > /proc/sys/vm/drop_caches
}

# 主函数
main() {
    echo "开始优化代理服务器性能..."
    
    # 创建备份
    backup_configs
    
    # 执行优化步骤
    optimize_kernel
    setup_bbr
    optimize_network_interface
    optimize_dns
    clear_cache
    
    echo "优化完成！"
    
    # 询问是否重启
    read -p "需要重启服务器才能使所有优化生效，是否现在重启？[Y/n] " yn
    [ -z "${yn}" ] && yn="y"
    if [[ $yn == [Yy] ]]; then
        echo "服务器重启中..."
        reboot
    else
        echo "请记得稍后手动重启服务器以使所有优化生效"
    fi
}

# 运行主函数
main
