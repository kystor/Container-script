#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import platform
import queue
import re
import shlex
import subprocess
import sys
import threading
import time
from pathlib import Path


PRESET_NEZHA_COMMAND = ""
PRESET_KOMARI_COMMAND = ""
CUSTOM_ENV_INPUT = 'hypt=""'

TIMEOUT_SECONDS = 20
NEZHA_CONFIG_FILE = "nezha.yml"
NEZHA_BACKUP_FILE = "nezha_config.json"
KOMARI_ARGS_FILE = "komari-agent.args"
KOMARI_BINARY_FILE = "komari-agent"
ARGOSBX_URL = "https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh"
ARGOSBX_FILE = "argosbx.sh"


def log(message: str) -> None:
    print(message, flush=True)


def parse_and_load_env() -> None:
    if not CUSTOM_ENV_INPUT:
        return

    pattern = re.compile(r'(\w+)=(?:"([^"]*)"|(\S+))')
    matches = pattern.findall(CUSTOM_ENV_INPUT)
    if not matches:
        return

    log(">>> [环境] 正在加载自定义环境变量...")
    for key, quoted, plain in matches:
        value = quoted if quoted else plain
        os.environ[key] = value
        log(f">>> [环境] 已设置 {key}={value}")


def is_valid_port(value: str) -> bool:
    return value.isdigit() and 1 <= int(value) <= 65535


def detect_container_port() -> dict | None:
    candidate_vars = [
        "SERVER_PORT",
        "PORT",
        "PANEL_PORT",
        "LISTEN_PORT",
        "APP_PORT",
        "WEB_PORT",
        "CONTAINER_PORT",
        "INTERNAL_PORT",
    ]

    detected_port = ""
    detected_source = ""
    for var_name in candidate_vars:
        candidate = os.environ.get(var_name, "").strip()
        if is_valid_port(candidate):
            detected_port = candidate
            detected_source = var_name
            break

    if not detected_port:
        return None

    os.environ["CONTAINER_PORT"] = detected_port
    os.environ.setdefault("PORT", detected_port)
    os.environ.setdefault("SERVER_PORT", detected_port)
    os.environ.setdefault("INTERNAL_PORT", detected_port)
    os.environ.setdefault("PANEL_PORT", detected_port)
    if not os.environ.get("hypt", "").strip():
        os.environ["hypt"] = detected_port

    return {
        "port": detected_port,
        "source": detected_source,
    }


def print_runtime_context(port_info: dict | None) -> None:
    log("----------------------------------------------------")
    log("                    运行环境信息                    ")
    log("----------------------------------------------------")

    if port_info:
        log(f">>> [端口] 已检测到容器端口: {port_info['port']} (来源: {port_info['source']})")
        log(">>> [端口] 已导出 SERVER_PORT/PORT/CONTAINER_PORT/INTERNAL_PORT")
    else:
        log(">>> [端口] 未检测到容器平台分配端口，将继续使用各模块默认端口")

    if sys.stdin.isatty():
        log(">>> [交互] 当前终端支持交互输入")
    else:
        log(">>> [交互] 当前终端可能不支持交互输入，超时后将自动继续")


def run_command(command, check=False, capture_output=False, shell=False):
    return subprocess.run(
        command,
        check=check,
        text=True,
        capture_output=capture_output,
        shell=shell,
        env=os.environ,
    )


def _read_stdin_line(result_queue: "queue.Queue[str | None]") -> None:
    try:
        line = sys.stdin.readline()
        if line == "":
            result_queue.put(None)
        else:
            result_queue.put(line.rstrip("\n"))
    except Exception:
        result_queue.put(None)


def read_line_with_timeout(prompt: str, timeout_seconds: int) -> str:
    print(prompt, end="", flush=True)
    result_queue: "queue.Queue[str | None]" = queue.Queue(maxsize=1)
    reader = threading.Thread(target=_read_stdin_line, args=(result_queue,), daemon=True)
    reader.start()

    try:
        result = result_queue.get(timeout=timeout_seconds)
    except queue.Empty:
        print("")
        return ""

    if result is None:
        print("")
        return ""

    return result.strip()


def ask_with_timeout(prompt: str, timeout_seconds: int) -> str:
    return read_line_with_timeout(prompt, timeout_seconds)


def read_multiline_with_timeout(first_prompt: str, first_timeout: int, next_timeout: int = 1) -> list[str]:
    lines = []
    first_line = read_line_with_timeout(first_prompt, first_timeout)
    if not first_line:
        return lines

    lines.append(first_line)
    while True:
        line = read_line_with_timeout("", next_timeout)
        if not line.strip():
            break
        lines.append(line)
    return lines


def get_arch_code() -> str:
    machine = platform.machine().lower()
    if machine in ("x86_64", "amd64"):
        return "amd64"
    if machine in ("aarch64", "arm64"):
        return "arm64"
    if machine.startswith("armv7") or machine.startswith("armv6"):
        return "arm"
    if machine in ("i386", "i686"):
        return "386"
    return ""


def load_json_if_exists(path: str):
    if not os.path.exists(path):
        return None
    try:
        with open(path, "r", encoding="utf-8") as file:
            return json.load(file)
    except Exception:
        return None


def save_json(path: str, data) -> None:
    with open(path, "w", encoding="utf-8") as file:
        json.dump(data, file, ensure_ascii=False)


def download_argosbx_sh() -> bool:
    log(">>> [下载] 正在获取 argosbx.sh ...")
    try:
        run_command(["curl", "-L", "-o", ARGOSBX_FILE, ARGOSBX_URL], check=True)
        os.chmod(ARGOSBX_FILE, 0o755)
        return True
    except Exception as exc:
        log(f">>> [错误] 下载 argosbx.sh 失败: {exc}")
        return os.path.exists(ARGOSBX_FILE)


def start_main_script() -> None:
    log(">>> [主程序] 正在启动 Argosbx ...")
    script_path = f"./{ARGOSBX_FILE}"

    if not os.path.exists(ARGOSBX_FILE):
        if not download_argosbx_sh():
            log(">>> [错误] 无法启动 Argosbx，脚本不存在且下载失败")
            return

    try:
        os.chmod(ARGOSBX_FILE, 0o755)
    except Exception:
        pass

    try:
        subprocess.Popen(["bash", script_path, "rep"], env=os.environ)
    except Exception as exc:
        log(f">>> [错误] 启动 Argosbx 失败: {exc}")


def parse_nezha_command(cmd_input: str):
    if not cmd_input:
        return None

    server_match = re.search(r'NZ_SERVER=([^\s]+)', cmd_input)
    secret_match = re.search(r'NZ_CLIENT_SECRET=([^\s]+)', cmd_input)
    tls_match = re.search(r'NZ_TLS=(true|false)', cmd_input)
    uuid_match = re.search(r'NZ_UUID=([^\s]+)', cmd_input)

    if not server_match or not secret_match:
        return None

    return {
        "server": server_match.group(1).strip('\'"'),
        "secret": secret_match.group(1).strip('\'"'),
        "tls": tls_match.group(1) if tls_match else "false",
        "uuid": uuid_match.group(1).strip('\'"') if uuid_match else None,
    }


def start_nezha(config: dict | None, use_old_config: bool) -> None:
    bin_file = "nezha-agent"

    if use_old_config:
        if os.path.exists(NEZHA_CONFIG_FILE):
            log(">>> [哪吒] 使用本地 nezha.yml 启动")
            subprocess.Popen([f"./{bin_file}", "-c", NEZHA_CONFIG_FILE], env=os.environ)
        else:
            log(">>> [哪吒] 未找到本地 nezha.yml，跳过启动")
        return

    if not config:
        log(">>> [哪吒] 未提供有效配置，跳过启动")
        return

    arch_code = get_arch_code()
    if not arch_code:
        log(f">>> [哪吒] 不支持当前架构: {platform.machine()}")
        return

    if os.path.exists(bin_file) or os.path.exists("nezha.zip"):
        run_command(f'rm -rf "{bin_file}" "nezha.zip"', shell=True)

    log(f">>> [哪吒] 正在下载适配 {arch_code} 的探针...")
    try:
        run_command(
            [
                "curl",
                "-L",
                "-o",
                "nezha.zip",
                f"https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_{arch_code}.zip",
            ],
            check=True,
        )
        run_command(["unzip", "-o", "nezha.zip"], check=True)
        run_command(["chmod", "+x", bin_file], check=True)
    except Exception as exc:
        log(f">>> [哪吒] 下载或解压失败: {exc}")
        return

    final_config = [
        f"server: {config['server']}",
        f"client_secret: {config['secret']}",
        f"tls: {config['tls']}",
    ]

    if config.get("uuid"):
        final_config.append(f"uuid: {config['uuid']}")
    elif os.path.exists(NEZHA_CONFIG_FILE):
        try:
            with open(NEZHA_CONFIG_FILE, "r", encoding="utf-8") as file:
                old_content = file.read()
            old_server_match = re.search(r"server:\s*(.*)", old_content)
            uuid_match = re.search(r"uuid:\s*(.*)", old_content)
            old_server = old_server_match.group(1).strip() if old_server_match else None
            old_uuid = uuid_match.group(1).strip() if uuid_match else None
            if old_server == config["server"] and old_uuid:
                final_config.append(f"uuid: {old_uuid}")
        except Exception:
            pass

    with open(NEZHA_CONFIG_FILE, "w", encoding="utf-8") as file:
        file.write("\n".join(final_config) + "\n")

    save_json(NEZHA_BACKUP_FILE, config)
    log(f">>> [哪吒] 配置已写入 {NEZHA_CONFIG_FILE}")

    try:
        subprocess.Popen([f"./{bin_file}", "-c", NEZHA_CONFIG_FILE], env=os.environ)
    except Exception as exc:
        log(f">>> [哪吒] 启动失败: {exc}")


def normalize_komari_args(cmd_input: str) -> str:
    if not cmd_input:
        return ""

    command = cmd_input.strip()
    if "bash -s --" in command:
        command = command.split("bash -s --", 1)[1].strip()
    elif "install.sh" in command:
        command = command.split("install.sh", 1)[1].strip()
    return command


def parse_komari_command(cmd_input: str):
    if not cmd_input:
        return None

    args = normalize_komari_args(cmd_input)
    if not args:
        return None

    endpoint_match = re.search(r'(?:--endpoint(?:=|\s+)|-e\s+)([^\s]+)', args)
    token_match = re.search(r'(?:--token(?:=|\s+)|-t\s+)([^\s]+)', args)
    auto_discovery = "--auto-discovery" in args

    endpoint = endpoint_match.group(1).strip('\'"') if endpoint_match else ""
    token = token_match.group(1).strip('\'"') if token_match else ""

    if not endpoint:
        return None
    if not token and not auto_discovery:
        return None

    return {
        "args": args,
        "endpoint": endpoint,
        "token": token,
        "auto_discovery": auto_discovery,
    }


def collect_probe_commands():
    log("----------------------------------------------------")
    log("                    探针配置中心                    ")
    log("----------------------------------------------------")
    log("支持一次性粘贴多条命令，脚本会逐行自动识别：")
    log("1. 包含 NZ_SERVER / NZ_CLIENT_SECRET -> 识别为哪吒")
    log("2. 包含 -e/--endpoint 和 -t/--token -> 识别为 Komari")
    log("3. 两个都要可直接连续粘贴两行")
    log(f"4. 首行等待 {TIMEOUT_SECONDS} 秒，后续空行或 1 秒无输入自动结束")
    log("----------------------------------------------------")

    lines = read_multiline_with_timeout("请输入探针命令 > ", TIMEOUT_SECONDS, 1)
    nezha_config = None
    komari_config = None

    if not lines:
        log(">>> [探针] 未输入任何命令，将尝试使用预设或本地配置")
        return nezha_config, komari_config

    for index, line in enumerate(lines, start=1):
        parsed_nezha = parse_nezha_command(line)
        if parsed_nezha:
            nezha_config = parsed_nezha
            log(f">>> [探针] 第 {index} 条已识别为哪吒命令")
            continue

        parsed_komari = parse_komari_command(line)
        if parsed_komari:
            komari_config = parsed_komari
            log(f">>> [探针] 第 {index} 条已识别为 Komari 命令")
            continue

        log(f">>> [探针] 第 {index} 条未识别，已忽略")

    return nezha_config, komari_config


def start_komari(config: dict | None, use_saved_args: bool) -> None:
    if use_saved_args:
        if not os.path.exists(KOMARI_ARGS_FILE):
            log(">>> [Komari] 未找到本地配置，跳过启动")
            return
        args = Path(KOMARI_ARGS_FILE).read_text(encoding="utf-8").strip()
        config = parse_komari_command(args)
        if not config:
            log(">>> [Komari] 本地参数格式无效，跳过启动")
            return

    if not config:
        log(">>> [Komari] 未提供有效配置，跳过启动")
        return

    Path(KOMARI_ARGS_FILE).write_text(config["args"] + "\n", encoding="utf-8")
    save_json(
        "komari_config.json",
        {
            "endpoint": config["endpoint"],
            "token": config["token"],
            "auto_discovery": config["auto_discovery"],
            "args": config["args"],
        },
    )

    arch_code = get_arch_code()
    if not arch_code:
        log(f">>> [Komari] 不支持当前架构: {platform.machine()}")
        return

    download_url = f"https://github.com/komari-monitor/komari-agent/releases/latest/download/komari-agent-linux-{arch_code}"

    if not os.path.exists(KOMARI_BINARY_FILE):
        log(f">>> [Komari] 正在下载 Komari Agent ({arch_code})...")
        try:
            run_command(["curl", "-fL", "-o", KOMARI_BINARY_FILE, download_url], check=True)
            os.chmod(KOMARI_BINARY_FILE, 0o755)
        except Exception as exc:
            log(f">>> [Komari] 下载 Komari Agent 失败: {exc}")
            return

    log(">>> [Komari] 正在后台启动 Komari Agent...")
    try:
        subprocess.Popen(f'./{KOMARI_BINARY_FILE} {config["args"]}', shell=True, env=os.environ)
    except Exception as exc:
        log(f">>> [Komari] 启动 Komari Agent 失败: {exc}")


def main() -> None:
    parse_and_load_env()
    os.system("cls" if os.name == "nt" else "clear")
    port_info = detect_container_port()

    log("====================================================")
    log("            Container-Script (Python)               ")
    log("====================================================")
    print_runtime_context(port_info)

    preset_nezha = parse_nezha_command(PRESET_NEZHA_COMMAND)
    backup_nezha = load_json_if_exists(NEZHA_BACKUP_FILE)
    preset_komari = parse_komari_command(PRESET_KOMARI_COMMAND)

    final_nezha_config = None
    use_old_nezha = False
    final_komari_config = None
    use_saved_komari = False

    external_nezha = parse_nezha_command(os.environ.get("NZ_CMD", ""))
    external_komari = parse_komari_command(os.environ.get("KOMARI_CMD", ""))

    if external_nezha:
        final_nezha_config = external_nezha
        log(">>> [哪吒] 检测到环境变量 NZ_CMD，将优先使用")
    if external_komari:
        final_komari_config = external_komari
        log(">>> [Komari] 检测到环境变量 KOMARI_CMD，将优先使用")

    if not external_nezha and not external_komari:
        collected_nezha, collected_komari = collect_probe_commands()
        if collected_nezha:
            final_nezha_config = collected_nezha
        if collected_komari:
            final_komari_config = collected_komari

    log("----------------------------------------------------")
    log("                    探针配置结果                    ")
    log("----------------------------------------------------")

    if final_nezha_config:
        log(">>> [哪吒] 使用已识别到的新命令")
    elif preset_nezha:
        final_nezha_config = preset_nezha
        log(">>> [哪吒] 使用脚本预设配置")
    elif backup_nezha:
        final_nezha_config = backup_nezha
        log(">>> [哪吒] 使用本地备份配置")
    elif os.path.exists(NEZHA_CONFIG_FILE):
        use_old_nezha = True
        log(">>> [哪吒] 使用本地 nezha.yml 启动")
    else:
        log(">>> [哪吒] 未检测到任何可用配置，将跳过启动")

    if final_komari_config:
        log(">>> [Komari] 使用已识别到的新命令")
    elif preset_komari:
        final_komari_config = preset_komari
        log(">>> [Komari] 使用脚本预设配置")
    elif os.path.exists(KOMARI_ARGS_FILE):
        use_saved_komari = True
        log(">>> [Komari] 使用本地 komari-agent.args 启动")
    else:
        log(">>> [Komari] 未检测到任何可用配置，将跳过启动")

    start_nezha(final_nezha_config, use_old_nezha)
    start_komari(final_komari_config, use_saved_komari)
    start_main_script()

    log(">>> [保活] 脚本进入保活模式...")
    while True:
        time.sleep(3600)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        log("\n>>> [退出] 用户终止脚本")
