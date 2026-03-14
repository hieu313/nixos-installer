#!/usr/bin/env bash
# =============================================================================
# NixOS Auto Installer — VMware / BIOS / Flakes
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Colors & symbols
# -----------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
DIM='\033[2m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WAIT="${YELLOW}…${NC}"
INFO="${CYAN}→${NC}"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
print_header() {
  echo ""
  echo -e "${BLUE}╔══════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║${NC}  ${WHITE}$1${NC}"
  echo -e "${BLUE}╚══════════════════════════════════════════════════╝${NC}"
  echo ""
}

print_step() {
  echo -e "  ${WAIT}  ${WHITE}$1${NC}"
}

print_ok() {
  echo -e "\033[1A\033[2K  ${PASS}  ${GREEN}$1${NC}"
}

print_fail() {
  echo -e "\033[1A\033[2K  ${FAIL}  ${RED}$1${NC}"
}

print_info() {
  echo -e "  ${INFO}  ${DIM}$1${NC}"
}

print_error_box() {
  echo ""
  echo -e "  ${RED}┌─────────────────────────────────────────────┐${NC}"
  echo -e "  ${RED}│  ✗  $1${NC}"
  echo -e "  ${RED}└─────────────────────────────────────────────┘${NC}"
  echo ""
}

print_success_box() {
  echo ""
  echo -e "  ${GREEN}┌─────────────────────────────────────────────┐${NC}"
  echo -e "  ${GREEN}│  ✓  $1${NC}"
  echo -e "  ${GREEN}└─────────────────────────────────────────────┘${NC}"
  echo ""
}

print_warn_box() {
  echo ""
  echo -e "  ${YELLOW}┌─────────────────────────────────────────────┐${NC}"
  echo -e "  ${YELLOW}│  ⚠  $1${NC}"
  echo -e "  ${YELLOW}└─────────────────────────────────────────────┘${NC}"
  echo ""
}

abort() {
  print_error_box "$1"
  echo -e "  ${DIM}Script aborted. Please check and try again.${NC}"
  echo ""
  exit 1
}

# -----------------------------------------------------------------------------
# WiFi setup via wpa_supplicant
# -----------------------------------------------------------------------------
setup_wifi() {
  print_warn_box "No network — WiFi Setup"

  echo -e "  ${INFO}  Starting wpa_supplicant..."
  systemctl start wpa_supplicant 2>/dev/null || true
  sleep 1

  print_step "Scanning WiFi networks..."
  wpa_cli -i wlan0 scan &>/dev/null
  sleep 3

  SSID_LIST=$(wpa_cli -i wlan0 scan_results \
    | awk 'NR>1 && $NF != "" && $NF != "[P2P]" {print $NF}' \
    | sort -u)

  print_ok "Scan complete"
  echo ""

  if [[ -z "$SSID_LIST" ]]; then
    echo -e "  ${YELLOW}⚠  No WiFi networks found. Enter SSID manually.${NC}"
    echo ""
  else
    echo -e "  ${WHITE}Available WiFi networks:${NC}"
    echo -e "  ${DIM}────────────────────────────────${NC}"
    i=1
    while IFS= read -r ssid; do
      echo -e "  ${CYAN}[$i]${NC}  $ssid"
      ((i++))
    done <<< "$SSID_LIST"
    echo -e "  ${DIM}────────────────────────────────${NC}"
    echo ""
  fi

  while true; do
    echo -ne "  ${WHITE}SSID (WiFi name): ${NC}"
    read -r WIFI_SSID

    echo -ne "  ${WHITE}Password       : ${NC}"
    read -rs WIFI_PSK
    echo ""
    echo ""

    print_step "Connecting to \"${WIFI_SSID}\"..."

    
    wpa_cli -i wlan0 <<EOF
add_network
set_network 0 ssid "${WIFI_SSID}"
set_network 0 psk "${WIFI_PSK}"
set_network 0 key_mgmt WPA-PSK
enable_network 0
quit
EOF

    sleep 4

    dhclient wlan0 &>/dev/null || true
    sleep 2

    if ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
      print_ok "WiFi connected successfully!"
      break
    fi

    print_fail "WiFi connection failed"
    echo ""
    echo -ne "  ${WHITE}Retry (r) or Abort (q)? [r/q]: ${NC}"
    read -r retry_choice
    if [[ "$retry_choice" == "q" || "$retry_choice" == "Q" ]]; then
      abort "WiFi connection failed. Aborted by user."
    fi
    echo ""
  done
}

# -----------------------------------------------------------------------------
# Banner
# -----------------------------------------------------------------------------
clear
echo ""
echo -e "${CYAN}  ███╗   ██╗██╗██╗  ██╗ ██████╗ ███████╗${NC}"
echo -e "${CYAN}  ████╗  ██║██║╚██╗██╔╝██╔═══██╗██╔════╝${NC}"
echo -e "${CYAN}  ██╔██╗ ██║██║ ╚███╔╝ ██║   ██║███████╗${NC}"
echo -e "${CYAN}  ██║╚██╗██║██║ ██╔██╗ ██║   ██║╚════██║${NC}"
echo -e "${CYAN}  ██║ ╚████║██║██╔╝ ██╗╚██████╔╝███████║${NC}"
echo -e "${CYAN}  ╚═╝  ╚═══╝╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝${NC}"
echo ""
echo -e "  ${DIM}Auto Installer  ·  VMware  ·  BIOS  ·  Flakes${NC}"
echo ""
echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# =============================================================================
# PHASE 1 — NETWORK CHECK
# =============================================================================
print_header "Phase 1 — Network Check"

# --- Test 1: ping 1.1.1.1 ---
print_step "Checking internet connection (ping 1.1.1.1)..."
if ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
  print_ok "Internet connection OK"
else
  print_fail "No ethernet connection"
  setup_wifi
fi

# --- Test 2: DNS resolution ---
print_step "Checking DNS (cache.nixos.org)..."
if getent hosts cache.nixos.org &>/dev/null; then
  print_ok "DNS resolution OK"
else
  print_fail "DNS resolution failed"
  abort "DNS error. Add nameserver to /etc/resolv.conf:\n  echo 'nameserver 1.1.1.1' > /etc/resolv.conf"
fi

# --- Test 3: Reach Nix binary cache ---
print_step "Checking Nix binary cache..."
if curl -fsS --max-time 5 https://cache.nixos.org/nix-cache-info &>/dev/null; then
  print_ok "Nix binary cache reachable"
else
  print_fail "Cannot reach cache.nixos.org"
  abort "Nix cache unavailable. Check your network or try again later."
fi

# --- Summary ---
print_success_box "All network checks PASSED — proceeding"
print_info "Host: $(hostname)"
print_info "IP  : $(ip -4 addr show scope global | grep inet | awk '{print $2}' | head -1)"
echo ""