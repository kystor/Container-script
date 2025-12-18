#!/bin/bash

# ==========================================
# 🟢 脚本说明与配置区
# ==========================================
# 这是一个集成了哪吒探针和 Argosbx 业务的自动化脚本。
# 修改内容：
# 1. 增加了 Argosbx 启动前的环境变量交互输入。
# 2. 详细注释了每一段代码的作用。

# 🟢 【配置 1】：哪吒指令预设区 (如果这里填了，会作为默认值之一)
PRESET_NEZHA_COMMAND=""

# 🟢 【配置 2】：自定义环境变量 (脚本内部默认的，优先级低于手动输入)
CUSTOM_VARIABLES='hypt=""'

# 🟢 【核心】：脚本自身的远程下载地址 (用于自启更新)
SELF_URL="https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh"
LOCAL_SCRIPT="$HOME/start.sh"

# ==========================================
# 📦 基础环境与变量加载
# ==========================================

cd "$HOME" || exit
# 切换到用户主目录，确保操作路径一致

echo ">>> [初始化] 工作目录已锁定至: $HOME"

# 加载脚本头部定义的默认变量
if [ -n "$CUSTOM_VARIABLES" ]; then
    echo ">>> [环境] 检测到预设变量字符串，正在加载..."
    eval "export $CUSTOM_VARIABLES"
fi

# ==========================================
# 0. 🔌 自我安装与开机自启模块
# ==========================================
setup_persistence() {
    echo ""
    echo ">>> [系统] 正在检查脚本完整性与开机自启..."

    # 下载最新版脚本覆盖当前文件 (保持脚本最新)
    curl -L -s -o "$LOCAL_SCRIPT" "$SELF_URL"
    chmod +x "$LOCAL_SCRIPT"

    # 构建 Crontab 任务命令
    if [ -n "$CUSTOM_VARIABLES" ]; then
        # 如果有变量，需要在自启命令中也带上
        CRON_CMD="@reboot eval \"export $CUSTOM_VARIABLES\"; /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    else
        CRON_CMD="@reboot /bin/bash \"$LOCAL_SCRIPT\" >/dev/null 2>&1 &"
    fi

    # 检查是否已经添加过任务
    if crontab -l 2>/dev/null | grep -q "$LOCAL_SCRIPT"; then
        echo ">>> [自启] ✅ 开机自启任务已存在，跳过。"
    else
        # 添加任务到 crontab
        (crontab -l 2>/dev/null; echo "$CRON_CMD") | crontab -
        if [ $? -eq 0 ]; then
            echo ">>> [自启] ✅ 成功添加开机自启任务！"
        else
            echo ">>> [自启] ❌ 添加失败 (可能是权限受限，容器内常见)。"
        fi
    fi
}

# ==========================================
# 1. 🛡️ 哪吒探针逻辑模块
# ==========================================
start_nezha() {
    local cmd_str="$1"
    # 如果没有传递配置字符串，直接返回
    if [ -z "$cmd_str" ]; then
        echo ">>> [探针] 未提供配置，跳过哪吒探针启动。"
        return
    fi

    echo ""
    echo ">>> [探针] 正在解析配置并准备启动..."

    # 提取关键参数：Server, Secret, TLS
    local server=$(echo "$cmd_str" | grep -o 'NZ_SERVER=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local secret=$(echo "$cmd_str" | grep -o 'NZ_CLIENT_SECRET=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    local tls=$(echo "$cmd_str" | grep -o 'NZ_TLS=[^ ]*' | cut -d= -f2 | sed 's/["'\'']//g')
    
    if [ -z "$tls" ]; then tls="false"; fi

    if [ -z "$server" ] || [ -z "$secret" ]; then
        echo ">>> [错误] 无法解析 Server 或 Secret，请检查指令格式。"
        return
    fi

    # 判断系统架构 (AMD64 或 ARM64)
    local arch=$(uname -m)
    local arch_code="amd64"
    if [[ "$arch" == "aarch64" || "$arch" == "arm64" ]]; then arch_code="arm64"; fi
    
    local bin_file="nezha-agent"
    local config_file="nezha.yml"

    # 下载哪吒探针二进制文件
    if [ ! -f "$bin_file" ]; then
        echo ">>> [下载] 正在下载哪吒探针 (${arch_code})..."
        curl -L -o nezha.zip "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${arch_code}.zip"
        unzip -o nezha.zip > /dev/null
        chmod +x "$bin_file"
        rm -f nezha.zip
    fi

    # 生成配置文件
    cat > "$config_file" <<EOF
server: $server
client_secret: $secret
tls: $tls
EOF

    echo ">>> [启动] 拉起 Nezha Agent..."
    # 后台运行探针
    ./"$bin_file" -c "$config_file" >/dev/null 2>&1 &  
}

# ==========================================
# 2. 🚀 主业务逻辑 (Argosbx)
# ==========================================
start_argosbx() {
    echo ""
    echo "===================================================="
    echo ">>> [主程序] 准备启动 Argosbx 业务"
    echo "===================================================="
    
    # 🟢 【新增功能】：手动输入环境变量
    # 这里的 read -t 20 表示等待20秒，-p 是提示语
    echo "请输入 Argosbx 需要的环境变量 (例如: hypt="1234")"
    echo "提示：如果有多个变量，请用空格隔开；直接回车则跳过。"
    read -t 20 -p "请输入变量 > " USER_ENV_INPUT

    if [ -n "$USER_ENV_INPUT" ]; then
        echo ">>> [环境] 检测到手动输入变量，正在应用..."
        # 使用 eval export 将字符串转换为系统环境变量
        eval "export $USER_ENV_INPUT"
    else
        echo ">>> [环境] 未检测到输入或超时，使用默认环境。"
    fi

    echo ">>> [主程序] 正在下载并运行脚本..."
    
    local script_name="argosbx.sh"
    local script_url="https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"

    if [ ! -f "$script_name" ]; then
        curl -L -o "$script_name" "$script_url"
        chmod +x "$script_name"
    fi

    # 运行主脚本
    # 注意：这里直接运行，会继承上面 export 的环境变量
    ./"$script_name"
}

# ==========================================
# 🏁 脚本入口 (Main Function)
# ==========================================
clear
echo "===================================================="
echo "      Container-Script (增强版)"
echo "===================================================="

# 1. 配置自启
setup_persistence

CONFIG_SOURCE=""
TIMEOUT=10 # 倒计时可以根据需要调整
BACKUP_FILE="nezha.conf"

# 2. 读取旧的备份配置
# 如果之前运行过并输入了指令，nezha.conf 里会有记录
if [ -f "$BACKUP_FILE" ]; then 
    CACHED_CMD=$(cat "$BACKUP_FILE") 
    echo ">>> [备份] 检测到本地已保存的哪吒配置。"
fi

# 3. 哪吒指令交互逻辑
echo "----------------------------------------------------"
echo "请配置【哪吒探针】($TIMEOUT 秒倒计时):"
echo "1. [输入] 粘贴新指令并回车 -> 更新配置并启动"
echo "2. [回车] 直接按回车       -> 使用上次保存的配置 (或预设)"
echo "----------------------------------------------------"

read -t $TIMEOUT -p "请输入哪吒指令 > " USER_INPUT
echo ""

# 🟢 【逻辑检查】：这里是你关心的“保留信息”逻辑
# 逻辑说明：
# - 场景 A：你输入了新指令 ($USER_INPUT 非空)
#   -> 脚本使用你的新指令，并将其写入 BACKUP_FILE (覆盖旧备份)。下次运行就是这个新指令。
# - 场景 B：你直接回车 ($USER_INPUT 为空)
#   -> 脚本会去检查预设 ($PRESET_NEZHA_COMMAND) 或 备份 ($CACHED_CMD)。
#   -> 这样就实现了“一次输入，永久保留”的效果。

if [ -n "$USER_INPUT" ]; then
    # 用户输入了内容
    CONFIG_SOURCE="$USER_INPUT"
    echo "$USER_INPUT" > "$BACKUP_FILE"  # 关键点：保存新配置到文件
    echo ">>> [配置] 新指令已保存至本地备份。"
elif [ -n "$PRESET_NEZHA_COMMAND" ]; then
    # 用户没输入，但脚本里写死预设
    CONFIG_SOURCE="$PRESET_NEZHA_COMMAND"
    echo ">>> [配置] 使用脚本内置预设。"
elif [ -n "$CACHED_CMD" ]; then
    # 用户没输入，也没有预设，但本地文件里有旧的
    CONFIG_SOURCE="$CACHED_CMD"
    echo ">>> [配置] 使用本地备份的配置。"
fi

# 4. 启动服务
start_nezha "$CONFIG_SOURCE"
start_argosbx

# 5. 保活逻辑
# 这是一个死循环，每小时醒来一次，防止容器因为脚本运行结束而退出
echo ""
echo ">>> [保活] 正在启动后台保活进程 (Keep-Alive)..."
nohup sh -c 'while true; do sleep 3600; done' >/dev/null 2>&1 &

echo ">>> [完成] 所有任务已触发，脚本执行完毕。"
