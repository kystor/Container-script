const { spawn, execSync } = require('child_process');
const readline = require('readline');
const fs = require('fs');
const path = require('path');

// ==========================================
// 🛠️ 全局配置区
// ==========================================

// [优先级 2] (代码预设) 如果你有哪吒指令需求，请在双引号中输入哪吒指令
const PRESET_NEZHA_COMMAND = ""; 

// 🟢 【修改处】：在这里填入你的环境变量字符串
// 格式要求：变量名="值"，多个变量用空格隔开
const CUSTOM_ENV_INPUT = 'hypt=""'; 

// 🟢 【环境解析模块】：自动解析上面的 CUSTOM_ENV_INPUT 并注入系统
(function parseAndLoadEnv() {
    if (!CUSTOM_ENV_INPUT) return;
    console.log('\n>>> [环境] 正在加载自定义变量...');
    
    // 正则提取 变量名=值 (支持带双引号或不带引号的值)
    const regex = /(\w+)=(?:"([^"]*)"|(\S+))/g;
    let match;
    
    while ((match = regex.exec(CUSTOM_ENV_INPUT)) !== null) {
        const key = match[1];
        const value = match[2] || match[3];
        process.env[key] = value; 
        console.log(`    + 成功设置: ${key} = ${value}`);
    }
    console.log('>>> [环境] 加载完毕。\n');
})();


const TIMEOUT_SECONDS = 20;       // 倒计时等待时间 (秒)
const CONFIG_FILE_YAML = 'nezha.yml';     // 探针配置文件名
const BACKUP_FILE = 'nezha_config.json';  // 配置备份文件名

// ==========================================
// 1. 🚀 启动主业务 (Argosbx)
// ==========================================
function startMainScript() {
    console.log('\n====================================================');
    console.log('>>> [主程序] 正在启动主业务脚本 (argosbx.sh) ...');
    console.log('====================================================');
    
    if (!fs.existsSync('./argosbx.sh')) {
        console.error('>>> [错误] 找不到 argosbx.sh 文件，请检查是否上传！');
        return;
    }

    // 给予脚本执行权限
    try { execSync('chmod +x ./argosbx.sh'); } catch(e) {}

    // 启动 bash 脚本，继承当前的环境变量 (process.env)
    const shProcess = spawn('bash', ['./argosbx.sh'], {
        stdio: 'inherit', 
        env: process.env  
    });

    shProcess.on('exit', (code) => {
        console.log(`\n[注意] argosbx.sh 已退出 (代码: ${code})`);
        console.log('>>> 脚本进入无限保活模式，防止容器退出...');
    });
}

// ==========================================
// 2. 🛡️ 哪吒探针安装与启动逻辑 (精准修复版)
// ==========================================
function startNezha(server, secret, tls, forceUUID) {
    if (!server || !secret) {
        console.log('>>> [跳过] 缺少探针参数，不启动哪吒探针。');
        return;
    }

    console.log(`\n>>> [探针] 准备启动哪吒探针...`);
    console.log(`    服务器: ${server}`);
    console.log(`    TLS: ${tls}`);
    if (forceUUID) console.log(`    UUID: ${forceUUID} (强制指定)`);

    // --- 下载部分 ---
    let archCode = process.arch === 'x64' ? 'amd64' : 'arm64';
    const binFile = 'nezha-agent';
    const downloadUrl = `https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_${archCode}.zip`;

    if (fs.existsSync(binFile) || fs.existsSync('nezha.zip')) {
        try { execSync(`rm -rf ${binFile} nezha.zip`); } catch (e) {}
    }

    console.log(`>>> [下载] 正在下载适配 ${archCode} 的探针...`);
    try {
        execSync(`curl -L -o nezha.zip ${downloadUrl}`, { stdio: 'inherit' });
        execSync(`unzip -o nezha.zip`, { stdio: 'inherit' });
        execSync(`chmod +x ${binFile}`);
        console.log('>>> [下载] 完成并已授权！');
    } catch (err) {
        console.error('\n>>> [错误] 下载或解压失败！请检查网络。');
        return;
    }

    // =========================================================
    // 🟢 [核心修复] 配置文件生成：锚定行首，避免读错行
    // =========================================================
    
    let finalConfigContent = `server: ${server}\nclient_secret: ${secret}\ntls: ${tls}\n`;
    let useOldConfig = false; 

    const cleanStr = (str) => String(str || '').replace(/['"]/g, '').trim();

    // 🛠️ 布尔值翻译官
    const isTrue = (val) => {
        const s = String(val).toLowerCase().replace(/['"]/g, '').trim();
        return s === 'true' || s === '1' || s === 'on';
    };

    if (forceUUID) {
        finalConfigContent += `uuid: ${forceUUID}\n`;
        console.log('>>> [配置] 检测到命令中包含 UUID，已强制应用。');
    } 
    else if (fs.existsSync(CONFIG_FILE_YAML)) {
        try {
            const oldContent = fs.readFileSync(CONFIG_FILE_YAML, 'utf8');
            
            // 🚨 关键修复：(?:^|\n) 确保只匹配行首的 tls:
            // 这样就不会匹配到 insecure_tls: 了！
            const oldServerMatch = oldContent.match(/(?:^|\n)\s*server:\s*([^#\n\r]+)/i);
            const oldSecretMatch = oldContent.match(/(?:^|\n)\s*client_secret:\s*([^#\n\r]+)/i);
            const oldTlsMatch = oldContent.match(/(?:^|\n)\s*tls:\s*([^#\n\r]+)/i);
            const oldUuidMatch = oldContent.match(/(?:^|\n)\s*uuid:\s*([a-zA-Z0-9-]+)/i);

            if (oldServerMatch && oldSecretMatch && oldTlsMatch && oldUuidMatch) {
                const oldServerVal = oldServerMatch[1];
                const oldSecretVal = oldSecretMatch[1];
                const oldTlsVal = oldTlsMatch[1];

                const isServerSame = cleanStr(oldServerVal) === cleanStr(server);
                const isSecretSame = cleanStr(oldSecretVal) === cleanStr(secret);
                const isTlsSame = isTrue(oldTlsVal) === isTrue(tls);

                if (isServerSame && isSecretSame && isTlsSame) {
                    console.log('>>> [配置] ✅ 参数校验通过，保留旧配置。');
                    finalConfigContent += `uuid: ${oldUuidMatch[1]}\n`;
                    useOldConfig = true;
                } else {
                    console.log('>>> [配置] ⚠️ 检测到关键参数变更，需重置：');
                    if (!isServerSame) console.log(`       - Server变更`);
                    if (!isSecretSame) console.log(`       - Secret变更`);
                    if (!isTlsSame)    console.log(`       - TLS模式变更 (原配置:${cleanStr(oldTlsVal)} -> 新指令:${tls})`);
                    console.log('       -> 正在重新生成配置文件...');
                }
            }
        } catch(e) {
            console.log('>>> [配置] 读取旧配置出错，将使用新配置。');
        }
    }

    fs.writeFileSync(CONFIG_FILE_YAML, finalConfigContent);
    
    if (!useOldConfig && !forceUUID) {
        console.log(`>>> [配置] 新探针配置已生成: ${CONFIG_FILE_YAML}`);
    }

    console.log('>>> [启动] 正在拉起 nezha-agent 进程...');
    console.log('----------------------------------------------------');
    
    const agentProcess = spawn(`./${binFile}`, ['-c', CONFIG_FILE_YAML], {
        stdio: 'inherit', 
        env: process.env
    });

    agentProcess.on('exit', (code) => {
        if (code !== 0) {
            console.error(`\n>>> [警告] 哪吒探针异常退出 (代码: ${code})。`);
        }
    });
}

// ==========================================
// 3. ⚙️ 参数解析模块
// ==========================================

function parseCommand(input) {
    if (!input) return null;
    
    // 正则提取哪吒参数
    const serverMatch = input.match(/NZ_SERVER=([\w\.:-]+)/);
    const secretMatch = input.match(/NZ_CLIENT_SECRET=([\w-]+)/);
    const tlsMatch = input.match(/NZ_TLS=(true|false)/i); 
    
    const uuidMatch = input.match(/NZ_UUID=([\w-]+)/);

    if (serverMatch && secretMatch) {
        return {
            server: serverMatch[1],
            secret: secretMatch[1],
            tls: tlsMatch ? tlsMatch[1] : 'false',
            uuid: uuidMatch ? uuidMatch[1] : null 
        };
    }
    return null;
}

// ==========================================
// 4. 🏁 主入口函数
// ==========================================
(async function main() {
    console.clear();
    console.log('====================================================');
    console.log('        多功能启动脚本 - 哪吒探针 & 业务程序');
    console.log('====================================================');

    let presetConfig = parseCommand(PRESET_NEZHA_COMMAND);
    let backupConfig = null;
    
    // 尝试读取本地备份
    if (fs.existsSync(BACKUP_FILE)) {
        try {
            backupConfig = JSON.parse(fs.readFileSync(BACKUP_FILE, 'utf8'));
        } catch (e) {}
    }

    if (presetConfig) console.log(`[提示] 代码预设: ${presetConfig.server}`);
    if (backupConfig) console.log(`[提示] 本地备份: ${backupConfig.server}`);

    console.log('----------------------------------------------------');
    console.log(`请选择操作 (${TIMEOUT_SECONDS}秒倒计时):`);
    console.log(`1. [粘贴] 输入新命令并回车 -> 使用新命令 (优先级最高)`);
    console.log(`2. [回车] 直接按回车        -> 跳过等待，使用预设或备份`);
    console.log(`3. [等待] 倒计时结束        -> 自动使用预设或备份`);
    console.log('----------------------------------------------------');

    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    const getUserInput = () => {
        return new Promise((resolve) => {
            let isResolved = false;
            const timer = setTimeout(() => {
                if (!isResolved) {
                    console.log('\n>>> 倒计时结束，自动继续...');
                    isResolved = true;
                    rl.close();
                    resolve(null);
                }
            }, TIMEOUT_SECONDS * 1000);

            rl.question('请输入 > ', (answer) => {
                if (!isResolved) {
                    clearTimeout(timer); 
                    isResolved = true;
                    rl.close();
                    resolve(answer.trim());
                }
            });
        });
    };

    const input = await getUserInput();
    let finalConfig = null;

    // 处理用户输入
    if (input && input.length > 5) {
        const consoleConfig = parseCommand(input);
        if (consoleConfig) {
            console.log('>>> [来源] 使用控制台输入的命令。');
            finalConfig = consoleConfig;
            fs.writeFileSync(BACKUP_FILE, JSON.stringify(finalConfig));
        } else {
            console.log('>>> [忽略] 输入的命令格式无法识别。');
        }
    }

    if (!finalConfig && presetConfig) {
        console.log('>>> [来源] 使用代码变量 (PRESET_NEZHA_COMMAND)。');
        finalConfig = presetConfig;
    }

    if (!finalConfig && backupConfig) {
        console.log('>>> [来源] 使用本地备份文件。');
        finalConfig = backupConfig;
    }

    if (finalConfig) {
        startNezha(finalConfig.server, finalConfig.secret, finalConfig.tls, finalConfig.uuid);
    } else {
        console.log('>>> [提示] 未找到配置，仅启动主业务。');
    }

    startMainScript();
    
    setInterval(() => {}, 1 << 30);
})();
