#!/bin/bash

# ==========================================
# 🛠️ 全局配置区
# ==========================================

# [优先级 2] (代码预设) 在双引号中填入哪吒指令
PRESET_NEZHA_COMMAND=""

# 🟢 【修改处】：在这里填入你的环境变量
# 格式：export 变量名="值"
export hypt=""

# 定义文件名常量
NEZHA_CONFIG="nezha.yml"
BACKUP_FILE="nezha_config.json" # Shell版简化逻辑，主要依赖yml文件
ARGOSBX_SCRIPT="argosbx.sh"
ARGOSBX_URL="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"
TIMEOUT_SECONDS=20

# ==========================================
# 🟢 1. 初始化与环境设置
# ==========================================

# 锁定工作目录
# 解释：$(dirname "$0") 获取脚本所在目录，确保后续下载的文件都在脚本旁边
cd "$(dirname "$(readlink -f "$0")")"
CURRENT_DIR=$(pwd)
echo ">>> [初始化] 工作目录已锁定至: $CURRENT_DIR"

# 解析自定义环境变量 (简单的 key=value 形式在上方 export 即可)
if [ -n "$hypt" ]; then
    echo ">>> [环境] 自定义变量 hypt 已加载."
fi

# ==========================================
# 🔌 2. 开机自启功能模块
# ==========================================
add_self_to_startup() {
    echo -e "\n>>> [自启] 正在检查开机自启配置..."
    
    # 获取当前脚本的绝对路径
    SCRIPT_PATH="$CURRENT_DIR/$(basename "$0")"
    
    # 构建 Crontab 命令：重启时(@reboot) -> 进入目录 -> 运行脚本
    CRON_CMD="@reboot cd $CURRENT_DIR && bash $SCRIPT_PATH >/dev/null 2>&1 &"
    
    # 检查是否已存在 (grep -F 固定字符串搜索)
    if crontab -l 2>/dev/null | grep -Fq "$SCRIPT_PATH"; then
        echo ">>> [自启] ✅ 检测到已添加过开机自启，跳过写入。"
    else
        # 写入新的 crontab
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        if [ $? -eq 0 ]; then
            echo ">>> [自启] ✅ 成功将脚本加入开机自动启动！"
        else
            echo ">>> [自启] ❌ 添加失败。"
        fi
    fi
}

# ==========================================
# 🛠️ 辅助函数：提取参数
# ==========================================
# 解释：模拟 Node.js 的正则提取，从长字符串中提取 NZ_SERVER 等参数
get_param() {
    local input_str="$1"
    local key="$2"
    # 使用 grep 和 sed 提取 key=value 中的 value
    echo "$input_str" | grep -oP "$key=\K[\w\.:-]+" 2>/dev/null || \
    echo "$input_str" | sed -n "s/.*$key=\([^ ]*\).*/\1/p"
}

# ==========================================
# 🛡️ 3. 哪吒探针逻辑
# ==========================================
start_nezha() {
    local cmd_str="$1"
    
    # 提取参数
    local server=$(get_param "$cmd_str" "NZ_SERVER")
    local secret=$(get_param "$cmd_str" "NZ_CLIENT_SECRET")
    local tls=$(get_param "$cmd_str" "NZ_TLS")
    local uuid=$(get_param "$cmd_str" "NZ_UUID")

    # 如果没有服务器或密钥，尝试从现有的 nezha.yml 读取 (简单的兼容性检查)
    if [[ -z "$server" || -z "$secret" ]]; then
        if [ -f "$NEZHA_CONFIG" ]; then
            echo ">>> [探针] 使用现有配置文件启动。"
        else
            echo ">>> [探针] 缺少参数且无配置文件，跳过哪吒探针。"
            return
        fi
    fi

    echo -e "\n>>> [探针] 准备启动哪吒探针..."
    
    # --- 下载部分 ---
    # 检测系统架构 (amd64 或 arm64)
    ARCH=$(uname -m)
    if [[ "$ARCH" == "x86_64" ]]; then NZ_ARCH="amd64"; elif [[ "$ARCH" == "aarch64" ]]; then NZ_ARCH="arm64"; else NZ_ARCH="amd64"; fi
    
    BIN_FILE="nezha-agent"
    DOWNLOAD_URL="https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${NZ_ARCH}.zip"

    # 如果没有探针文件，则下载
    if [ ! -f "$BIN_FILE" ]; then
        echo ">>> [下载] 正在下载适配 ${NZ_ARCH} 的探针..."
        rm -rf nezha.zip
        curl -L -o nezha.zip "$DOWNLOAD_URL"
        unzip -o nezha.zip
        chmod +x "$BIN_FILE"
        echo ">>> [下载] 完成并已授权！"
    fi

    # --- 配置生成部分 ---
    # 只有当传入了新参数时，才重新生成配置文件
    if [[ -n "$server" && -n "$secret" ]]; then
        echo ">>> [配置] 生成新的配置文件..."
        cat > "$NEZHA_CONFIG" <<EOF
server: ${server}
client_secret: ${secret}
tls: ${tls:-false}
EOF
        if [ -n "$uuid" ]; then
            echo "uuid: $uuid" >> "$NEZHA_CONFIG"
        fi
    fi

    # --- 启动部分 ---
    echo ">>> [启动] 正在后台拉起 nezha-agent..."
    # 解释：& 符号让程序在后台运行，不阻塞脚本继续执行
    ./"$BIN_FILE" -c "$NEZHA_CONFIG" >/dev/null 2>&1 &
}

# ==========================================
# 🚀 4. 主业务 (Argosbx) 逻辑
# ==========================================
start_main_script() {
    echo -e "\n===================================================="
    echo ">>> [主程序] 正在检查主业务脚本 ($ARGOSBX_SCRIPT) ..."
    echo "===================================================="

    # 如果文件不存在，自动下载
    if [ ! -f "$ARGOSBX_SCRIPT" ]; then
        echo ">>> [警告] 未检测到脚本文件。"
        echo ">>> [下载] 正在从 GitHub 拉取..."
        curl -L -o "$ARGOSBX_SCRIPT" "$ARGOSBX_URL"
        
        if [ $? -eq 0 ]; then
            echo ">>> [下载] ✅ 下载成功！"
        else
            echo ">>> [错误] ❌ 下载失败，请检查网络。"
            return
        fi
    else
        echo ">>> [检测] ✅ 文件已存在。"
    fi

    chmod +x "$ARGOSBX_SCRIPT"
    
    echo ">>> [启动] 正在执行 argosbx.sh ..."
    # 启动 bash 脚本
    # 解释：这里我们在后台启动它，然后脚本最后进入保活模式
    bash "./$ARGOSBX_SCRIPT" &
    
    echo ">>> [主程序] 已在后台启动。"
}

# ==========================================
# 🏁 5. 主入口流程
# ==========================================
main() {
    clear
    echo "===================================================="
    echo "        多功能启动脚本 (Shell版 - 含自启/自动下载)"
    echo "===================================================="

    # 1. 设置自启
    add_self_to_startup

    # 2. 获取用户输入 (倒计时)
    echo "----------------------------------------------------"
    echo "请选择操作 ($TIMEOUT_SECONDS 秒倒计时):"
    echo "1. [粘贴] 输入包含 NZ_SERVER=... 的命令并回车"
    echo "2. [回车] 直接回车或等待 -> 使用预设"
    echo "----------------------------------------------------"

    # read -t 用于设置超时时间
    read -t $TIMEOUT_SECONDS -p "请输入 > " USER_INPUT

    # 3. 决策逻辑
    FINAL_CONFIG=""
    
    if [ -n "$USER_INPUT" ]; then
        echo -e "\n>>> [来源] 使用控制台输入。"
        FINAL_CONFIG="$USER_INPUT"
    elif [ -n "$PRESET_NEZHA_COMMAND" ]; then
        echo -e "\n>>> [来源] 使用代码预设变量。"
        FINAL_CONFIG="$PRESET_NEZHA_COMMAND"
    else
        echo -e "\n>>> [提示] 无输入且无预设，尝试读取旧配置或仅启动主程序。"
    fi

    # 4. 启动模块
    # 无论有无配置，都尝试运行 start_nezha (函数内部会再次检查参数)
    start_nezha "$FINAL_CONFIG"
    
    # 启动主业务
    start_main_script

    echo -e "\n>>> [保活] 脚本进入无限保活模式..."
    # 解释：tail -f /dev/null 是一个极低资源的命令，用于让容器/脚本不退出
    tail -f /dev/null
}

# 执行主函数
main
