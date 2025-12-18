#!/bin/bash

# ==========================================
# 🟢 配置区 (已自动填充)
# ==========================================

# 1. 脚本的自我更新/下载地址
# [修正] 已去除 ref/heads 路径，使用标准的 raw 链接格式，确保 curl 能下载
MY_SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/main/start.sh"

# 2. 哪吒探针指令预设 (如果不想每次手动输，可以在这里填入 NZ_SERVER=xxx...)
PRESET_NEZHA_COMMAND=""

# 3. 自定义环境变量 (可选)
export hypt=""

# ==========================================
# 🛠️ 常量定义
# ==========================================
# [修正] 文件名统一修改为 start.sh
INSTALL_PATH="/root/start.sh"
NEZHA_CONFIG="/root/nezha.yml"
ARGOSBX_SCRIPT="/root/argosbx.sh"
ARGOSBX_URL="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"
TIMEOUT_SECONDS=20

# ==========================================
# 🚑 0. 环境依赖修复 (Alpine 救砖逻辑)
# ==========================================
check_dependencies() {
    echo ">>> [环境] 正在检查系统依赖..."
    
    # 针对 Alpine Linux 的核心修复逻辑
    if [ -f /etc/alpine-release ]; then
        echo ">>> [系统] 检测到 Alpine Linux，正在安装兼容性依赖 (gcompat)..."
        # 安装 gcompat 和 libstdc++ 以解决 "Terminated" 和进程崩溃问题
        apk update
        apk add --no-cache bash curl wget ca-certificates tar unzip gcompat libstdc++ procps
        
        # 建立软连接，防止脚本找不到 /bin/bash
        if [ ! -f /bin/bash ]; then ln -s /usr/bin/bash /bin/bash; fi
        echo ">>> [系统] Alpine 依赖修复完成。"
    fi

    # 针对 Debian/Ubuntu 的基础依赖检查
    if [ -f /etc/debian_version ]; then
        if ! command -v curl &> /dev/null; then
            apt-get update && apt-get install -y curl wget unzip
        fi
    fi
}

# ==========================================
# 📦 1. 自我安装 (实现无权限启动 -> 有权限自启)
# ==========================================
install_self() {
    # 如果本地没有这个文件，或者想强制更新，都会执行下载
    if [ ! -f "$INSTALL_PATH" ]; then
        echo ">>> [安装] 正在将脚本下载到本地: $INSTALL_PATH"
        
        # 使用 curl 下载自身
        curl -L -o "$INSTALL_PATH" "$MY_SELF_URL"
        
        if [ $? -ne 0 ]; then
            echo ">>> [警告] ❌ 下载失败！请检查 GitHub 仓库中是否存在 start.sh 文件，且链接正确。"
            echo "    目标链接: $MY_SELF_URL"
        else
            chmod +x "$INSTALL_PATH"
            echo ">>> [安装] ✅ 脚本已落地并授权。"
        fi
    else
        # 确保权限存在
        chmod +x "$INSTALL_PATH"
    fi
}

# ==========================================
# 🔌 2. 开机自启
# ==========================================
add_self_to_startup() {
    # 只有文件落地了，才能设置自启
    [ ! -f "$INSTALL_PATH" ] && return
    
    # 构造自启命令：重启后 -> 进目录 -> 后台运行脚本
    CRON_CMD="@reboot cd /root && bash $INSTALL_PATH >/dev/null 2>&1 &"
    
    # 检查是否已经添加过
    if crontab -l 2>/dev/null | grep -Fq "$INSTALL_PATH"; then
        echo ">>> [自启] ✅ 开机自启已配置。"
    else
        # 添加到 crontab
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        echo ">>> [自启] ✅ 已成功添加开机自启。"
    fi
}

# ==========================================
# 🛠️ 辅助函数: 参数提取
# ==========================================
get_param() {
    local input_str="$1"
    local key="$2"
    # 尝试提取 key=value 的值
    echo "$input_str" | grep -oP "$key=\K[\w\.:-]+" 2>/dev/null || \
    echo "$input_str" | sed -n "s/.*$key=\([^ ]*\).*/\1/p"
}

# ==========================================
# 🛡️ 3. 哪吒探针逻辑
# ==========================================
start_nezha() {
    local cmd_str="$1"
    local server=$(get_param "$cmd_str" "NZ_SERVER")
    local secret=$(get_param "$cmd_str" "NZ_CLIENT_SECRET")
    local tls=$(get_param "$cmd_str" "NZ_TLS")
    local uuid=$(get_param "$cmd_str" "NZ_UUID")

    cd /root
    
    # 如果没有传入新参数，尝试读取旧配置
    if [[ -z "$server" || -z "$secret" ]]; then
        if [ -f "$NEZHA_CONFIG" ]; then
            echo ">>> [探针] 使用现有配置启动。"
        else
            return # 无参数也无配置，直接跳过
        fi
    fi

    # 下载探针文件
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then NZ_ARCH="amd64"; elif [[ "$ARCH" == "aarch64" ]]; then NZ_ARCH="arm64"; else NZ_ARCH="amd64"; fi
    BIN_FILE="nezha-agent"
    
    if [ ! -f "$BIN_FILE" ]; then
        echo ">>> [探针] 下载 Agent ($NZ_ARCH)..."
        curl -L -o nezha.zip "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${NZ_ARCH}.zip"
        unzip -o nezha.zip >/dev/null 2>&1
        chmod +x "$BIN_FILE"
        rm -f nezha.zip
    fi

    # 生成配置文件
    if [[ -n "$server" && -n "$secret" ]]; then
        cat > "$NEZHA_CONFIG" <<EOF
server: ${server}
client_secret: ${secret}
tls: ${tls:-false}
EOF
        [ -n "$uuid" ] && echo "uuid: $uuid" >> "$NEZHA_CONFIG"
    fi

    # 启动探针 (使用 nohup 后台静默运行)
    nohup ./"$BIN_FILE" -c "$NEZHA_CONFIG" >/dev/null 2>&1 &
}

# ==========================================
# 🚀 4. 主业务 (Argosbx)
# ==========================================
start_main_script() {
    cd /root
    echo -e "\n>>> [主程序] 启动 Argosbx..."
    
    # 下载脚本
    if [ ! -f "$ARGOSBX_SCRIPT" ]; then
        curl -L -o "$ARGOSBX_SCRIPT" "$ARGOSBX_URL"
    fi
    chmod +x "$ARGOSBX_SCRIPT"
    
    # 启动脚本
    # 使用 nohup + 后台运行，并将日志输出到 argosbx.log，防止阻塞主流程
    nohup bash "$ARGOSBX_SCRIPT" >/root/argosbx.log 2>&1 &
    
    echo ">>> [启动] 业务脚本已在后台运行。"
    echo ">>> [日志] 你可以使用 'tail -f /root/argosbx.log' 查看运行情况。"
}

# ==========================================
# 🏁 5. 入口函数
# ==========================================
main() {
    clear
    echo "===================================================="
    echo "      全自动启动脚本 (Alpine 兼容修复版)"
    echo "===================================================="

    # 1. 优先修复系统依赖 (Alpine 救星)
    check_dependencies

    # 2. 将脚本安装到硬盘
    install_self

    # 3. 设置开机自启
    add_self_to_startup

    echo "----------------------------------------------------"
    echo "请选择操作 ($TIMEOUT_SECONDS 秒倒计时):"
    echo "1. [输入] 粘贴哪吒命令"
    echo "2. [回车] 使用预设/旧配置"
    echo "----------------------------------------------------"

    read -t $TIMEOUT_SECONDS -p "请输入 > " USER_INPUT
    
    FINAL_CONFIG=""
    if [ -n "$USER_INPUT" ]; then FINAL_CONFIG="$USER_INPUT"; 
    elif [ -n "$PRESET_NEZHA_COMMAND" ]; then FINAL_CONFIG="$PRESET_NEZHA_COMMAND"; fi

    # 启动各模块
    start_nezha "$FINAL_CONFIG"
    start_main_script

    echo -e "\n>>> [完成] 脚本已进入后台保活模式。"
    echo ">>> [保活] 正在运行 tail -f /dev/null 防止容器退出..."
    tail -f /dev/null
}

main
