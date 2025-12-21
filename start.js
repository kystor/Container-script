#!/usr/bin/env node

/**
 * ==========================================
 * 🟢 Container-Script Node.js 完整版
 * ==========================================
 * 功能：
 * 1. 环境自检 (支持 unzip 和 Java 解压)
 * 2. 自动加载自定义环境变量
 * 3. 哪吒探针安装与启动
 * 4. Argosbx 业务启动
 * 5. 开机自启保活
 * * 特别说明：
 * - 代码中使用了 spawn + inherit 模式，确保所有子进程的日志都能直接显示，不会被屏蔽。
 * - 适合新手阅读，包含详细中文注解。
 */

const fs = require('fs');           // 文件系统模块：用于读写文件
const path = require('path');       // 路径模块：处理文件路径
const { execSync, spawn } = require('child_process'); // 子进程模块：用于运行外部命令
const https = require('https');     // 网络模块：用于下载文件
const os = require('os');           // 系统模块：获取系统信息（如架构、主目录）
const readline = require('readline'); // 读取输入模块：用于获取用户输入

// ==========================================
// 🟢 配置区域 (在此修改你的设置)
// ==========================================

// 1. 脚本自身的下载地址 (用于更新和自启时的拉取)
const SELF_URL = "https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.js";

// 2. 本地保存的文件名 (保存到当前用户的主目录下)
const LOCAL_SCRIPT = path.join(os.homedir(), "start.js");

// 3. 哪吒探针默认配置 (如果你想把指令写死在脚本里，填在这里)
// 格式如: "NZ_SERVER=... NZ_CLIENT_SECRET=..."
const PRESET_NEZHA_COMMAND = "";

// 4. 自定义环境变量 (对应原脚本的 CUSTOM_VARIABLES)
// 【新手提示】：在这里填入你需要预设的变量。
// 格式为: "变量名": "值" (记得用双引号包起来，中间用冒号，行尾用逗号)
const CUSTOM_VARIABLES = {
    // 示例 (请取消注释并修改你需要的部分):
    // "hypt": "你的UUID或参数",
    // "ANOTHER_VAR": "123456"
};

// ==========================================
// 🛠️ 工具函数库 (新手可学习此处封装)
// ==========================================

/**
 * 颜色输出辅助对象，让控制台日志更好看
 * 使用方法: log.info("消息内容")
 */
const log = {
    info: (msg) => console.log(`\x1b[32m>>> [系统] ${msg}\x1b[0m`), // 绿色：正常信息
    warn: (msg) => console.log(`\x1b[33m>>> [警告] ${msg}\x1b[0m`), // 黄色：警告
    err: (msg) => console.log(`\x1b[31m>>> [错误] ${msg}\x1b[0m`),  // 红色：错误
    step: (msg) => console.log(`\x1b[36m>>> [步骤] ${msg}\x1b[0m`), // 青色：步骤提示
};

/**
 * 检查某个命令是否存在
 * 原理：执行 'command -v cmd'，如果不报错说明存在
 */
function commandExists(cmd) {
    try {
        // stdio: 'ignore' 表示我们不需要看它的输出，只需要知道它成不成功
        execSync(`command -v ${cmd}`, { stdio: 'ignore' });
        return true;
    } catch (e) {
        return false;
    }
}

/**
 * 下载文件函数 (使用原生 https，不依赖第三方库)
 * @param {string} url - 下载链接
 * @param {string} dest - 保存路径
 */
function downloadFile(url, dest) {
    return new Promise((resolve, reject) => {
        const file = fs.createWriteStream(dest); // 创建一个写入流
        https.get(url, (response) => {
            // 处理 GitHub 等网站的 302/301 重定向
            if (response.statusCode === 302 || response.statusCode === 301) {
                downloadFile(response.headers.location, dest).then(resolve).catch(reject);
                return;
            }
            response.pipe(file); // 把下载的数据“管道”传输到文件里
            file.on('finish', () => {
                file.close(() => resolve(dest)); // 下载完成，关闭文件
            });
        }).on('error', (err) => {
            fs.unlink(dest, () => reject(err)); // 出错时删除损坏的文件
        });
    });
}

/**
 * 核心运行函数：运行命令并实时输出日志
 * @param {string} command - 命令 (如 bash, ./nezha-agent)
 * @param {Array} args - 参数数组 (如 ['argosbx.sh', 'rep'])
 * @param {boolean} detach - 是否后台运行 (true=后台, false=等待执行完)
 */
function runCommand(command, args, detach = false) {
    // 【关键】：stdio: 'inherit' 让子进程直接使用主进程的屏幕
    // 这样你就绝对不会错过任何报错信息
    const options = { stdio: 'inherit', shell: true };
    
    if (detach) {
        options.detached = true; // 允许脱离父进程
        // 后台运行时，通常为了防止卡住，可以忽略输入，但保留输出会更好调试
        // 这里为了保险，后台进程我们也让它尽量能输出
    }

    const child = spawn(command, args, options);

    if (detach) {
        child.unref(); // 让父进程（此脚本）可以退出，而不用等待子进程
    }
    return child;
}

// ==========================================
// 🟢 模块 0：环境自检 (对应 check_dependencies)
// ==========================================
function checkDependencies() {
    log.info("正在检查环境依赖...");
    
    // 设置环境变量 PATH，确保能找到常用命令
    process.env.PATH = `${process.env.PATH}:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`;

    // 1. 检测 unzip
    if (commandExists('unzip')) {
        log.info("✅ 系统已有 unzip。");
        return 'unzip'; // 返回模式名称
    } 
    
    log.warn("系统未安装 unzip，尝试检测 Java...");

    // 2. 检测 Java (jar)
    if (commandExists('jar')) {
        log.info("✅ 检测到 Java，将使用 jar 命令代替 unzip。");
        return 'jar';
    }

    // 3. 都没有
    log.err("❌ 未找到 unzip 且未找到 Java，后续解压步骤可能失败！");
    log.info("提示：请在容器外部手动安装 unzip。");
    return null;
}

// 解压逻辑封装：根据环境自动选择工具
function unzipFile(zipFile, mode) {
    if (mode === 'unzip') {
        // -o 覆盖不提示
        log.step(`[Unzip] 正在解压: ${zipFile}`);
        execSync(`unzip -o "${zipFile}"`, { stdio: 'inherit' });
    } else if (mode === 'jar') {
        log.step(`[Java] 正在使用 jar 解压: ${zipFile}`);
        // jar xf 文件名
        execSync(`jar xf "${zipFile}"`, { stdio: 'inherit' });
    } else {
        log.err("无法解压：缺乏工具。");
    }
}

// ==========================================
// 0. 🔌 自我安装与开机自启模块
// ==========================================
async function setupPersistence() {
    log.step("正在检查脚本完整性与开机自启...");

    // 1. 下载最新版脚本 (自我更新)
    try {
        await downloadFile(SELF_URL, LOCAL_SCRIPT);
        fs.chmodSync(LOCAL_SCRIPT, '755'); // 赋予 755 可执行权限
    } catch (e) {
        log.warn("脚本自我更新失败 (可能是网络问题)，将使用当前版本继续。");
    }

    // 2. 设置 Crontab (开机自启)
    // 构造 Cron 命令: @reboot /path/to/node /path/to/script.js
    const nodeBin = process.execPath; // 获取当前 node 程序的绝对路径
    const cronCmd = `@reboot ${nodeBin} "${LOCAL_SCRIPT}" >/dev/null 2>&1 &`;

    try {
        // 读取现有 crontab
        let currentCron = "";
        try {
            currentCron = execSync('crontab -l', { stdio: ['pipe', 'pipe', 'ignore'] }).toString();
        } catch (e) {
            // 如果 crontab 为空或不存在，忽略错误
        }

        if (currentCron.includes(LOCAL_SCRIPT)) {
            log.info("✅ 开机自启任务已存在，跳过。");
        } else {
            // 写入新的 crontab
            const newCron = `${currentCron}\n${cronCmd}\n`;
            // 使用子进程将字符串写入 crontab
            const child = spawn('crontab', ['-']);
            child.stdin.write(newCron);
            child.stdin.end();
            log.info("✅ 成功添加开机自启任务！");
        }
    } catch (e) {
        log.warn("⚠️ 无法设置 crontab (可能无权限或未安装)，跳过自启。");
    }
}

// ==========================================
// 1. 🛡️ 哪吒探针逻辑模块
// ==========================================
async function startNezha(cmdStr, unzipMode) {
    const binFile = "nezha-agent";
    const configFile = "nezha.yml";

    // 逻辑 A: 如果没有传入指令，检查本地是否有配置
    if (!cmdStr) {
        if (fs.existsSync(configFile)) {
            log.info("✅ 检测到现有的配置文件，直接启动探针...");
            // 后台启动，保留输出
            runCommand(`./${binFile}`, ['-c', configFile], true);
            return;
        } else {
            log.warn("⚠️ 未提供配置且无本地配置文件，跳过哪吒启动。");
            return;
        }
    }

    log.step("正在解析指令并更新配置...");

    // 解析参数 (简单正则提取)
    const getServer = (str) => (str.match(/NZ_SERVER=([^ ]+)/) || [])[1] || "";
    const getSecret = (str) => (str.match(/NZ_CLIENT_SECRET=([^ ]+)/) || [])[1] || "";
    const getTls = (str) => (str.match(/NZ_TLS=([^ ]+)/) || [])[1] || "false";

    const server = getServer(cmdStr);
    const secret = getSecret(cmdStr);
    const tls = getTls(cmdStr);

    if (!server || !secret) {
        log.err("无法解析 Server 或 Secret，请检查指令格式。");
        return;
    }

    // 下载对应架构的文件
    if (!fs.existsSync(binFile)) {
        let arch = os.arch(); // x64, arm64, etc.
        let archCode = "amd64"; // 默认为 amd64
        if (arch === 'arm64' || arch === 'aarch64') archCode = "arm64";
        
        log.info(`正在下载哪吒探针 (${archCode})...`);
        const downloadUrl = `https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${archCode}.zip`;
        
        try {
            await downloadFile(downloadUrl, 'nezha.zip');
            // 调用之前定义的解压函数
            unzipFile('nezha.zip', unzipMode);
            fs.chmodSync(binFile, '755');
            fs.unlinkSync('nezha.zip'); // 删除压缩包
        } catch (e) {
            log.err(`下载或解压失败: ${e.message}`);
            return;
        }
    }

    // 生成配置文件 nezha.yml
    const configContent = `server: ${server}\nclient_secret: ${secret}\ntls: ${tls}\n`;
    fs.writeFileSync(configFile, configContent);
    log.info("配置文件 nezha.yml 已重新生成。");

    log.step("🚀 拉起 Nezha Agent...");
    // 后台运行，不阻塞主线程
    runCommand(`./${binFile}`, ['-c', configFile], true);
}

// ==========================================
// 2. 🚀 主业务逻辑 (Argosbx)
// ==========================================
async function startArgosbx() {
    console.log("");
    console.log("====================================================");
    log.step("准备启动 Argosbx 业务");
    console.log("====================================================");

    // 检查是否有预设变量 hypt 或 AUTO_RUN
    let skipInput = false;
    if (process.env.hypt) {
        log.info(`✅ 检测到环境变量 hypt = ${process.env.hypt}`);
        skipInput = true;
    }
    if (process.env.AUTO_RUN === 'true') {
        log.info("✅ 检测到 AUTO_RUN 标记，跳过手动输入。");
        skipInput = true;
    }

    // 处理用户输入 (如果没检测到变量)
    if (!skipInput) {
        console.log("请输入 Argosbx 需要的环境变量 (例如: hypt=\"1234\")");
        console.log("提示：如果有多个变量，请用空格隔开；直接回车则跳过。");
        
        const rl = readline.createInterface({
            input: process.stdin,
            output: process.stdout
        });

        // 包装 readline 为 Promise 以使用 await，并添加超时
        const askQuestion = () => new Promise((resolve) => {
            const timer = setTimeout(() => {
                log.info("未检测到输入或超时，使用默认环境。");
                rl.close();
                resolve("");
            }, 20000); // 20秒超时

            rl.question("请输入变量 > ", (answer) => {
                clearTimeout(timer);
                rl.close();
                resolve(answer);
            });
        });

        const userEnv = await askQuestion();
        if (userEnv) {
            log.info("检测到手动输入变量，正在应用...");
            // 简单解析用户输入的 export A="B"
            const envs = userEnv.replace(/export /g, '').split(' ');
            envs.forEach(kv => {
                const [key, val] = kv.split('=');
                if (key && val) {
                    // 去除引号并设置到环境变量
                    process.env[key] = val.replace(/["']/g, ''); 
                }
            });
        }
    }

    const scriptName = "argosbx.sh";
    const scriptUrl = "https://raw.githubusercontent.com/yonggekkk/argosbx/main/argosbx.sh";

    // 下载脚本逻辑
    if (fs.existsSync(scriptName)) {
        // 文件存在，静默跳过
    } else {
        log.info("本地未找到脚本，正在下载 Argosbx...");
        await downloadFile(scriptUrl, scriptName);
        fs.chmodSync(scriptName, '755');
    }

    log.step("正在运行 Argosbx (模式: rep)...");
    
    // [关键]：使用 'rep' 参数强制显示信息
    // stdio: 'inherit' 确保输出直接打印到屏幕，不被吞掉
    runCommand('bash', [scriptName, 'rep']);
}

// ==========================================
// 🏁 主函数 (Main) - 程序的入口
// ==========================================
async function main() {
    // 清屏
    console.clear();
    console.log("====================================================");
    console.log("                 Container-Script (Node.js)         ");
    console.log("====================================================");

    // 🟢 1. 加载自定义环境变量 (从配置区读取)
    // Object.entries 会把对象变成数组，如 [['hypt', '123'], ['Key', 'Val']]
    if (Object.keys(CUSTOM_VARIABLES).length > 0) {
        log.info("正在加载脚本内部预设变量...");
        for (const [key, value] of Object.entries(CUSTOM_VARIABLES)) {
            process.env[key] = value; // 这行代码等同于 export KEY=VALUE
            console.log(` -> [环境] 已设置: ${key}=${value}`);
        }
    }

    // 🟢 2. 检查解压工具 (unzip 或 jar)
    const unzipMode = checkDependencies();

    // 🟢 3. 自我安装/自启配置
    await setupPersistence();

    // 🟢 4. 处理哪吒指令输入
    // 优先级：NZ_CMD > 手动输入 > 配置文件 > 脚本预设
    let nezhaCmdSource = process.env.NZ_CMD || "";
    let timeoutSeconds = nezhaCmdSource ? 1 : 20; // 外部有变量就快点跳过，没有就等20秒

    // 如果没有外部命令，也没有本地配置文件，也没预设，才提示用户输入
    if (!nezhaCmdSource && !fs.existsSync("nezha.yml") && !PRESET_NEZHA_COMMAND) {
        console.log("----------------------------------------------------");
        console.log(`请配置【哪吒探针】(${timeoutSeconds} 秒倒计时):`);
        console.log("1. [输入] 粘贴新指令并回车");
        console.log("2. [回车] 使用脚本预设或跳过");
        console.log("----------------------------------------------------");

        const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
        
        // 封装输入等待逻辑
        const getUserInput = () => new Promise((resolve) => {
            const timer = setTimeout(() => {
                rl.close();
                resolve("");
            }, timeoutSeconds * 1000);

            rl.question("请输入哪吒指令 > ", (ans) => {
                clearTimeout(timer);
                rl.close();
                resolve(ans);
            });
        });

        const userInput = await getUserInput();
        if (userInput) {
            nezhaCmdSource = userInput;
            log.info("使用手动输入配置。");
        }
    } else if (process.env.NZ_CMD) {
        log.info("检测到外部 NZ_CMD，优先使用。");
    }

    // 如果还是空的，尝试使用脚本预设
    if (!nezhaCmdSource && PRESET_NEZHA_COMMAND) {
        nezhaCmdSource = PRESET_NEZHA_COMMAND;
        log.info("使用脚本预设配置。");
    }
    
    // 启动哪吒 (传入指令和解压模式)
    await startNezha(nezhaCmdSource, unzipMode);

    // 🟢 5. 启动 Argosbx 业务
    await startArgosbx();

    // 🟢 6. 保活逻辑 (Keep-Alive)
    console.log("");
    log.step("正在启动后台保活进程 (Keep-Alive)...");
    
    // Node.js 的保活非常简单，设置一个无限循环的定时器
    // 只要有定时器在跑，Node 进程就不会退出
    setInterval(() => {
        // 可以在这里打印心跳，也可以留空保持静默
    }, 3600 * 1000); // 每小时触发一次

    log.info("✅ 所有任务已触发，脚本进入守护模式。");
}

// 执行主函数，并捕获全局错误
main().catch(err => {
    console.error("脚本运行出错:", err);
});
