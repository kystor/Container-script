#!/bin/bash

# ===============================================
# 🚀 全能节点启动脚本 (完全被动版)
# ===============================================

# 🟢 1. 接收并检查参数
# -----------------------------------------------

# 检查 UUID
if [ -z "$MY_UUID" ]; then
    echo ">>> [错误] 环境变量 MY_UUID 未设置！请在 main.lua 中配置。"
    exit 1
fi

# 检查 Token
if [ -z "$ARGO_TOKEN" ]; then
    echo ">>> [错误] 环境变量 ARGO_TOKEN 未设置！请在 main.lua 中配置。"
    exit 1
fi

# 检查 域名
if [ -z "$MY_DOMAIN" ]; then
    echo ">>> [错误] 环境变量 MY_DOMAIN 未设置！请在 main.lua 中配置。"
    exit 1
fi

# 检查 内部端口 (New!)
if [ -z "$INTERNAL_PORT" ]; then
    echo ">>> [错误] 环境变量 INTERNAL_PORT 未设置！请在 main.lua 中配置。"
    exit 1
fi

echo ">>> [系统] 环境变量加载成功："
echo "    - UUID: $MY_UUID"
echo "    - Domain: $MY_DOMAIN"
echo "    - Port: $INTERNAL_PORT (内部专用)"
# -----------------------------------------------

# 🧹 2. 清理旧进程与残留文件
echo ">>> [系统] 清理旧进程..."
pkill -f web
pkill -f bot
rm -rf web.zip config.json

# 📥 3. 下载核心程序
if [ ! -f "web" ]; then
    echo ">>> [下载] Xray 核心..."
    curl -L -o web.zip https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip
    unzip -o web.zip xray >/dev/null 2>&1
    mv xray web
    rm -f web.zip *.dat geo* LICENSE README.md
    chmod +x web
fi

if [ ! -f "bot" ]; then
    echo ">>> [下载] Argo 隧道核心..."
    curl -L -o bot https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64
    chmod +x bot
fi

# 📝 4. 生成 Xray 配置文件
# 使用 main.lua 传入的 $INTERNAL_PORT
echo ">>> [配置] 生成端口 $INTERNAL_PORT 的配置文件..."
cat > config.json <<EOF
{
    "log": { "loglevel": "warning" },
    "inbounds": [{
        "port": $INTERNAL_PORT,
        "protocol": "vmess",
        "settings": { "clients": [{ "id": "$MY_UUID" }] },
        "streamSettings": { "network": "ws", "wsSettings": { "path": "/vmess" } }
    }],
    "outbounds": [{ "protocol": "freedom" }]
}
EOF

# 🚀 5. 启动服务
echo ">>> [启动] 正在拉起 Cloudflare Tunnel..."
# Argo 日志单独保存
nohup ./bot tunnel --edge-ip-version auto --protocol http2 run --token "$ARGO_TOKEN" > argo.log 2>&1 &

echo ">>> [启动] 正在拉起 Xray 节点..."
# Xray 日志保存
nohup ./web -c config.json > xray.log 2>&1 &

# ===============================================
# 🔗 6. 自动生成并输出链接
# ===============================================

# 构造标准 Vmess JSON
VMESS_JSON=$(cat <<EOF
{
  "v": "2",
  "ps": "BeamMP_Node",
  "add": "${MY_DOMAIN}",
  "port": "443",
  "id": "${MY_UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "ws",
  "type": "none",
  "host": "${MY_DOMAIN}",
  "path": "/vmess",
  "tls": "tls",
  "sni": "${MY_DOMAIN}",
  "alpn": ""
}
EOF
)

# Base64 加密
VMESS_LINK="vmess://$(echo -n "$VMESS_JSON" | base64 -w 0)"

# 打印结果
echo ""
echo "================================================================"
echo "🎉 节点部署成功！请复制下方链接使用："
echo "----------------------------------------------------------------"
echo "📱 Vmess 链接:"
echo ""
echo "$VMESS_LINK"
echo ""
echo "----------------------------------------------------------------"
echo "📋 Clash / Meta 配置参考:"
echo "  - name: BeamMP_Node"
echo "    type: vmess"
echo "    server: $MY_DOMAIN"
echo "    port: 443"
echo "    uuid: $MY_UUID"
echo "    alterId: 0"
echo "    cipher: auto"
echo "    udp: true"
echo "    tls: true"
echo "    servername: $MY_DOMAIN"
echo "    network: ws"
echo "    ws-opts:"
echo "      path: /vmess"
echo "      headers:"
echo "        Host: $MY_DOMAIN"
echo "================================================================"