#!/bin/sh
# sing-box setup - OS auto-detection wrapper
# Usage: ./setup.sh
# The script will prompt for the VLESS link interactively

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo ""
echo "${CYAN}Detecting operating system...${NC}"

# Detect OS (order matters: check Devuan before Debian/Ubuntu since Devuan is Debian-based)
if [ -f /etc/alpine-release ]; then
    OS="alpine"
    OS_NAME="Alpine Linux $(cat /etc/alpine-release)"
elif [ -f /etc/devuan_version ]; then
    OS="devuan"
    OS_NAME="Devuan Linux $(cat /etc/devuan_version)"
elif grep -qi devuan /etc/os-release 2>/dev/null; then
    OS="devuan"
    OS_NAME="Devuan Linux"
elif grep -qi ubuntu /etc/os-release 2>/dev/null; then
    OS="debian"
    OS_NAME="Ubuntu $(grep VERSION_ID /etc/os-release 2>/dev/null | cut -d'"' -f2)"
elif [ -f /etc/debian_version ]; then
    OS="debian"
    OS_NAME="Debian Linux $(cat /etc/debian_version)"
elif grep -qi debian /etc/os-release 2>/dev/null; then
    OS="debian"
    OS_NAME="Debian Linux"
else
    echo "${RED}Error: Unsupported operating system${NC}"
    echo ""
    echo "This script supports:"
    echo "  - Alpine Linux"
    echo "  - Debian Linux"
    echo "  - Ubuntu Linux"
    echo "  - Devuan Linux"
    echo ""
    echo "For other distributions, please adapt the setup scripts manually."
    exit 1
fi

echo "${GREEN}Detected: ${OS_NAME}${NC}"
echo ""

# Check if required files exist
SETUP_SCRIPT="${SCRIPT_DIR}/setup-${OS}.sh"
COMMON_SCRIPT="${SCRIPT_DIR}/common.sh"

if [ ! -f "$COMMON_SCRIPT" ]; then
    echo "${RED}Error: common.sh not found${NC}"
    echo ""
    echo "Make sure common.sh is in the same directory as this script."
    exit 1
fi

if [ ! -f "$SETUP_SCRIPT" ]; then
    echo "${RED}Error: Setup script not found: ${SETUP_SCRIPT}${NC}"
    echo ""
    echo "Make sure setup-alpine.sh, setup-debian.sh, and setup-devuan.sh are in the same directory."
    exit 1
fi

# Install bash if needed (Alpine doesn't have it by default)
if [ "$OS" = "alpine" ]; then
    if ! command -v bash >/dev/null 2>&1; then
        echo "${CYAN}Installing bash...${NC}"
        apk update >/dev/null
        apk add --no-cache bash >/dev/null
        echo "  ${GREEN}bash installed${NC}"
        echo ""
    fi
fi

# Run the appropriate setup script
exec "$SETUP_SCRIPT" "$@"
