#!/usr/bin/env bash
# sing-box setup for Debian/Ubuntu Linux (systemd)
# Usage: ./setup-debian.sh
# The script will prompt for the VLESS link interactively

set -e

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ============================================================================
# Debian/Ubuntu-specific Functions
# ============================================================================

print_header() {
    echo ""
    echo "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}║${NC}        sing-box Installer for Debian/Ubuntu              ${CYAN}║${NC}"
    echo "${CYAN}║${NC}        Route all traffic through VLESS + REALITY         ${CYAN}║${NC}"
    echo "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_os() {
    # Check for Devuan (Debian fork without systemd)
    if grep -qi devuan /etc/os-release 2>/dev/null || [ -f /etc/devuan_version ]; then
        echo "${RED}Error: Devuan detected. Use ./setup-devuan.sh instead${NC}"
        exit 1
    fi
    # Check for Debian or Ubuntu
    if ! grep -qiE 'debian|ubuntu' /etc/os-release 2>/dev/null && [ ! -f /etc/debian_version ]; then
        echo "${RED}Error: This script is for Debian/Ubuntu Linux only${NC}"
        echo "For Alpine, use: ./setup-alpine.sh"
        echo "For Devuan, use: ./setup-devuan.sh"
        exit 1
    fi
    # Check for systemd
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "${RED}Error: systemd not found. Use ./setup-devuan.sh for non-systemd systems${NC}"
        exit 1
    fi
}

install_dependencies() {
    echo ""
    echo "${CYAN}Installing dependencies...${NC}"
    apt-get update -qq
    apt-get install -y -qq curl tar ca-certificates
}

start_service() {
    echo ""
    echo "${CYAN}Starting sing-box service...${NC}"

    # Enable at boot
    systemctl enable sing-box >/dev/null 2>&1

    # Stop if running
    systemctl stop sing-box 2>/dev/null || true

    # Start
    if systemctl start sing-box; then
        echo "  ${GREEN}Service started successfully${NC}"
    else
        echo "  ${RED}Failed to start service${NC}"
        echo "  Check logs: journalctl -u sing-box -f"
        exit 1
    fi
}

print_summary() {
    echo ""
    echo "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo "${GREEN}║${NC}              Installation Complete!                      ${GREEN}║${NC}"
    echo "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "  Config:  $CONFIG_FILE"
    echo "  DNS:     $DNS_NAME ($DNS_SERVER)"
    if [ "$ENABLE_LOGS" = "y" ]; then
        echo "  Logs:    $LOG_FILE"
    else
        echo "  Logs:    disabled"
    fi
    echo "  Service: systemctl {start|stop|restart|status} sing-box"
    echo ""
    echo "  Commands:"
    echo "    Check status:   systemctl status sing-box"
    if [ "$ENABLE_LOGS" = "y" ]; then
        echo "    View logs:      tail -f $LOG_FILE"
    else
        echo "    View logs:      journalctl -u sing-box -f"
    fi
    echo "    Check your IP:  curl https://ifconfig.me"
    echo "    Stop proxy:     systemctl stop sing-box"
    echo ""
}

# ============================================================================
# Main
# ============================================================================

main() {
    print_header
    check_root
    check_os
    parse_vless_link "$1"
    detect_arch
    choose_dns
    choose_logging
    install_dependencies
    install_sing_box
    write_config
    create_systemd_service
    enable_tun_module
    start_service
    verify_connection
    print_summary
}

main "$@"
