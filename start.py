#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import sys
import time
import json
import re
import subprocess
import platform
import select
import signal

# ==========================================
# 🛠️ 全局配置区
# ==========================================

# [优先级 2] (代码预设) 如果你有哪吒指令需求，请在双引号中输入哪吒指令
PRESET_NEZHA_COMMAND = ""

# 🟢 【修改处】：在这里填入你的环境变量字符串
# 格式要求：变量名="值"，多个变量用空格隔开
CUSTOM_ENV_INPUT = 'hypt=""'

TIMEOUT_SECONDS = 20              # 倒计时等待时间 (秒)
CONFIG_FILE_YAML = 'nezha.yml'    # 探针配置文件名
BACKUP_FILE = 'nezha_config.json' # 配置备份文件名

# 🟢 新增：argosbx.sh 下载地址
ARGOSBX_URL = 'https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh'
ARGOSBX_FILE = 'argosbx.sh'

# ==========================================
# 🟢 环境解析模块 (自动执行)
# ==========================================
def parse_and_load_env():
    if not CUSTOM_ENV_INPUT:
        return

    print('\n>>> [环境] 正在加载自定义变量...')

    # 正则提取 变量名=值 (支持带双引号或不带引号的值)
    # Python 正则: (\w+)=(?:"([^"]*)"|(\S+))
    pattern = re.compile(r'(\w+)=(?:"([^"]*)"|(\S+))')
    matches = pattern.findall(CUSTOM_ENV_INPUT)

    for match in matches:
        key = match[0]
        # match[1] 是双引号内的值, match[2] 是无引号的值
        value = match[1] if match[1] else match[2]

        # 注入到当前进程的环境变量中
        os.environ[key] = value
        print(f"    + 成功设置: {key} = {value}")

    print('>>> [环境] 加载完毕。\n')

# 执行环境加载
parse_and_load_env()

# ==========================================
# 1. 🟢 下载 argosbx.sh
# ==========================================
def download_argosbx_sh():
    """
    下载 argosbx.sh 到当前目录。
    若下载成功，则赋予可执行权限。
    """
    print('\n====================================================')
    print('>>> [下载] 正在准备获取 argosbx.sh ...')
    print('====================================================')

    try:
        # 使用 curl 下载脚本
        subprocess.run(
            ["curl", "-L", "-o", ARGOSBX_FILE, ARGOSBX_URL],
            check=True
        )

        # 赋予执行权限
        try:
            os.chmod(ARGOSBX_FILE, 0o755)
        except Exception:
            pass

        print(f">>> [下载] argosbx.sh 下载完成: {ARGOSBX_FILE}")
        return True

    except subprocess.CalledProcessError as e:
        print(f">>> [错误] 下载 argosbx.sh 失败: {e}")
        print(">>> [提示] 如果当前目录已存在 argosbx.sh，将尝试继续使用本地文件。")
        return os.path.exists(ARGOSBX_FILE)

    except Exception as e:
        print(f">>> [错误] 处理 argosbx.sh 时发生异常: {e}")
        return os.path.exists(ARGOSBX_FILE)

# ==========================================
# 2. 🚀 启动主业务 (Argosbx)
# ==========================================
def start_main_script():
    print('\n====================================================')
    print('>>> [主程序] 正在启动主业务脚本 (argosbx.sh) ...')
    print('====================================================')

    script_path = f'./{ARGOSBX_FILE}'

    # 如果文件不存在，先自动下载
    if not os.path.exists(script_path):
        print('>>> [主程序] 检测到本地不存在 argosbx.sh，开始下载...')
        if not download_argosbx_sh():
            print('>>> [错误] argosbx.sh 下载失败且本地也不存在，无法启动主业务。')
            return
    else:
        # 如果存在，也可以选择更新一次，保证是最新版本
        # 如果你不想每次都更新，可以把这一段注释掉
        print('>>> [主程序] 检测到本地已有 argosbx.sh，尝试重新下载以更新到最新版本...')
        download_argosbx_sh()

    # 再次确认文件存在
    if not os.path.exists(script_path):
        print('>>> [错误] 找不到 argosbx.sh 文件，请检查下载结果。')
        return

    # 给予脚本执行权限
    try:
        os.chmod(script_path, 0o755)
    except Exception:
        pass

    # 启动 bash 脚本，继承当前的环境变量 (os.environ)
    # 使用 subprocess.Popen 异步启动
    try:
        subprocess.Popen(['bash', script_path], env=os.environ)
    except Exception as e:
        print(f">>> [错误] 启动脚本失败: {e}")

# ==========================================
# 3. 🛡️ 哪吒探针安装与启动逻辑 (智能 UUID 版)
# ==========================================
def start_nezha(server, secret, tls, force_uuid=None):
    if not server or not secret:
        print('>>> [跳过] 缺少探针参数，不启动哪吒探针。')
        return

    print(f"\n>>> [探针] 准备启动哪吒探针...")
    print(f"    服务器: {server}")
    print(f"    TLS: {tls}")
    if force_uuid:
        print(f"    UUID: {force_uuid} (强制指定)")

    # 自动判断系统架构
    machine = platform.machine().lower()
    # 简单的映射逻辑
    if 'aarch64' in machine or 'arm64' in machine:
        arch_code = 'arm64'
    elif 'x86_64' in machine or 'amd64' in machine:
        arch_code = 'amd64'
    else:
        arch_code = 'amd64'  # 默认回退

    bin_file = 'nezha-agent'
    download_url = f"https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_{arch_code}.zip"

    # 🟢 [优化] 只有存在文件时才执行清理
    if os.path.exists(bin_file) or os.path.exists('nezha.zip'):
        print('>>> [清理] 检测到旧文件，正在移除以确保安装纯净...')
        subprocess.run(f"rm -rf {bin_file} nezha.zip", shell=True)

    print(f">>> [下载] 正在下载适配 {arch_code} 的探针...")
    try:
        subprocess.run(["curl", "-L", "-o", "nezha.zip", download_url], check=True)
        subprocess.run(["unzip", "-o", "nezha.zip"], check=True)
        subprocess.run(["chmod", "+x", bin_file], check=True)
        print('>>> [下载] 完成并已授权！')
    except subprocess.CalledProcessError:
        print('\n>>> [错误] 下载或解压失败！请检查网络。')
        return

    # =========================================================
    # 🟢 [核心逻辑] 配置文件生成：UUID 优先级判断
    # =========================================================

    final_config = f"server: {server}\nclient_secret: {secret}\ntls: {tls}\n"

    # 优先级 1: 如果输入命令里强制带了 UUID，直接用
    if force_uuid:
        final_config += f"uuid: {force_uuid}\n"
        print('>>> [配置] 检测到命令中包含 UUID，已强制应用。')

    # 优先级 2: 如果没强制指定，检查本地旧配置
    elif os.path.exists(CONFIG_FILE_YAML):
        try:
            with open(CONFIG_FILE_YAML, 'r', encoding='utf-8') as f:
                old_content = f.read()

            # 提取旧服务器地址
            server_match = re.search(r'server: (.*)', old_content)
            old_server = server_match.group(1).strip() if server_match else None

            # 提取旧 UUID
            uuid_match = re.search(r'uuid: .*', old_content)

            # 只有服务器地址没变，才保留旧 UUID
            if old_server == server and uuid_match:
                print('>>> [配置] 服务器地址未变，保留旧 UUID 以延续数据。')
                final_config += f"{uuid_match.group(0)}\n"
            elif uuid_match:
                print('>>> [配置] 检测到服务器地址变更，且未指定新UUID，将生成新探针。')
        except Exception:
            pass

    with open(CONFIG_FILE_YAML, 'w', encoding='utf-8') as f:
        f.write(final_config)
    print(f">>> [配置] 配置文件已生成: {CONFIG_FILE_YAML}")

    # --- 启动进程 ---
    print('>>> [启动] 正在拉起 nezha-agent 进程...')
    print('----------------------------------------------------')

    try:
        subprocess.Popen([f"./{bin_file}", "-c", CONFIG_FILE_YAML], env=os.environ)
    except Exception as e:
        print(f">>> [错误] 启动哪吒失败: {e}")

# ==========================================
# 4. ⚙️ 参数解析模块
# ==========================================
def parse_command(cmd_input):
    if not cmd_input:
        return None

    # 正则提取哪吒参数
    server_match = re.search(r'NZ_SERVER=([\w\.:-]+)', cmd_input)
    secret_match = re.search(r'NZ_CLIENT_SECRET=([\w-]+)', cmd_input)
    tls_match = re.search(r'NZ_TLS=(true|false)', cmd_input)
    # 🟢 [新增] 支持提取 NZ_UUID
    uuid_match = re.search(r'NZ_UUID=([\w-]+)', cmd_input)

    if server_match and secret_match:
        return {
            'server': server_match.group(1),
            'secret': secret_match.group(1),
            'tls': tls_match.group(1) if tls_match else 'false',
            'uuid': uuid_match.group(1) if uuid_match else None
        }
    return None

# ==========================================
# 5. 🏁 主入口函数
# ==========================================
def main():
    # 清屏 (跨平台兼容)
    os.system('cls' if os.name == 'nt' else 'clear')

    print('====================================================')
    print('        多功能启动脚本 - 哪吒探针 & 业务程序')
    print('====================================================')

    preset_config = parse_command(PRESET_NEZHA_COMMAND)
    backup_config = None

    # 尝试读取本地备份
    if os.path.exists(BACKUP_FILE):
        try:
            with open(BACKUP_FILE, 'r', encoding='utf-8') as f:
                backup_config = json.load(f)
        except Exception:
            pass

    if preset_config:
        print(f"[提示] 代码预设: {preset_config['server']}")
    if backup_config:
        print(f"[提示] 本地备份: {backup_config['server']}")

    print('----------------------------------------------------')
    print(f"请选择操作 ({TIMEOUT_SECONDS}秒倒计时):")
    print(f"1. [粘贴] 输入新命令并回车 -> 使用新命令 (优先级最高)")
    print(f"2. [回车] 直接按回车        -> 跳过等待，使用预设或备份")
    print(f"3. [等待] 倒计时结束        -> 自动使用预设或备份")
    print('----------------------------------------------------')

    user_input_str = None
    print("请输入 > ", end="", flush=True)

    # 模拟 Node.js 的超时输入逻辑 (只在 Linux/Mac 有效，Windows 需要 msvcrt)
    # Docker 环境通常是 Linux，所以使用 select
    try:
        rlist, _, _ = select.select([sys.stdin], [], [], TIMEOUT_SECONDS)
        if rlist:
            user_input_str = sys.stdin.readline().strip()
        else:
            print(f"\n>>> 倒计时结束，自动继续...")
    except Exception:
        # 如果 select 报错（极少数环境），直接跳过
        pass

    final_config = None

    # 处理用户输入
    if user_input_str and len(user_input_str) > 5:
        console_config = parse_command(user_input_str)
        if console_config:
            print('>>> [来源] 使用控制台输入的命令。')
            final_config = console_config
            # 备份最新配置到本地
            with open(BACKUP_FILE, 'w', encoding='utf-8') as f:
                json.dump(final_config, f)
        else:
            print('>>> [忽略] 输入的命令格式无法识别。')

    # 回退到代码预设
    if not final_config and preset_config:
        print('>>> [来源] 使用代码变量 (PRESET_NEZHA_COMMAND)。')
        final_config = preset_config

    # 回退到本地备份
    if not final_config and backup_config:
        print('>>> [来源] 使用本地备份文件。')
        final_config = backup_config

    # 启动哪吒 (传入 4 个参数)
    if final_config:
        start_nezha(
            final_config['server'],
            final_config['secret'],
            final_config['tls'],
            final_config.get('uuid')
        )
    else:
        print('>>> [提示] 未找到配置，仅启动主业务。')

    # 启动主业务
    start_main_script()

    # 防止进程退出 (Python 版的 Keep Alive)
    print(">>> 脚本进入无限保活模式...")
    while True:
        time.sleep(3600)

if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print("\n>>> 用户终止脚本。")
