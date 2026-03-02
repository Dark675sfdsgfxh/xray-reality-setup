#!/usr/bin/env bash
# sing-box setup - Common functions library
# This file is sourced by the OS-specific setup scripts

# ============================================================================
# Configuration
# ============================================================================

SING_BOX_VERSION="1.13.0"
CONFIG_DIR="/etc/sing-box"
CONFIG_FILE="${CONFIG_DIR}/config.json"
LOG_FILE="/var/log/sing-box.log"

# SHA256 checksums for sing-box releases (update when changing version)
# From: https://github.com/SagerNet/sing-box/releases
declare -A SING_BOX_CHECKSUMS=(
    ["amd64"]="86db0f9df3f822ca2adccde2f7c1c9e21d64e646a77bf258274fde3be399025b"
    ["arm64"]="57efdb8a256ae0736fa00aee5538c384ee50b40882075d2d1a05a1c3d7c4a889"
    ["armv7"]="5c598e427ba44bf0c45146178e05227ded2d3d20acc498aecdea49a60d9605dc"
)

# DNS Providers (same as server)
DNS_NAMES=(
    "DNS.SB"
    "Mullvad DNS"
    "Cloudflare"
    "Google"
    "Quad9"
    "AdGuard DNS"
)
DNS_SERVERS=(
    "45.11.45.11"
    "194.242.2.2"
    "1.1.1.1"
    "8.8.8.8"
    "9.9.9.9"
    "94.140.14.14"
)
DNS_DESCRIPTIONS=(
    "Germany   | No logging, DNSSEC"
    "Sweden    | No logging, privacy-focused"
    "USA       | Fast, no logging (Cloudflare policy)"
    "USA       | Fast, logs for 24-48h"
    "Zurich    | Malware blocking, DNSSEC"
    "Cyprus    | Ad blocking, no logging"
)

# Colors (using ANSI-C quoting for bash compatibility)
RED=$'\033[0;31m'
GREEN=$'\033[0;32m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
NC=$'\033[0m'

# ============================================================================
# Common Functions
# ============================================================================

# Escape special characters for JSON string values
json_escape() {
    local str="$1"
    # Escape backslash, double quote, and control characters
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\r'/\\r}"
    str="${str//$'\t'/\\t}"
    printf '%s' "$str"
}

check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

parse_vless_link() {
    LINK="$1"

    # Prompt for VLESS link if not provided (avoids storing in bash history)
    if [ -z "$LINK" ]; then
        echo ""
        echo "${CYAN}Enter your VLESS share link${NC}"
        echo "(paste the link from xray-setup.sh output on your server)"
        echo ""
        printf "  VLESS link: "
        read -r LINK
        echo ""
    fi

    if [ -z "$LINK" ]; then
        echo "${RED}Error: VLESS link is required${NC}"
        exit 1
    fi

    if ! echo "$LINK" | grep -q "^vless://"; then
        echo "${RED}Error: Invalid VLESS link format${NC}"
        echo "Link must start with: vless://"
        exit 1
    fi

    # Extract components
    # Format: vless://UUID@SERVER:PORT?params#name

    # Remove vless:// prefix and #name suffix
    LINK_BODY=$(echo "$LINK" | sed 's|^vless://||' | sed 's|#.*$||')

    # Extract UUID (before @)
    UUID=$(echo "$LINK_BODY" | cut -d'@' -f1)

    # Extract server:port (between @ and ?)
    SERVER_PORT=$(echo "$LINK_BODY" | cut -d'@' -f2 | cut -d'?' -f1)
    SERVER=$(echo "$SERVER_PORT" | cut -d':' -f1)
    PORT=$(echo "$SERVER_PORT" | cut -d':' -f2)

    # Extract parameters
    PARAMS=$(echo "$LINK_BODY" | cut -d'?' -f2)

    # Parse individual parameters
    SNI=$(echo "$PARAMS" | tr '&' '\n' | grep "^sni=" | cut -d'=' -f2)
    PBK=$(echo "$PARAMS" | tr '&' '\n' | grep "^pbk=" | cut -d'=' -f2)
    SID=$(echo "$PARAMS" | tr '&' '\n' | grep "^sid=" | cut -d'=' -f2)
    FLOW=$(echo "$PARAMS" | tr '&' '\n' | grep "^flow=" | cut -d'=' -f2)
    FP=$(echo "$PARAMS" | tr '&' '\n' | grep "^fp=" | cut -d'=' -f2)

    # Set defaults
    [ -z "$FLOW" ] && FLOW="xtls-rprx-vision"
    [ -z "$FP" ] && FP="chrome"
    [ -z "$PORT" ] && PORT="443"

    # Validate required fields
    if [ -z "$UUID" ] || [ -z "$SERVER" ] || [ -z "$SNI" ] || [ -z "$PBK" ]; then
        echo "${RED}Error: Could not parse all required fields from VLESS link${NC}"
        echo ""
        echo "Parsed values:"
        echo "  Server: ${SERVER:-MISSING}"
        echo "  Port: ${PORT:-MISSING}"
        echo "  UUID: ${UUID:-MISSING}"
        echo "  SNI: ${SNI:-MISSING}"
        echo "  Public Key: ${PBK:-MISSING}"
        echo "  Short ID: ${SID:-empty}"
        exit 1
    fi

    # Detect if server is IP or domain
    if [[ "$SERVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || [[ "$SERVER" =~ : ]]; then
        SERVER_IS_IP=true
    else
        SERVER_IS_IP=false
    fi

    echo "${GREEN}Parsed VLESS link successfully${NC}"
    echo "  Server: $SERVER:$PORT"
    if [ "$SERVER_IS_IP" = true ]; then
        echo "  Server type: IP address"
    else
        echo "  Server type: Domain (will use local DNS for resolution)"
    fi
    echo "  SNI: $SNI"
}

detect_arch() {
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64)  ARCH="amd64" ;;
        aarch64) ARCH="arm64" ;;
        armv7l)  ARCH="armv7" ;;
        *)
            echo "${RED}Error: Unsupported architecture: $ARCH${NC}"
            exit 1
            ;;
    esac
    echo "  Architecture: $ARCH"
}

choose_logging() {
    echo ""
    echo "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}║${NC}  Logging Preference                                      ${CYAN}║${NC}"
    echo "${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo "${CYAN}║${NC}                                                          ${CYAN}║${NC}"
    echo "${CYAN}║${NC}  Logs can help with troubleshooting but may contain      ${CYAN}║${NC}"
    echo "${CYAN}║${NC}  connection metadata (timestamps, errors).               ${CYAN}║${NC}"
    echo "${CYAN}║${NC}                                                          ${CYAN}║${NC}"
    echo "${CYAN}║${NC}  For maximum privacy, keep logging disabled.             ${CYAN}║${NC}"
    echo "${CYAN}║${NC}                                                          ${CYAN}║${NC}"
    echo "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    printf "  Enable logging? [y/N]: "
    read -r LOG_INPUT

    if [ "${LOG_INPUT}" = "y" ] || [ "${LOG_INPUT}" = "Y" ] || [ "${LOG_INPUT}" = "yes" ]; then
        ENABLE_LOGS="y"
        echo "  ${GREEN}Logging enabled: warnings and errors will be logged${NC}"
    else
        ENABLE_LOGS="n"
        echo "  ${GREEN}Logging disabled: no data will be stored${NC}"
    fi
}

choose_dns() {
    echo ""
    echo "${CYAN}Choose DNS provider:${NC}"
    echo ""
    for i in "${!DNS_NAMES[@]}"; do
        printf "  %d) %-15s %s\n" "$((i+1))" "${DNS_NAMES[$i]}" "${DNS_DESCRIPTIONS[$i]}"
    done
    echo ""

    printf "  Select DNS [1-%d, default=1]: " "${#DNS_NAMES[@]}"
    read -r INPUT_DNS

    DNS_IDX=$(( ${INPUT_DNS:-1} - 1 ))
    if [ "$DNS_IDX" -lt 0 ] || [ "$DNS_IDX" -ge "${#DNS_NAMES[@]}" ]; then
        echo "  ${YELLOW}Invalid choice. Using DNS.SB.${NC}"
        DNS_IDX=0
    fi

    DNS_NAME="${DNS_NAMES[$DNS_IDX]}"
    DNS_SERVER="${DNS_SERVERS[$DNS_IDX]}"

    echo ""
    echo "  ${GREEN}Selected: ${DNS_NAME} (${DNS_SERVER})${NC}"
}

install_sing_box() {
    echo ""
    echo "${CYAN}Installing sing-box v${SING_BOX_VERSION}...${NC}"

    # Check if already installed
    if command -v sing-box >/dev/null 2>&1; then
        CURRENT_VERSION=$(sing-box version 2>/dev/null | head -n1 | awk '{print $3}')
        echo "  Current version: $CURRENT_VERSION"
        if [ "$CURRENT_VERSION" = "$SING_BOX_VERSION" ]; then
            echo "  ${GREEN}Already up to date${NC}"
            return
        fi
    fi

    # Create secure temporary directory
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "$TEMP_DIR"' EXIT

    # Download
    DOWNLOAD_URL="https://github.com/SagerNet/sing-box/releases/download/v${SING_BOX_VERSION}/sing-box-${SING_BOX_VERSION}-linux-${ARCH}.tar.gz"
    TARBALL="${TEMP_DIR}/sing-box.tar.gz"

    echo "  Downloading from GitHub..."
    curl -sL -o "$TARBALL" "$DOWNLOAD_URL" || {
        echo "${RED}Error: Failed to download sing-box${NC}"
        exit 1
    }

    # Verify checksum
    EXPECTED_CHECKSUM="${SING_BOX_CHECKSUMS[$ARCH]}"
    if [ -n "$EXPECTED_CHECKSUM" ]; then
        echo "  Verifying checksum..."
        ACTUAL_CHECKSUM=$(sha256sum "$TARBALL" | cut -d' ' -f1)
        if [ "$ACTUAL_CHECKSUM" != "$EXPECTED_CHECKSUM" ]; then
            echo "${RED}Error: Checksum verification failed${NC}"
            echo "  Expected: $EXPECTED_CHECKSUM"
            echo "  Got:      $ACTUAL_CHECKSUM"
            exit 1
        fi
        echo "  ${GREEN}Checksum verified${NC}"
    else
        echo "  ${YELLOW}Warning: No checksum available for $ARCH, skipping verification${NC}"
    fi

    # Extract and install
    echo "  Extracting..."
    tar -xzf "$TARBALL" -C "$TEMP_DIR"
    cp "${TEMP_DIR}/sing-box-${SING_BOX_VERSION}-linux-${ARCH}/sing-box" /usr/local/bin/
    chmod +x /usr/local/bin/sing-box

    # Cleanup handled by trap

    echo "  ${GREEN}Installed: $(sing-box version | head -n1)${NC}"
}

write_config() {
    echo ""
    echo "${CYAN}Writing configuration...${NC}"

    mkdir -p "$CONFIG_DIR"

    # Escape user-provided values for JSON safety
    local SERVER_ESC=$(json_escape "$SERVER")
    local UUID_ESC=$(json_escape "$UUID")
    local SNI_ESC=$(json_escape "$SNI")
    local PBK_ESC=$(json_escape "$PBK")
    local SID_ESC=$(json_escape "$SID")
    local FP_ESC=$(json_escape "$FP")
    local FLOW_ESC=$(json_escape "$FLOW")

    # Build DNS config based on server type
    if [ "$SERVER_IS_IP" = true ]; then
        # Server is IP - no need for local DNS resolution
        DNS_CONFIG='"dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "'"${DNS_SERVER}"'",
        "detour": "proxy"
      }
    ],
    "strategy": "prefer_ipv4"
  },'
    else
        # Server is domain - need local DNS for server resolution
        DNS_CONFIG='"dns": {
    "servers": [
      {
        "tag": "dns-remote",
        "address": "'"${DNS_SERVER}"'",
        "detour": "proxy"
      },
      {
        "tag": "dns-direct",
        "address": "local"
      }
    ],
    "rules": [
      {
        "outbound": "any",
        "server": "dns-direct"
      }
    ],
    "strategy": "prefer_ipv4"
  },'
    fi

    # Build log config based on preference
    if [ "$ENABLE_LOGS" = "y" ]; then
        LOG_CONFIG='"log": {
    "level": "warn",
    "timestamp": true
  },'
    else
        LOG_CONFIG='"log": {
    "disabled": true
  },'
    fi

    cat > "$CONFIG_FILE" << EOF
{
  ${LOG_CONFIG}
  ${DNS_CONFIG}
  "inbounds": [
    {
      "type": "tun",
      "tag": "tun-in",
      "interface_name": "sing-tun",
      "address": [
        "172.19.0.1/30",
        "fdfe:dcba:9876::1/126"
      ],
      "mtu": 1400,
      "auto_route": true,
      "strict_route": true,
      "stack": "system",
      "sniff": true,
      "sniff_override_destination": true
    }
  ],
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "${SERVER_ESC}",
      "server_port": ${PORT},
      "uuid": "${UUID_ESC}",
      "flow": "${FLOW_ESC}",
      "tls": {
        "enabled": true,
        "server_name": "${SNI_ESC}",
        "utls": {
          "enabled": true,
          "fingerprint": "${FP_ESC}"
        },
        "reality": {
          "enabled": true,
          "public_key": "${PBK_ESC}",
          "short_id": "${SID_ESC}"
        }
      }
    },
    {
      "type": "direct",
      "tag": "direct"
    },
    {
      "type": "block",
      "tag": "block"
    },
    {
      "type": "dns",
      "tag": "dns-out"
    }
  ],
  "route": {
    "rules": [
      {
        "protocol": "dns",
        "outbound": "dns-out"
      },
      {
        "ip_is_private": true,
        "outbound": "direct"
      },
      {
        "protocol": "stun",
        "outbound": "block"
      }
    ],
    "auto_detect_interface": true,
    "final": "proxy"
  }
}
EOF

    # Restrict permissions (contains credentials)
    chmod 600 "$CONFIG_FILE"

    echo "  Config written to: $CONFIG_FILE"

    # Validate
    echo "  Validating config..."
    if sing-box check -c "$CONFIG_FILE"; then
        echo "  ${GREEN}Config is valid${NC}"
    else
        echo "  ${RED}Config validation failed${NC}"
        exit 1
    fi
}

enable_tun_module() {
    echo ""
    echo "${CYAN}Enabling TUN module...${NC}"

    # Load TUN module
    if ! lsmod | grep -q "^tun"; then
        modprobe tun 2>/dev/null || true
    fi

    # Persist across reboots
    if [ ! -f /etc/modules-load.d/tun.conf ]; then
        mkdir -p /etc/modules-load.d
        echo "tun" > /etc/modules-load.d/tun.conf
    fi

    # Also add to /etc/modules (for Alpine and Devuan)
    if [ -f /etc/modules ] && ! grep -q "^tun$" /etc/modules 2>/dev/null; then
        echo "tun" >> /etc/modules
    fi

    echo "  ${GREEN}TUN module enabled${NC}"
}

verify_connection() {
    echo ""
    echo "${CYAN}Verifying connection...${NC}"

    # Wait for TUN interface
    sleep 2

    # Check TUN interface
    if ip addr show sing-tun >/dev/null 2>&1; then
        echo "  ${GREEN}TUN interface created${NC}"
    else
        echo "  ${YELLOW}Warning: TUN interface not found${NC}"
    fi

    # Test connectivity
    echo "  Testing connectivity..."
    if PUBLIC_IP=$(curl -s --connect-timeout 10 https://ifconfig.me 2>/dev/null); then
        echo "  ${GREEN}Connection working${NC}"
        echo "  Your public IP: $PUBLIC_IP"
    else
        echo "  ${YELLOW}Warning: Could not verify connection${NC}"
        echo "  This may be normal if the server is not reachable yet."
    fi
}

# ============================================================================
# Init Script Helpers
# ============================================================================

# Create OpenRC init script
create_openrc_service() {
    echo ""
    echo "${CYAN}Creating OpenRC service...${NC}"

    # Detect openrc-run path
    if [ -f /sbin/openrc-run ]; then
        SHEBANG="#!/sbin/openrc-run"
    else
        SHEBANG="#!/usr/sbin/openrc-run"
    fi

    # Set log paths based on preference
    if [ "$ENABLE_LOGS" = "y" ]; then
        LOG_OUTPUT="/var/log/sing-box.log"
        LOG_ERROR="/var/log/sing-box.log"
        # checkpath creates file with mode 0640 (root:root, not world-readable)
        START_PRE='checkpath -f -m 0640 -o root:root "$output_log"
    ${command} check -c /etc/sing-box/config.json || return 1'
    else
        LOG_OUTPUT="/dev/null"
        LOG_ERROR="/dev/null"
        START_PRE='${command} check -c /etc/sing-box/config.json || return 1'
    fi

    cat > /etc/init.d/sing-box << EOF
${SHEBANG}

name="sing-box"
description="sing-box universal proxy"
command="/usr/local/bin/sing-box"
command_args="run -c /etc/sing-box/config.json"
command_background="yes"
pidfile="/run/\${RC_SVCNAME}.pid"

output_log="${LOG_OUTPUT}"
error_log="${LOG_ERROR}"

depend() {
    need net
    after firewall
}

start_pre() {
    ${START_PRE}
}
EOF

    chmod +x /etc/init.d/sing-box
    echo "  Created /etc/init.d/sing-box"
}

# Create SysVinit init script
create_sysvinit_service() {
    echo ""
    echo "${CYAN}Creating SysVinit service...${NC}"

    # Set log path based on preference
    if [ "$ENABLE_LOGS" = "y" ]; then
        INIT_LOG_FILE="/var/log/sing-box.log"
    else
        INIT_LOG_FILE="/dev/null"
    fi

    cat > /etc/init.d/sing-box << 'INITSCRIPT'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          sing-box
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: sing-box universal proxy
# Description:       sing-box routes system traffic through VLESS proxy
### END INIT INFO

NAME=sing-box
DAEMON=/usr/local/bin/sing-box
CONFIG=/etc/sing-box/config.json
PIDFILE=/run/sing-box.pid
INITSCRIPT

    # Append the LOGFILE line with the actual value
    echo "LOGFILE=${INIT_LOG_FILE}" >> /etc/init.d/sing-box

    cat >> /etc/init.d/sing-box << 'INITSCRIPT'

case "$1" in
    start)
        echo "Starting $NAME..."
        if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
            echo "$NAME is already running."
            exit 0
        fi
        $DAEMON check -c "$CONFIG" || exit 1
        # Create log file with restrictive permissions if logging enabled
        if [ "$LOGFILE" != "/dev/null" ]; then
            touch "$LOGFILE"
            chmod 640 "$LOGFILE"
        fi
        nohup $DAEMON run -c "$CONFIG" >> "$LOGFILE" 2>&1 &
        echo $! > "$PIDFILE"
        echo "$NAME started."
        ;;
    stop)
        echo "Stopping $NAME..."
        if [ -f "$PIDFILE" ]; then
            kill $(cat "$PIDFILE") 2>/dev/null
            rm -f "$PIDFILE"
            echo "$NAME stopped."
        else
            echo "$NAME is not running."
        fi
        ;;
    restart)
        $0 stop
        sleep 1
        $0 start
        ;;
    status)
        if [ -f "$PIDFILE" ] && kill -0 $(cat "$PIDFILE") 2>/dev/null; then
            echo "$NAME is running (PID: $(cat $PIDFILE))"
        else
            echo "$NAME is not running."
            exit 1
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac

exit 0
INITSCRIPT

    chmod +x /etc/init.d/sing-box
    echo "  Created /etc/init.d/sing-box"
}

# Create systemd service
create_systemd_service() {
    echo ""
    echo "${CYAN}Creating systemd service...${NC}"

    # Set log output based on preference
    if [ "$ENABLE_LOGS" = "y" ]; then
        STDOUT_LOG="append:${LOG_FILE}"
        STDERR_LOG="append:${LOG_FILE}"
        # Pre-create log file with restrictive permissions
        touch "$LOG_FILE"
        chmod 640 "$LOG_FILE"
    else
        STDOUT_LOG="null"
        STDERR_LOG="null"
    fi

    cat > /etc/systemd/system/sing-box.service << EOF
[Unit]
Description=sing-box universal proxy
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target

[Service]
Type=simple
ExecStartPre=/usr/local/bin/sing-box check -c ${CONFIG_FILE}
ExecStart=/usr/local/bin/sing-box run -c ${CONFIG_FILE}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
StandardOutput=${STDOUT_LOG}
StandardError=${STDERR_LOG}

[Install]
WantedBy=multi-user.target
EOF

    # Reload systemd
    systemctl daemon-reload

    echo "  Created /etc/systemd/system/sing-box.service"
}
