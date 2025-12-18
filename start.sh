#!/bin/bash

# ==========================================
# 🟢 配置区 (已自动填充)
# ==========================================

# 1. 脚本的自我更新/下载地址
MY_SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/main/start.sh"

# 2. 哪吒探针指令预设
PRESET_NEZHA_COMMAND=""

# 3. 自定义环境变量
export hypt=""

# ==========================================
# 🛠️ 常量定义
# ==========================================
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
        
        # 🟢 [修改点 1] 静默安装：添加了 >/dev/null 2>&1
        # 这样就不会刷屏 fetch ... Installing ... 这些信息了
        apk update >/dev/null 2>&1
        apk add --no-cache bash curl wget ca-certificates tar unzip gcompat libstdc++ procps >/dev/null 2>&1
        
        # 建立软连接
        if [ ! -f /bin/bash ]; then ln -s /usr/bin/bash /bin/bash; fi
        echo ">>> [系统] Alpine 依赖修复完成。"
    fi

    # 针对 Debian/Ubuntu 的基础依赖检查
    if [ -f /etc/debian_version ]; then
        if ! command -v curl &> /dev/null; then
            apt-get update >/dev/null 2>&1 && apt-get install -y curl wget unzip >/dev/null 2>&1
        fi
    fi
}

# ==========================================
# 📦 1. 自我安装
# ==========================================
install_self() {
    if [ ! -f "$INSTALL_PATH" ]; then
        echo ">>> [安装] 正在将脚本下载到本地: $INSTALL_PATH"
        curl -L -o "$INSTALL_PATH" "$MY_SELF_URL"
        
        if [ $? -ne 0 ]; then
            echo ">>> [警告] ❌ 下载失败！请检查链接。"
        else
            chmod +x "$INSTALL_PATH"
            echo ">>> [安装] ✅ 脚本已落地并授权。"
        fi
    else
        chmod +x "$INSTALL_PATH"
    fi
}

# ==========================================
# 🔌 2. 开机自启
# ==========================================
add_self_to_startup() {
    [ ! -f "$INSTALL_PATH" ] && return
    
    # 注意：这里的自启命令依然保留 >/dev/null，防止重启时系统日志爆炸
    # 但我们手动运行时，是在前台运行的，能看到输出
    CRON_CMD="@reboot cd /root && bash $INSTALL_PATH >/dev/null 2>&1 &"
    
    if crontab -l 2>/dev/null | grep -Fq "$INSTALL_PATH"; then
        echo ">>> [自启] ✅ 开机自启已配置。"
    else
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        echo ">>> [自启] ✅ 已成功添加开机自启。"
    fi
}

# ==========================================
# 🛠️ 辅助函数
# ==========================================
get_param() {
    local input_str="$1"
    local key="$2"
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
    
    if [[ -z "$server" || -z "$secret" ]]; then
        if [ -f "$NEZHA_CONFIG" ]; then
            echo ">>> [探针] 使用现有配置启动。"
        else
            return 
        fi
    fi

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

    if [[ -n "$server" && -n "$secret" ]]; then
        cat > "$NEZHA_CONFIG" <<EOF
server: ${server}
client_secret: ${secret}
tls: ${tls:-false}
EOF
        [ -n "$uuid" ] && echo "uuid: $uuid" >> "$NEZHA_CONFIG"
    fi

    # 🟢 [修改点 2] 去除 >/dev/null，直接后台运行
    # 输出将直接打印到当前终端
    ./"$BIN_FILE" -c "$NEZHA_CONFIG" &
}

# ==========================================
# 🚀 4. 主业务 (Argosbx)
# ==========================================
start_main_script() {
    cd /root
    echo -e "\n>>> [主程序] 启动 Argosbx..."
    
    if [ ! -f "$ARGOSBX_SCRIPT" ]; then
        curl -L -o "$ARGOSBX_SCRIPT" "$ARGOSBX_URL"
    fi
    chmod +x "$ARGOSBX_SCRIPT"
    
    # 🟢 [修改点 3] 完全去除 nohup 和重定向
    # 这样 Argosbx 的所有彩色输出、报错、进度条都会直接显示在你的屏幕上
    bash "$ARGOSBX_SCRIPT" &
    
    echo ">>> [启动] 业务脚本已在后台启动 (输出已释放)。"
}

# ==========================================
# 🏁 5. 入口函数
# ==========================================
main() {
    clear
    echo "===================================================="
    echo "      全自动启动脚本 (输出增强版)"
    echo "===================================================="

    check_dependencies
    install_self
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

    start_nezha "$FINAL_CONFIG"
    start_main_script

    echo -e "\n>>> [完成] 脚本已进入后台保活模式。"
    # 即使这里有 tail -f，上面的后台进程 (&) 依然可以往屏幕上打印信息
    tail -f /dev/null
}

main
