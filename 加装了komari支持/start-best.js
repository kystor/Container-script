#!/usr/bin/env node

const fs = require("fs");
const path = require("path");
const os = require("os");
const https = require("https");
const readline = require("readline");
const { execSync, spawn, spawnSync } = require("child_process");

const SELF_URL = "https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.js";
const LOCAL_SCRIPT = path.join(os.homedir(), "start.js");

const PRESET_NEZHA_COMMAND = "";
const PRESET_KOMARI_COMMAND = "";
const CUSTOM_VARIABLES_STR = 'hypt=""';

const TIMEOUT_SECONDS = 20;
const NEZHA_CONFIG_FILE = "nezha.yml";
const KOMARI_ARGS_FILE = "komari-agent.args";
const KOMARI_BINARY_FILE = "komari-agent";
const ARGOSBX_FILE = "argosbx.sh";
const ARGOSBX_URL = "https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh";

const log = {
  info: (msg) => console.log(msg),
  warn: (msg) => console.log(msg),
  err: (msg) => console.error(msg),
};

function commandExists(cmd) {
  try {
    execSync(`command -v ${cmd}`, { stdio: "ignore" });
    return true;
  } catch {
    return false;
  }
}

function downloadFileSilent(url, dest) {
  return new Promise((resolve, reject) => {
    const file = fs.createWriteStream(dest);
    https
      .get(url, (response) => {
        if (response.statusCode === 301 || response.statusCode === 302) {
          downloadFileSilent(response.headers.location, dest).then(resolve).catch(reject);
          return;
        }
        response.pipe(file);
        file.on("finish", () => file.close(() => resolve(dest)));
      })
      .on("error", (error) => {
        fs.unlink(dest, () => reject(error));
      });
  });
}

function runDetached(command, args) {
  const child = spawn(command, args, {
    detached: true,
    stdio: "inherit",
    env: process.env,
  });
  child.unref();
}

function askQuestion(query, timeoutMs = 0) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    let timer = null;
    if (timeoutMs > 0) {
      timer = setTimeout(() => {
        rl.close();
        resolve("");
      }, timeoutMs);
    }

    rl.question(query, (answer) => {
      if (timer) {
        clearTimeout(timer);
      }
      rl.close();
      resolve(answer.trim());
    });
  });
}

function readLineWithTimeout(timeoutMs) {
  return new Promise((resolve) => {
    const rl = readline.createInterface({
      input: process.stdin,
      output: process.stdout,
    });

    let timer = null;
    if (timeoutMs > 0) {
      timer = setTimeout(() => {
        rl.close();
        resolve(null);
      }, timeoutMs);
    }

    rl.once("line", (line) => {
      if (timer) {
        clearTimeout(timer);
      }
      rl.close();
      resolve(line);
    });
  });
}

async function readMultilineCommands(firstTimeoutMs, nextTimeoutMs = 1000) {
  const lines = [];
  const firstLine = await askQuestion("请输入探针命令 > ", firstTimeoutMs);
  if (!firstLine) {
    return lines;
  }

  lines.push(firstLine);
  while (true) {
    const nextLine = await readLineWithTimeout(nextTimeoutMs);
    if (nextLine === null || !nextLine.trim()) {
      break;
    }
    lines.push(nextLine.trim());
  }
  return lines;
}

function parseCustomVariables() {
  if (!CUSTOM_VARIABLES_STR) {
    return;
  }

  CUSTOM_VARIABLES_STR.split(" ").forEach((kv) => {
    const [key, val] = kv.split("=");
    if (key && typeof val !== "undefined") {
      process.env[key] = val.replace(/["']/g, "");
    }
  });
}

function isValidPort(value) {
  return /^\d+$/.test(value) && Number(value) >= 1 && Number(value) <= 65535;
}

function detectContainerPort() {
  const candidateVars = [
    "SERVER_PORT",
    "PORT",
    "PANEL_PORT",
    "LISTEN_PORT",
    "APP_PORT",
    "WEB_PORT",
    "CONTAINER_PORT",
    "INTERNAL_PORT",
  ];

  let detectedPort = "";
  let detectedSource = "";
  for (const varName of candidateVars) {
    const candidate = (process.env[varName] || "").trim();
    if (isValidPort(candidate)) {
      detectedPort = candidate;
      detectedSource = varName;
      break;
    }
  }

  if (!detectedPort) {
    log.warn(">>> [端口] 未检测到容器平台分配端口，将继续使用各模块默认端口");
    return;
  }

  process.env.CONTAINER_PORT = detectedPort;
  if (!process.env.PORT) process.env.PORT = detectedPort;
  if (!process.env.SERVER_PORT) process.env.SERVER_PORT = detectedPort;
  if (!process.env.INTERNAL_PORT) process.env.INTERNAL_PORT = detectedPort;
  if (!process.env.PANEL_PORT) process.env.PANEL_PORT = detectedPort;
  if (!process.env.hypt) process.env.hypt = detectedPort;

  log.info(`>>> [端口] 已检测到容器端口: ${detectedPort} (来源: ${detectedSource})`);
  log.info(">>> [端口] 已导出 SERVER_PORT/PORT/CONTAINER_PORT/INTERNAL_PORT");
}

function unzipFile(zipFile, mode) {
  if (mode === "unzip") {
    execSync(`unzip -o "${zipFile}"`, { stdio: "inherit" });
  } else if (mode === "jar") {
    execSync(`jar xf "${zipFile}"`, { stdio: "inherit" });
  }
}

function checkDependencies() {
  process.env.PATH = `${process.env.PATH}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`;
  if (commandExists("unzip")) {
    return "unzip";
  }
  if (commandExists("jar")) {
    return "jar";
  }
  return null;
}

async function setupPersistence() {
  try {
    await downloadFileSilent(SELF_URL, LOCAL_SCRIPT);
    fs.chmodSync(LOCAL_SCRIPT, 0o755);
  } catch {}

  if (!commandExists("crontab")) {
    return;
  }

  const cronCmd = `@reboot ${process.execPath} "${LOCAL_SCRIPT}" >/dev/null 2>&1 &`;
  let currentCron = "";
  try {
    currentCron = execSync("crontab -l", { stdio: ["pipe", "pipe", "ignore"] }).toString();
  } catch {}

  if (!currentCron.includes(LOCAL_SCRIPT)) {
    const child = spawn("crontab", ["-"]);
    child.stdin.write(`${currentCron}\n${cronCmd}\n`);
    child.stdin.end();
  }
}

function parseNezhaCommand(cmdStr) {
  if (!cmdStr) {
    return null;
  }

  const server = (cmdStr.match(/NZ_SERVER=([^\s]+)/) || [])[1] || "";
  const secret = (cmdStr.match(/NZ_CLIENT_SECRET=([^\s]+)/) || [])[1] || "";
  const tls = (cmdStr.match(/NZ_TLS=(true|false)/) || [])[1] || "false";
  const uuid = (cmdStr.match(/NZ_UUID=([^\s]+)/) || [])[1] || null;

  if (!server || !secret) {
    return null;
  }

  return {
    server: server.replace(/["']/g, ""),
    secret: secret.replace(/["']/g, ""),
    tls,
    uuid: uuid ? uuid.replace(/["']/g, "") : null,
  };
}

function getArchCode() {
  const arch = os.arch();
  if (arch === "x64") return "amd64";
  if (arch === "arm64") return "arm64";
  if (arch === "arm") return "arm";
  if (arch === "ia32") return "386";
  return "";
}

function startNezha(config, unzipMode, useOldConfig) {
  const binFile = "nezha-agent";

  if (useOldConfig) {
    if (fs.existsSync(NEZHA_CONFIG_FILE)) {
      log.info(">>> [哪吒] 使用本地 nezha.yml 启动");
      runDetached(`./${binFile}`, ["-c", NEZHA_CONFIG_FILE]);
    }
    return;
  }

  if (!config) {
    log.warn(">>> [哪吒] 未提供有效配置，跳过启动");
    return;
  }

  const archCode = getArchCode();
  if (!archCode) {
    log.err(`>>> [哪吒] 不支持当前架构: ${os.arch()}`);
    return;
  }

  if (!fs.existsSync(binFile)) {
    log.info(`>>> [哪吒] 正在下载适配 ${archCode} 的探针...`);
    try {
      execSync(
        `curl -L -o nezha.zip https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${archCode}.zip`,
        { stdio: "inherit" }
      );
      unzipFile("nezha.zip", unzipMode);
      fs.chmodSync(binFile, 0o755);
      if (fs.existsSync("nezha.zip")) {
        fs.unlinkSync("nezha.zip");
      }
    } catch (error) {
      log.err(`>>> [哪吒] 下载失败: ${error.message}`);
      return;
    }
  }

  let configContent = `server: ${config.server}\nclient_secret: ${config.secret}\ntls: ${config.tls}\n`;
  if (config.uuid) {
    configContent += `uuid: ${config.uuid}\n`;
  } else if (fs.existsSync(NEZHA_CONFIG_FILE)) {
    try {
      const oldContent = fs.readFileSync(NEZHA_CONFIG_FILE, "utf8");
      const oldServer = (oldContent.match(/server:\s*(.*)/) || [])[1] || "";
      const oldUuid = (oldContent.match(/uuid:\s*(.*)/) || [])[1] || "";
      if (oldServer.trim() === config.server && oldUuid.trim()) {
        configContent += `uuid: ${oldUuid.trim()}\n`;
      }
    } catch {}
  }

  fs.writeFileSync(NEZHA_CONFIG_FILE, configContent);
  fs.writeFileSync("nezha_config.json", JSON.stringify(config, null, 2));
  runDetached(`./${binFile}`, ["-c", NEZHA_CONFIG_FILE]);
}

function normalizeKomariArgs(cmdStr) {
  if (!cmdStr) {
    return "";
  }

  let args = cmdStr.trim();
  if (args.includes("bash -s --")) {
    args = args.split("bash -s --")[1].trim();
  } else if (args.includes("install.sh")) {
    args = args.split("install.sh")[1].trim();
  }
  return args;
}

function parseKomariCommand(cmdStr) {
  if (!cmdStr) {
    return null;
  }

  const args = normalizeKomariArgs(cmdStr);
  if (!args) {
    return null;
  }

  const endpointMatch = args.match(/(?:--endpoint(?:=|\s+)|-e\s+)([^\s]+)/);
  const tokenMatch = args.match(/(?:--token(?:=|\s+)|-t\s+)([^\s]+)/);
  const autoDiscovery = args.includes("--auto-discovery");

  const endpoint = endpointMatch ? endpointMatch[1].replace(/["']/g, "") : "";
  const token = tokenMatch ? tokenMatch[1].replace(/["']/g, "") : "";

  if (!endpoint) {
    return null;
  }
  if (!token && !autoDiscovery) {
    return null;
  }

  return {
    args,
    endpoint,
    token,
    autoDiscovery,
  };
}

async function collectProbeCommands() {
  console.log("----------------------------------------------------");
  console.log("                    探针配置中心                    ");
  console.log("----------------------------------------------------");
  console.log("支持一次性粘贴多条命令，脚本会逐行自动识别：");
  console.log("1. 包含 NZ_SERVER / NZ_CLIENT_SECRET -> 识别为哪吒");
  console.log("2. 包含 -e/--endpoint 和 -t/--token -> 识别为 Komari");
  console.log("3. 两个都要可直接连续粘贴两行");
  console.log(`4. 首行等待 ${TIMEOUT_SECONDS} 秒，后续空行或 1 秒无输入自动结束`);
  console.log("----------------------------------------------------");

  const lines = await readMultilineCommands(TIMEOUT_SECONDS * 1000, 1000);
  let nezhaConfig = null;
  let komariConfig = null;

  if (!lines.length) {
    log.info(">>> [探针] 未输入任何命令，将尝试使用预设或本地配置");
    return { nezhaConfig, komariConfig };
  }

  lines.forEach((line, index) => {
    const parsedNezha = parseNezhaCommand(line);
    if (parsedNezha) {
      nezhaConfig = parsedNezha;
      log.info(`>>> [探针] 第 ${index + 1} 条已识别为哪吒命令`);
      return;
    }

    const parsedKomari = parseKomariCommand(line);
    if (parsedKomari) {
      komariConfig = parsedKomari;
      log.info(`>>> [探针] 第 ${index + 1} 条已识别为 Komari 命令`);
      return;
    }

    log.warn(`>>> [探针] 第 ${index + 1} 条未识别，已忽略`);
  });

  return { nezhaConfig, komariConfig };
}

function startKomari(config, useSavedArgs) {
  let finalConfig = config;

  if (useSavedArgs) {
    if (!fs.existsSync(KOMARI_ARGS_FILE)) {
      log.warn(">>> [Komari] 未找到本地参数，跳过启动");
      return;
    }
    finalConfig = parseKomariCommand(fs.readFileSync(KOMARI_ARGS_FILE, "utf8").trim());
  }

  if (!finalConfig) {
    log.warn(">>> [Komari] 未提供有效配置，跳过启动");
    return;
  }

  fs.writeFileSync(KOMARI_ARGS_FILE, `${finalConfig.args}\n`);
  fs.writeFileSync(
    "komari_config.json",
    JSON.stringify(
      {
        endpoint: finalConfig.endpoint,
        token: finalConfig.token,
        autoDiscovery: finalConfig.autoDiscovery,
        args: finalConfig.args,
      },
      null,
      2
    )
  );

  const archCode = getArchCode();
  if (!archCode) {
    log.err(`>>> [Komari] 不支持当前架构: ${os.arch()}`);
    return;
  }

  const downloadUrl = `https://github.com/komari-monitor/komari-agent/releases/latest/download/komari-agent-linux-${archCode}`;

  if (!fs.existsSync(KOMARI_BINARY_FILE)) {
    try {
      execSync(`curl -fL -o ${KOMARI_BINARY_FILE} ${downloadUrl}`, { stdio: "inherit" });
      fs.chmodSync(KOMARI_BINARY_FILE, 0o755);
    } catch (error) {
      log.err(`>>> [Komari] 下载 Komari Agent 失败: ${error.message}`);
      return;
    }
  }

  runDetached("sh", ["-c", `"$PWD/${KOMARI_BINARY_FILE}" ${finalConfig.args}`]);
}

function ensureArgosbx() {
  if (fs.existsSync(ARGOSBX_FILE)) {
    return;
  }
  execSync(`curl -L -o ${ARGOSBX_FILE} ${ARGOSBX_URL}`, { stdio: "inherit" });
  fs.chmodSync(ARGOSBX_FILE, 0o755);
}

function startArgosbx() {
  log.info(">>> [主程序] 正在启动 Argosbx ...");
  ensureArgosbx();
  runDetached("bash", [`./${ARGOSBX_FILE}`, "rep"]);
}

async function main() {
  console.clear();
  parseCustomVariables();
  detectContainerPort();
  const unzipMode = checkDependencies();
  await setupPersistence();

  let finalNezhaConfig = null;
  let useOldNezha = false;
  let finalKomariConfig = null;
  let useSavedKomari = false;

  const externalNezha = parseNezhaCommand(process.env.NZ_CMD || "");
  const externalKomari = parseKomariCommand(process.env.KOMARI_CMD || "");
  const presetNezha = parseNezhaCommand(PRESET_NEZHA_COMMAND);
  const presetKomari = parseKomariCommand(PRESET_KOMARI_COMMAND);
  let backupNezha = null;

  if (fs.existsSync("nezha_config.json")) {
    try {
      backupNezha = JSON.parse(fs.readFileSync("nezha_config.json", "utf8"));
    } catch {}
  }

  if (externalNezha) {
    finalNezhaConfig = externalNezha;
    log.info(">>> [哪吒] 检测到环境变量 NZ_CMD，将优先使用");
  }

  if (externalKomari) {
    finalKomariConfig = externalKomari;
    log.info(">>> [Komari] 检测到环境变量 KOMARI_CMD，将优先使用");
  }

  if (!externalNezha && !externalKomari) {
    const collected = await collectProbeCommands();
    if (collected.nezhaConfig) {
      finalNezhaConfig = collected.nezhaConfig;
    }
    if (collected.komariConfig) {
      finalKomariConfig = collected.komariConfig;
    }
  }

  console.log("----------------------------------------------------");
  console.log("                    探针配置结果                    ");
  console.log("----------------------------------------------------");

  if (finalNezhaConfig) {
    log.info(">>> [哪吒] 使用已识别到的新命令");
  } else if (presetNezha) {
    finalNezhaConfig = presetNezha;
    log.info(">>> [哪吒] 使用脚本预设配置");
  } else if (backupNezha) {
    finalNezhaConfig = backupNezha;
    log.info(">>> [哪吒] 使用本地备份配置");
  } else if (fs.existsSync(NEZHA_CONFIG_FILE)) {
    useOldNezha = true;
    log.info(">>> [哪吒] 使用本地 nezha.yml 启动");
  } else {
    log.info(">>> [哪吒] 未检测到任何可用配置，将跳过启动");
  }

  if (finalKomariConfig) {
    log.info(">>> [Komari] 使用已识别到的新命令");
  } else if (presetKomari) {
    finalKomariConfig = presetKomari;
    log.info(">>> [Komari] 使用脚本预设配置");
  } else if (fs.existsSync(KOMARI_ARGS_FILE)) {
    useSavedKomari = true;
    log.info(">>> [Komari] 使用本地 komari-agent.args 启动");
  } else {
    log.info(">>> [Komari] 未检测到任何可用配置，将跳过启动");
  }

  startNezha(finalNezhaConfig, unzipMode, useOldNezha);
  startKomari(finalKomariConfig, useSavedKomari);
  startArgosbx();

  log.info(">>> [保活] 脚本进入保活模式...");
  setInterval(() => {}, 3600 * 1000);
}

main().catch((error) => {
  console.error("运行出错:", error);
});
