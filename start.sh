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
  echo -e "  ${DIM}Script dừng lại. Kiểm tra lại và chạy lại.${NC}"
  echo ""
  exit 1
}

# -----------------------------------------------------------------------------
# WiFi setup via wpa_supplicant
# -----------------------------------------------------------------------------
setup_wifi() {
  print_warn_box "Không có mạng — Thiết lập WiFi"

  echo -e "  ${INFO}  Khởi động wpa_supplicant..."
  systemctl start wpa_supplicant 2>/dev/null || true
  sleep 1

  # Scan và list SSID
  print_step "Đang scan mạng WiFi..."
  wpa_cli -i wlan0 scan &>/dev/null
  sleep 3

  SSID_LIST=$(wpa_cli -i wlan0 scan_results \
    | awk 'NR>1 && $NF != "" && $NF != "[P2P]" {print $NF}' \
    | sort -u)

  print_ok "Scan hoàn tất"
  echo ""

  if [[ -z "$SSID_LIST" ]]; then
    echo -e "  ${YELLOW}⚠  Không tìm thấy mạng WiFi nào. Nhập SSID thủ công.${NC}"
    echo ""
  else
    echo -e "  ${WHITE}Danh sách mạng WiFi:${NC}"
    echo -e "  ${DIM}────────────────────────────────${NC}"
    i=1
    while IFS= read -r ssid; do
      echo -e "  ${CYAN}[$i]${NC}  $ssid"
      ((i++))
    done <<< "$SSID_LIST"
    echo -e "  ${DIM}────────────────────────────────${NC}"
    echo ""
  fi

  # Nhập SSID
  echo -ne "  ${WHITE}SSID (tên WiFi): ${NC}"
  read -r WIFI_SSID

  # Nhập password (ẩn input)
  echo -ne "  ${WHITE}Password      : ${NC}"
  read -rs WIFI_PSK
  echo ""
  echo ""

  print_step "Đang kết nối tới \"${WIFI_SSID}\"..."

  # Dùng wpa_cli để kết nối
  wpa_cli -i wlan0 <<EOF
add_network
set_network 0 ssid "${WIFI_SSID}"
set_network 0 psk "${WIFI_PSK}"
set_network 0 key_mgmt WPA-PSK
enable_network 0
quit
EOF

  # Chờ kết nối
  sleep 4

  # Xin IP qua DHCP
  dhclient wlan0 &>/dev/null || true
  sleep 2

  # Kiểm tra lại
  if ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
    print_ok "Kết nối WiFi thành công!"
  else
    print_fail "Kết nối WiFi thất bại"
    abort "Không kết nối được WiFi. Kiểm tra lại SSID / password."
  fi
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
print_step "Kiểm tra kết nối internet (ping 1.1.1.1)..."
if ping -c 2 -W 3 1.1.1.1 &>/dev/null; then
  print_ok "Kết nối internet OK"
else
  print_fail "Không có kết nối ethernet"
  setup_wifi
fi

# --- Test 2: DNS resolution ---
print_step "Kiểm tra DNS (cache.nixos.org)..."
if getent hosts cache.nixos.org &>/dev/null; then
  print_ok "DNS phân giải OK"
else
  print_fail "DNS không phân giải được"
  abort "DNS lỗi. Thêm nameserver vào /etc/resolv.conf:\n  echo 'nameserver 1.1.1.1' > /etc/resolv.conf"
fi

# --- Test 3: Reach Nix binary cache ---
print_step "Kiểm tra Nix binary cache..."
if curl -fsS --max-time 5 https://cache.nixos.org/nix-cache-info &>/dev/null; then
  print_ok "Nix binary cache reachable"
else
  print_fail "Không kết nối được cache.nixos.org"
  abort "Nix cache không khả dụng. Kiểm tra lại mạng hoặc thử lại sau."
fi

# --- Summary ---
print_success_box "Tất cả kiểm tra mạng đều PASS — tiếp tục cài đặt"
print_info "Host: $(hostname)"
print_info "IP  : $(ip -4 addr show scope global | grep inet | awk '{print $2}' | head -1)"
echo ""