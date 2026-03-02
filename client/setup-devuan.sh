#!/usr/bin/env bash
# sing-box setup for Devuan Linux
# Usage: ./setup-devuan.sh
# The script will prompt for the VLESS link interactively

set -e

# Get script directory and source common functions
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/common.sh"

# ============================================================================
# Devuan-specific Functions
# ============================================================================

print_header() {
    echo ""
    echo "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo "${CYAN}║${NC}        sing-box Installer for Devuan Linux               ${CYAN}║${NC}"
    echo "${CYAN}║${NC}        Route all traffic through VLESS + REALITY         ${CYAN}║${NC}"
    echo "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

check_os() {
    if [ ! -f /etc/devuan_version ] && ! grep -qi devuan /etc/os-release 2>/dev/null; then
        echo "${RED}Error: This script is for Devuan Linux only${NC}"
        echo "For Alpine, use: ./setup-alpine.sh"
        echo "For Debian/Ubuntu, use: ./setup-debian.sh"
        exit 1
    fi
}

detect_init_system() {
    # Check for OpenRC
    if command -v openrc >/dev/null 2>&1 || [ -d /etc/runlevels ]; then
        INIT_SYSTEM="openrc"
    # Check for systemd (shouldn't happen on Devuan, but just in case)
    elif command -v systemctl >/dev/null 2>&1 && systemctl --version >/dev/null 2>&1; then
        INIT_SYSTEM="systemd"
        echo "${RED}Error: systemd detected. This script is for non-systemd systems.${NC}"
        exit 1
    # Default to sysvinit
    else
        INIT_SYSTEM="sysvinit"
    fi
    echo "  Init system: $INIT_SYSTEM"
}

install_dependencies() {
    echo ""
    echo "${CYAN}Installing dependencies...${NC}"
    apt-get update -qq
    apt-get install -y -qq curl tar ca-certificates
}

create_init_script() {
    if [ "$INIT_SYSTEM" = "openrc" ]; then
        create_openrc_service
    else
        create_sysvinit_service
    fi
}

start_service() {
    echo ""
    echo "${CYAN}Starting sing-box service...${NC}"

    if [ "$INIT_SYSTEM" = "openrc" ]; then
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
    else
        # Enable at boot (SysVinit)
        update-rc.d sing-box defaults 2>/dev/null || true

        # Stop if running
        /etc/init.d/sing-box stop 2>/dev/null || true

        # Start
        if /etc/init.d/sing-box start; then
            echo "  ${GREEN}Service started successfully${NC}"
        else
            echo "  ${RED}Failed to start service${NC}"
            echo "  Check logs: tail -f $LOG_FILE"
            exit 1
        fi
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

    if [ "$INIT_SYSTEM" = "openrc" ]; then
        echo "  Service: rc-service sing-box {start|stop|restart|status}"
        echo ""
        echo "  Commands:"
        echo "    Check status:   rc-service sing-box status"
        if [ "$ENABLE_LOGS" = "y" ]; then
            echo "    View logs:      tail -f $LOG_FILE"
        fi
        echo "    Check your IP:  curl https://ifconfig.me"
        echo "    Stop proxy:     rc-service sing-box stop"
    else
        echo "  Service: /etc/init.d/sing-box {start|stop|restart|status}"
        echo ""
        echo "  Commands:"
        echo "    Check status:   /etc/init.d/sing-box status"
        if [ "$ENABLE_LOGS" = "y" ]; then
            echo "    View logs:      tail -f $LOG_FILE"
        fi
        echo "    Check your IP:  curl https://ifconfig.me"
        echo "    Stop proxy:     /etc/init.d/sing-box stop"
    fi
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
    detect_init_system
    choose_dns
    choose_logging
    install_dependencies
    install_sing_box
    write_config
    create_init_script
    enable_tun_module
    start_service
    verify_connection
    print_summary
}

main "$@"
