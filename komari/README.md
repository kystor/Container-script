# Container-script

å®¹å¨å¯å¨èæ¬ï¼åç½®ä»¥ä¸è½åï¼

- åªåæ¢éå®è£ä¸å¯å¨
- Komari æ¢éå®è£ä¸å¯å¨
- Argosbx ä¸»èæ¬æèµ·
- èªå¨æ¢æµå®¹å¨ç«¯å£
- ç¯å¢åééä¼ å° `argosbx.sh`

## è¿ç¨å®è£

å¦ææå¡å¨æ `curl`ï¼ç´æ¥æ§è¡ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

å¦ææå¡å¨æ²¡æ `curl`ï¼å¯ä»¥ç¨ï¼

```bash
bash <(wget -qO- https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## æ«å°¾åæ°éä¼ 

`start.sh` ä¸è¯å« `rep`ã`del`ã`list`ã`res`ã`upx`ã`ups` è¿äºå·ä½å­ç¬¦ä¸²ã

å®åªåä¸ä»¶äºï¼

- æä½ åå¨å½ä»¤æ«å°¾çåæ°ï¼åæ ·ä¼ ç» `argosbx.sh`

ä¾å¦ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) ups
```

åé¨å®éæ§è¡ææå°±æ¯ï¼

```bash
bash argosbx.sh ups
```

å¦æä½ è¿æ ·æ§è¡ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) list
```

åé¨å°±ä¼éä¼ æï¼

```bash
bash argosbx.sh list
```

å¦ææ«å°¾æ²¡æåæ°ï¼èæ¬é»è®¤ä½¿ç¨ `rep`ã

ä¹å°±æ¯ä¸é¢ä¸¤ç§åæ³ç­ä»·ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) rep
```

## å¯å¨åä¼ å

ä½ å¯ä»¥æç¯å¢åéç´æ¥åå¨è¿ç¨å½ä»¤åé¢ã

ä¾å¦ï¼

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) rep
```

è¿äºåéä¼ï¼

- å½åè¿æ¬¡æ§è¡ç«å³çæ
- ç»§ç»­éä¼ ç»åé¨å¯å¨ç `argosbx.sh`
- èªå¨ä¿å­å° `$HOME/.container-script.env`
- å¨éå¯åç±èªå¯ä»»å¡éæ°å è½½

## å¸¸ç¨ç¤ºä¾

è°æ´åéå¹¶æ§è¡é»è®¤ `rep`ï¼

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

è°æ´åéå¹¶æ¾å¼æ§è¡ `rep`ï¼

```bash
hypt="1" tupt="2" bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) rep
```

æ¥çèç¹ä¿¡æ¯ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) list
```

å¸è½½ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) del
```

éå¯ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) res
```

åçº§ Xray åæ ¸ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) upx
```

åçº§ Singbox åæ ¸ï¼

```bash
bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh) ups
```

## å®¹å¨ç«¯å£æ£æµ

èæ¬ä¼ä¼åä»ä¸é¢è¿äºç¯å¢åééå¯»æ¾å®¹å¨ç«¯å£ï¼

- `SERVER_PORT`
- `PORT`
- `PANEL_PORT`
- `LISTEN_PORT`
- `APP_PORT`
- `WEB_PORT`
- `CONTAINER_PORT`
- `INTERNAL_PORT`

å¦ææ£æµå°ææç«¯å£ï¼ä¼èªå¨å¯¼åºï¼

- `SERVER_PORT`
- `PORT`
- `CONTAINER_PORT`
- `INTERNAL_PORT`
- `PANEL_PORT`

å¦æä½ æ²¡ææå¨ä¼ å¥ `hypt`ï¼èæ¬è¿ä¼ææ£æµå°çå®¹å¨ç«¯å£é»è®¤èµç» `hypt`ã

## åªåç¨æ³

æ¯æä¸é¢å ç§æ¹å¼ï¼

1. è¿è¡èæ¬åæå¨ç²è´´åªåå®æ¹å½ä»¤
2. éè¿ `NZ_CMD` ç´æ¥ä¼ å¥
3. æ¬å°å·²æ `nezha.yml` æ¶ç´æ¥å¤ç¨

ç¤ºä¾ï¼

```bash
NZ_CMD='NZ_SERVER=example.com:5555 NZ_CLIENT_SECRET=your-secret NZ_TLS=false' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## Komari ç¨æ³

æ¯æä¸é¢å ç§æ¹å¼ï¼

1. è¿è¡èæ¬åæå¨ç²è´´ Komari å®æ¹å®è£å½ä»¤
2. åªä¼ åæ°ï¼æ¯å¦ `-e https://example.com -t your-token`
3. éè¿ `KOMARI_CMD` ç´æ¥ä¼ å¥
4. æ¬å°å·²æ `komari-agent.args` æ¶ç´æ¥å¤ç¨

ç¤ºä¾ï¼

```bash
KOMARI_CMD='-e https://example.com -t your-token' bash <(curl -Ls https://raw.githubusercontent.com/kystor/Container-script/refs/heads/main/start.sh)
```

## æä¹åè¡ä¸º

èæ¬ä¼èªå¨æ§è¡è¿äºå¨ä½ï¼

- æè¿ç¨ `start.sh` åæ­¥å° `$HOME/start.sh`
- æå½åç¯å¢åéä¿å­å° `$HOME/.container-script.env`
- å¦æç³»ç»æ `crontab`ï¼èªå¨åå¥ `@reboot` èªå¯ä»»å¡

è¿æ ·æå¡å¨éå¯åï¼ä¹åä¼ è¿å»çç¯å¢åéè¿è½ç»§ç»­æ¢å¤å¹¶åæ¬¡æ§è¡èæ¬ã
