#!/bin/bash

# ==========================================
# 🟢 配置区 (用户必须修改这里)
# ==========================================

# 1. 你的 GitHub Raw 链接 (脚本需要知道去哪里下载自己来做备份)
#    请务必修改为你的真实链接！例如: https://raw.githubusercontent.com/你的名字/仓库/main/boot.sh
MY_SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh"

# 2. 哪吒探针指令预设 (可选)
PRESET_NEZHA_COMMAND=""

# 3. 自定义环境变量 (可选)
export hypt=""

# ==========================================
# 🛠️ 常量定义
# ==========================================
INSTALL_PATH="/root/boot.sh"  # 脚本将把自己安装到这里
NEZHA_CONFIG="/root/nezha.yml"
ARGOSBX_SCRIPT="/root/argosbx.sh"
ARGOSBX_URL="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"
TIMEOUT_SECONDS=20

# ==========================================
# 📦 1. 自我安装与环境检查 (核心逻辑)
# ==========================================
install_self() {
    echo ">>> [安装] 正在检测本地环境..."

    # 只要检测到从网络启动，或者本地文件和网络版不一致，就重新下载覆盖
    # 这一步确保了文件实实在在地存在于硬盘上
    if [ ! -f "$INSTALL_PATH" ]; then
        echo ">>> [安装] 正在将脚本下载到本地: $INSTALL_PATH"
        curl -L -o "$INSTALL_PATH" "$MY_SELF_URL"
        
        if [ $? -ne 0 ]; then
            echo ">>> [错误] ❌ 无法下载脚本自身，请检查 MY_SELF_URL 是否填写正确！"
            # 如果下载失败，为了不报错退出，暂时继续运行内存里的逻辑，但自启会失效
        else
            echo ">>> [安装] ✅ 脚本已落地到硬盘。"
        fi
    fi

    # 🟢 关键：在这里代码内部给自己授权
    if [ -f "$INSTALL_PATH" ]; then
        chmod +x "$INSTALL_PATH"
        echo ">>> [权限] ✅ 已自动赋予执行权限 (chmod +x)。"
    fi
}

# ==========================================
# 🔌 2. 开机自启功能
# ==========================================
add_self_to_startup() {
    echo -e "\n>>> [自启] 正在配置开机自启..."

    # 确保我们要添加的是硬盘上的那个文件，而不是内存里的流
    if [ ! -f "$INSTALL_PATH" ]; then
        echo ">>> [警告] ⚠️ 找不到本地文件，无法设置自启。"
        return
    fi

    # 构建命令：重启时进入 /root 目录并运行脚本
    CRON_CMD="@reboot cd /root && bash $INSTALL_PATH >/dev/null 2>&1 &"

    # 检查是否已存在
    if crontab -l 2>/dev/null | grep -Fq "$INSTALL_PATH"; then
        echo ">>> [自启] ✅ 开机自启已存在，跳过。"
    else
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        if [ $? -eq 0 ]; then
            echo ">>> [自启] ✅ 成功设置开机自动启动！"
        else
            echo ">>> [自启] ❌ 设置失败。"
        fi
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

    # 必须切换到 /root 目录，保证文件下载在同一个地方
    cd /root

    if [[ -z "$server" || -z "$secret" ]]; then
        if [ -f "$NEZHA_CONFIG" ]; then
            echo ">>> [探针] 使用现有配置启动。"
        else
            echo ">>> [探针] 无配置参数，跳过。"
            return
        fi
    fi

    # 探针下载逻辑
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then NZ_ARCH="amd64"; elif [[ "$ARCH" == "aarch64" ]]; then NZ_ARCH="arm64"; else NZ_ARCH="amd64"; fi
    BIN_FILE="nezha-agent"
    DOWNLOAD_URL="https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${NZ_ARCH}.zip"

    if [ ! -f "$BIN_FILE" ]; then
        echo ">>> [下载] 下载探针 ($NZ_ARCH)..."
        rm -rf nezha.zip
        curl -L -o nezha.zip "$DOWNLOAD_URL"
        unzip -o nezha.zip >/dev/null 2>&1
        chmod +x "$BIN_FILE"
    fi

    if [[ -n "$server" && -n "$secret" ]]; then
        cat > "$NEZHA_CONFIG" <<EOF
server: ${server}
client_secret: ${secret}
tls: ${tls:-false}
EOF
        [ -n "$uuid" ] && echo "uuid: $uuid" >> "$NEZHA_CONFIG"
    fi

    ./"$BIN_FILE" -c "$NEZHA_CONFIG" >/dev/null 2>&1 &
}

# ==========================================
# 🚀 4. 主业务逻辑
# ==========================================
start_main_script() {
    cd /root
    echo -e "\n>>> [主程序] 检查业务脚本..."
    
    if [ ! -f "$ARGOSBX_SCRIPT" ]; then
        echo ">>> [下载] 拉取 argosbx.sh ..."
        curl -L -o "$ARGOSBX_SCRIPT" "$ARGOSBX_URL"
    fi
    
    chmod +x "$ARGOSBX_SCRIPT"
    
    echo ">>> [启动] 运行 argosbx.sh ..."
    bash "$ARGOSBX_SCRIPT" &
}

# ==========================================
# 🏁 5. 入口
# ==========================================
main() {
    clear
    echo "===================================================="
    echo "      全自动启动脚本 (支持 bash <(curl) 模式)"
    echo "===================================================="

    # 第一步：把自己下载到硬盘并授权 (解决你的痛点)
    install_self

    # 第二步：设置开机自启
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
    tail -f /dev/null
}

main
