#!/usr/bin/env bash
# sing-box setup for Alpine Linux
# Usage: ./setup-alpine.sh
# The script will prompt for the VLESS link interactively

set -e

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ============================================================================
# Alpine-specific Functions
# ============================================================================

print_header() {
    echo ""
    echo "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}║${NC}        sing-box Installer for Alpine Linux              ${CYAN}║${NC}"
    echo "${CYAN}║${NC}        Route all traffic through VLESS + REALITY        ${CYAN}║${NC}"
    echo "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_os() {
    if [ ! -f /etc/alpine-release ]; then
        echo "${RED}Error: This script is for Alpine Linux only${NC}"
        echo "For Debian/Ubuntu, use: ./setup-debian.sh"
        echo "For Devuan, use: ./setup-devuan.sh"
        exit 1
    fi
}

install_dependencies() {
    echo ""
    echo "${CYAN}Installing dependencies...${NC}"
    apk update
    apk add --no-cache curl tar ca-certificates
}

start_service() {
    echo ""
    echo "${CYAN}Starting sing-box service...${NC}"

    # Add to default runlevel
    rc-update add sing-box default 2>/dev/null || true

    # Stop if running
    rc-service sing-box stop 2>/dev/null || true

    # Start
    if rc-service sing-box start; then
        echo "  ${GREEN}Service started successfully${NC}"
    else
        echo "  ${RED}Failed to start service${NC}"
        echo "  Check logs: tail -f $LOG_FILE"
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
    echo "  Service: rc-service sing-box {start|stop|restart|status}"
    echo ""
    echo "  Commands:"
    echo "    Check status:   rc-service sing-box status"
    if [ "$ENABLE_LOGS" = "y" ]; then
        echo "    View logs:      tail -f $LOG_FILE"
    fi
    echo "    Check your IP:  curl https://ifconfig.me"
    echo "    Stop proxy:     rc-service sing-box stop"
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
    create_openrc_service
    enable_tun_module
    start_service
    verify_connection
    print_summary
}

main "$@"
