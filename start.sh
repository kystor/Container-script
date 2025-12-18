#!/bin/bash

# ==========================================
# 🛠️ 全局配置区
# ==========================================

# 🟢 【配置 1】：哪吒指令预设区
# 示例：PRESET_NEZHA_COMMAND="export NZ_SERVER=nz.example.com NZ_CLIENT_SECRET=123 NZ_TLS=true"
PRESET_NEZHA_COMMAND=""

# 🟢 【配置 2】：自定义环境变量 (通用)
# 解释：这里填入的内容会被脚本自动解析并设为环境变量。
# 格式：变量名="值" (多个变量用空格隔开)
# ✅ 修改：外层使用单引号，内层使用双引号，这样更方便阅读
# 示例 1：CUSTOM_VARIABLES='hypt="123456"'
# 示例 2：CUSTOM_VARIABLES='hypt="my-token" tupt="other-value"'
CUSTOM_VARIABLES='hypt=""'

# 🟢 【核心】：脚本自身的远程下载地址
SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh"
LOCAL_SCRIPT="$HOME/start.sh"

# ==========================================
# 📦 基础环境与变量加载
# ==========================================

cd "$HOME" || exit
echo ">>> [初始化] 工作目录已锁定至: $HOME"

# 🟢 核心逻辑：加载自定义变量
# 1. 优先加载文件内配置的 CUSTOM_VARIABLES
if [ -n "$CUSTOM_VARIABLES" ]; then
    echo ">>> [环境] 检测到预设变量字符串，正在加载..."
    # 使用 eval export 动态将字符串内的所有 变量="值" 导出为环境变量
    eval "export $CUSTOM_VARIABLES"
fi

# 2. 打印当前关键变量状态 (仅作调试显示)
echo ">>> [环境] 变量加载检查："
env | grep -E "hypt=|tupt=" || echo "    (未检测到 hypt/tupt，如使用了其他变量名请忽略此提示)"

# ==========================================
# 0. 🔌 自我安装与开机自启
# ==========================================
setup_persistence() {
    echo ""
    echo ">>> [系统] 正在检查脚本完整性与开机自启..."

    # 强制更新本地文件
    curl -L -s -o "$LOCAL_SCRIPT" "$SELF_URL"
    chmod +x "$LOCAL_SCRIPT"

    # 构建开机自启命令
    # 逻辑：重启时，我们需要把当前的 CUSTOM_VARIABLES 也带进去
    if [ -n "$CUSTOM_VARIABLES" ]; then
        # 注意：这里为了保证重启后变量值的引号正确，我们对变量再次进行转义处理
        # 确保写入 Crontab 的命令格式正确
        CRON_CMD="@reboot eval \"export $CUSTOM_VARIABLES\"; /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    else
        CRON_CMD="@reboot /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    fi

    if crontab -l 2>/dev/null | grep -q "$LOCAL_SCRIPT"; then
        echo ">>> [自启] ✅ 开机自启任务已存在，跳过。"
    else
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        if [ $? -eq 0 ]; then
            echo ">>> [自启] ✅ 成功添加开机自启任务！"
        else
            echo ">>> [自启] ❌ 添加失败 (可能是权限受限)。"
        fi
    fi
}

# ==========================================
# 1. 🛡️ 哪吒探针逻辑
# ==========================================
start_nezha() {
    local cmd_str="$1"
    if [ -z "$cmd_str" ]; then
        echo ">>> [探针] 未提供配置，跳过哪吒探针启动。"
        return
    fi

    echo ""
    echo ">>> [探针] 正在解析配置并准备启动..."

    local server=$(echo "$cmd_str" | grep -o 'NZ_SERVER=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local secret=$(echo "$cmd_str" | grep -o 'NZ_CLIENT_SECRET=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local tls=$(echo "$cmd_str" | grep -o 'NZ_TLS=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    
    if [ -z "$tls" ]; then tls="false"; fi

    if [ -z "$server" ] || [ -z "$secret" ]; then
        echo ">>> [错误] 无法解析 Server 或 Secret。"
        return
    fi

    local arch=$(uname -m)
    local arch_code="amd64"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then arch_code="arm64"; fi
    
    local bin_file="nezha-agent"
    local config_file="nezha.yml"

    if [ ! -f "$bin_file" ]; then
        echo ">>> [下载] 正在下载哪吒探针 (${arch_code})..."
        curl -L -o nezha.zip "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch_code}.zip"
        unzip -o nezha.zip > /dev/null
        chmod +x "$bin_file"
        rm -f nezha.zip
    fi

    cat > "$config_file" <<EOF
server: $server
client_secret: $secret
tls: $tls
EOF

    echo ">>> [启动] 拉起 Nezha Agent..."
    ./"$bin_file" -c "$config_file" >/dev/null 2>&1 &  
}

# ==========================================
# 2. 🚀 主业务逻辑 (Argosbx)
# ==========================================
start_argosbx() {
    echo ""
    echo "===================================================="
    echo ">>> [主程序] 启动 Argosbx 业务脚本"
    echo "===================================================="
    
    local script_name="argosbx.sh"
    local script_url="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

    if [ ! -f "$script_name" ]; then
        curl -L -o "$script_name" "$script_url"
        chmod +x "$script_name"
    fi

    # 关键：这里直接运行，它会自动继承当前环境里所有的变量
    ./"$script_name"
}

# ==========================================
# 🏁 脚本入口
# ==========================================
clear
echo "===================================================="
echo "      Container-Script (通用版)"
echo "===================================================="

setup_persistence

CONFIG_SOURCE=""
TIMEOUT=20
BACKUP_FILE="nezha.conf"

if [ -f "$BACKUP_FILE" ]; then CACHED_CMD=$(cat "$BACKUP_FILE"); fi

echo "----------------------------------------------------"
echo "请选择操作 ($TIMEOUT 秒倒计时):"
echo "1. [粘贴] 粘贴 'export NZ_SERVER=...' (优先级最高)"
echo "2. [回车] 使用 GitHub 预设或本地缓存配置"
echo "----------------------------------------------------"

read -t $TIMEOUT -p "请输入 > " USER_INPUT
echo ""

if [ -n "$USER_INPUT" ]; then
    CONFIG_SOURCE="$USER_INPUT"
    echo "$USER_INPUT" > "$BACKUP_FILE"
elif [ -n "$PRESET_NEZHA_COMMAND" ]; then
    CONFIG_SOURCE="$PRESET_NEZHA_COMMAND"
elif [ -n "$CACHED_CMD" ]; then
    CONFIG_SOURCE="$CACHED_CMD"
fi

start_nezha "$CONFIG_SOURCE"
start_argosbx

echo ""
echo ">>> [保活] 脚本进入无限循环模式..."
while true; do sleep 3600; done
