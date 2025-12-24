import java.io.*;
import java.nio.charset.Charset;
import java.nio.file.*;
import java.util.*;
import java.util.regex.*;
import java.util.zip.*;

/**
 * 🚀 Java 启动器 (智能配置版)
 * 1. 读取 env.sh
 * 2. 智能对比 nezha.yml (复刻 Node.js 逻辑)
 * 3. Java 内置解压
 * 4. 启动探针 & 业务
 */
public class start {

    // ================= ⚙️ 配置区 =================
    private static final String CONFIG_FILE = "env.sh";
    private static final String CHAR_SET_NAME = "GBK";
    private static final String NEZHA_YAML = "nezha.yml";
    private static final String MAIN_SCRIPT = "argosbx.sh";
    private static Map<String, String> ENV_MAP = new HashMap<>();

    public static void main(String[] args) {
        System.out.println("====================================================");
        System.out.println("        🚀 Java 启动器 (智能配置版) 已启动");
        System.out.println("====================================================");

        try {
            // 1. 读取 env.sh
            loadEnvConfig();

            // 2. 获取哪吒指令
            String nezhaCommand = ENV_MAP.getOrDefault("NEZHA_COMMAND", "");

            // 3. 启动哪吒
            if (nezhaCommand != null && nezhaCommand.length() > 0) {
                NezhaConfig config = parseCommand(nezhaCommand);
                if (config != null) {
                    startNezha(config);
                } else {
                    System.out.println(">>> [提示] 哪吒指令格式不对，跳过探针。");
                }
            }

            // 4. 启动主脚本
            runMainScript();

            // 5. 保活
            System.out.println("\n>>> [系统] 任务完成，进入后台保活模式...");
            while (true) Thread.sleep(100000);

        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    // ==========================================
    // 🛡️ 哪吒探针逻辑 (含智能配置对比)
    // ==========================================

    private static void startNezha(NezhaConfig config) throws IOException {
        System.out.println("\n>>> [探针] 准备启动哪吒 Agent...");
        System.out.println("    服务器: " + config.server);

        String arch = System.getProperty("os.arch").toLowerCase();
        String downloadArch = (arch.contains("64") && !arch.contains("aarch")) ? "amd64" : "arm64";

        String binFile = "nezha-agent";
        String zipFile = "nezha.zip";
        String downloadUrl = "https://github.com/nezhahq/agent/releases/latest/download/nezha-agent_linux_" + downloadArch + ".zip";

        if (new File(binFile).exists()) {
            runShellCommand("rm -rf " + binFile + " " + zipFile, false);
        }

        System.out.println(">>> [下载] 正在下载适配 " + downloadArch + " 的探针...");
        runShellCommand("curl -L -o " + zipFile + " " + downloadUrl, true);

        System.out.println(">>> [解压] 使用 Java 内置功能解压...");
        try {
            unzip(zipFile, ".");
        } catch (Exception e) {
            System.err.println(">>> [错误] Java 解压失败: " + e.getMessage());
            return;
        }

        runShellCommand("chmod +x " + binFile, false);

        // 🟢 [核心逻辑] 智能生成/更新配置
        generateNezhaConfig(config);

        System.out.println(">>> [启动] 拉起 nezha-agent...");
        ProcessBuilder pb = new ProcessBuilder("./" + binFile, "-c", NEZHA_YAML);
        pb.environment().putAll(ENV_MAP);
        pb.inheritIO();
        pb.start();
    }

    /**
     * 🟢 [核心移植] 复刻 Node.js 的配置对比逻辑
     * 只有当 server, secret, tls 真正发生变化时才重写，否则保留 UUID
     */
    private static void generateNezhaConfig(NezhaConfig newConfig) throws IOException {
        File configFile = new File(NEZHA_YAML);
        String finalUuid = null;
        boolean useOldConfig = false;

        if (configFile.exists()) {
            try {
                String oldContent = new String(Files.readAllBytes(configFile.toPath()));

                // 🟢 使用多行模式 (?m)^ 确保只匹配行首，防止匹配到 insecure_tls 或注释
                String oldServer = extractRegex(oldContent, "(?m)^\\s*server:\\s*([^#\\r\\n]+)");
                String oldSecret = extractRegex(oldContent, "(?m)^\\s*client_secret:\\s*([^#\\r\\n]+)");
                String oldTls = extractRegex(oldContent, "(?m)^\\s*tls:\\s*([^#\\r\\n]+)");
                String oldUuid = extractRegex(oldContent, "(?m)^\\s*uuid:\\s*([a-zA-Z0-9-]+)");

                if (!oldServer.isEmpty() && !oldSecret.isEmpty() && !oldUuid.isEmpty()) {
                    // 1. 净化字符串 (去引号, 去空格)
                    boolean isServerSame = cleanStr(oldServer).equals(cleanStr(newConfig.server));
                    boolean isSecretSame = cleanStr(oldSecret).equals(cleanStr(newConfig.secret));

                    // 2. 智能布尔值对比 (1 == true == on)
                    boolean isTlsSame = isTrue(oldTls) == isTrue(newConfig.tls);

                    if (isServerSame && isSecretSame && isTlsSame) {
                        System.out.println(">>> [配置] ✅ 参数校验通过，保留旧 UUID: " + oldUuid);
                        finalUuid = oldUuid;
                        useOldConfig = true;
                    } else {
                        System.out.println(">>> [配置] ⚠️ 关键参数变更 (Server/Secret/TLS)，将重置配置...");
                    }
                }
            } catch (Exception e) {
                System.out.println(">>> [配置] 读取旧配置出错，将生成新配置。");
            }
        }

        // 写入新文件
        StringBuilder yaml = new StringBuilder();
        yaml.append("server: ").append(newConfig.server).append("\n");
        yaml.append("client_secret: ").append(newConfig.secret).append("\n");
        yaml.append("tls: ").append(newConfig.tls).append("\n");

        if (finalUuid != null) {
            yaml.append("uuid: ").append(finalUuid).append("\n");
        } else if (newConfig.uuid != null) {
            yaml.append("uuid: ").append(newConfig.uuid).append("\n");
        }

        Files.write(configFile.toPath(), yaml.toString().getBytes());
        if (!useOldConfig) {
            System.out.println(">>> [配置] 新配置文件已写入。");
        }
    }

    // ==========================================
    // 🛠️ 通用功能模块
    // ==========================================

    private static void loadEnvConfig() {
        System.out.println(">>> [环境] 正在读取 " + CONFIG_FILE + " ...");
        File file = new File(CONFIG_FILE);
        if (!file.exists()) {
            System.err.println(">>> [错误] 找不到 " + CONFIG_FILE);
            return;
        }
        try {
            String content = new String(Files.readAllBytes(file.toPath()), Charset.forName(CHAR_SET_NAME));
            Pattern pattern = Pattern.compile("export\\s+(\\w+)=\"(.*?)\"");
            Matcher matcher = pattern.matcher(content);
            while (matcher.find()) {
                ENV_MAP.put(matcher.group(1), matcher.group(2));
            }
            System.out.println(">>> [环境] 加载完毕。\n");
        } catch (IOException e) {
            System.err.println(">>> [错误] 读取失败: " + e.getMessage());
        }
    }

    private static void unzip(String zipFilePath, String destDir) throws IOException {
        File dir = new File(destDir);
        if (!dir.exists()) dir.mkdirs();
        byte[] buffer = new byte[1024];
        try (ZipInputStream zis = new ZipInputStream(new FileInputStream(zipFilePath))) {
            ZipEntry zipEntry = zis.getNextEntry();
            while (zipEntry != null) {
                File newFile = new File(destDir, zipEntry.getName());
                if (zipEntry.isDirectory()) {
                    newFile.mkdirs();
                } else {
                    new File(newFile.getParent()).mkdirs();
                    try (FileOutputStream fos = new FileOutputStream(newFile)) {
                        int len;
                        while ((len = zis.read(buffer)) > 0) fos.write(buffer, 0, len);
                    }
                }
                zipEntry = zis.getNextEntry();
            }
            zis.closeEntry();
        }
    }

    private static void runMainScript() {
        System.out.println("\n====================================================");
        System.out.println(">>> [主程序] 启动业务脚本 (" + MAIN_SCRIPT + ") ...");
        System.out.println("====================================================");
        File script = new File(MAIN_SCRIPT);
        if (!script.exists()) {
            System.err.println(">>> [错误] 找不到 " + MAIN_SCRIPT);
            return;
        }
        try {
            runShellCommand("chmod +x " + MAIN_SCRIPT, false);
            ProcessBuilder pb = new ProcessBuilder("bash", "./" + MAIN_SCRIPT);
            pb.environment().putAll(ENV_MAP);
            pb.inheritIO();
            Process process = pb.start();
            new Thread(() -> {
                try {
                    int code = process.waitFor();
                    System.out.println("\n[注意] " + MAIN_SCRIPT + " 运行结束 (代码: " + code + ")");
                } catch (InterruptedException e) {}
            }).start();
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    // ================= 🔧 辅助工具函数 =================

    private static void runShellCommand(String command, boolean showOutput) {
        try {
            ProcessBuilder pb = new ProcessBuilder("bash", "-c", command);
            if (showOutput) pb.inheritIO();
            Process p = pb.start();
            p.waitFor();
        } catch (Exception e) {}
    }

    private static String extractRegex(String source, String regex) {
        // Pattern.CASE_INSENSITIVE 让正则不区分大小写
        Pattern p = Pattern.compile(regex, Pattern.CASE_INSENSITIVE);
        Matcher m = p.matcher(source);
        return m.find() ? m.group(1).trim() : "";
    }

    private static String cleanStr(String str) {
        return str == null ? "" : str.replaceAll("['\"]", "").trim();
    }

    // 🟢 [新增] 智能判断布尔值 (复刻 Node.js 里的 isTrue)
    private static boolean isTrue(String val) {
        if (val == null) return false;
        String s = val.toLowerCase().replaceAll("['\"]", "").trim();
        return s.equals("true") || s.equals("1") || s.equals("on");
    }

    private static NezhaConfig parseCommand(String input) {
        String server = extractRegex(input, "NZ_SERVER=([\\w\\.:-]+)");
        String secret = extractRegex(input, "NZ_CLIENT_SECRET=([\\w-]+)");
        String tls = extractRegex(input, "NZ_TLS=(true|false|1|0)"); // 稍微放宽正则匹配
        if (server.isEmpty() || secret.isEmpty()) return null;
        return new NezhaConfig(server, secret, tls.isEmpty() ? "false" : tls, null);
    }

    static class NezhaConfig {
        String server, secret, tls, uuid;
        public NezhaConfig(String server, String secret, String tls, String uuid) {
            this.server = server; this.secret = secret; this.tls = tls; this.uuid = uuid;
        }
    }
}