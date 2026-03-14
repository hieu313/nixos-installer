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
    read -r WIFI_SSID < /dev/tty

    echo -ne "  ${WHITE}Password       : ${NC}"
    read -rs WIFI_PSK < /dev/tty
    echo ""
    echo ""

    print_step "Connecting to \"${WIFI_SSID}\"..."

    
    wpa_cli -i wlan0 <<EOF &>/dev/null
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
    read -r retry_choice < /dev/tty
    if [[ "$retry_choice" == "q" || "$retry_choice" == "Q" ]]; then
      abort "WiFi connection failed. Aborted by user."
    fi
    echo ""
  done
}
# -----------------------------------------------------------------------------
# Check if script is run as root
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  echo ""
  echo -e "  ${RED}✗  Script must be run as root.${NC}"
  echo -e "  ${DIM}Run: sudo bash install.sh${NC}"
  echo ""
  exit 1
fi
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

# =============================================================================
# PHASE 2 — DISK DETECTION & PARTITION
# =============================================================================
print_header "Phase 2 — Disk Detection & Partition"

# --- Detect disks ---
print_step "Detecting available disks..."

mapfile -t DISKS < <(lsblk -dnpo NAME,SIZE,TYPE | awk '$3 == "disk" {print $1}')
mapfile -t DISK_INFO < <(lsblk -dnpo NAME,SIZE,MODEL,TYPE | awk '$NF == "disk" {$NF=""; print}')

if [[ ${#DISKS[@]} -eq 0 ]]; then
  print_fail "No disks detected"
  abort "No disks found. Check your VM storage configuration."
fi

print_ok "Found ${#DISKS[@]} disk(s)"
echo ""

echo -e "  ${WHITE}Available disks:${NC}"
echo -e "  ${DIM}────────────────────────────────────────────${NC}"
for idx in "${!DISK_INFO[@]}"; do
  echo -e "  ${CYAN}[$((idx + 1))]${NC}  ${DISK_INFO[$idx]}"
done
echo -e "  ${DIM}────────────────────────────────────────────${NC}"
echo ""

# --- Select disk ---
if [[ ${#DISKS[@]} -eq 1 ]]; then
  DISK="${DISKS[0]}"
  print_info "Auto-selected: ${DISK} (only disk available)"
else
  while true; do
    echo -ne "  ${WHITE}Select disk [1-${#DISKS[@]}]: ${NC}"
    read -r disk_choice < /dev/tty
    if [[ "$disk_choice" =~ ^[0-9]+$ ]] && (( disk_choice >= 1 && disk_choice <= ${#DISKS[@]} )); then
      DISK="${DISKS[$((disk_choice - 1))]}"
      break
    fi
    echo -e "  ${RED}Invalid choice. Try again.${NC}"
  done
fi

DISK_SIZE=$(lsblk -dnpo SIZE "$DISK" | xargs)
echo ""
print_info "Target: ${DISK} (${DISK_SIZE})"

# --- Confirmation ---
echo ""
echo -e "  ${RED}┌─────────────────────────────────────────────┐${NC}"
echo -e "  ${RED}│  ⚠  WARNING: ALL DATA ON ${DISK} WILL BE   ${NC}"
echo -e "  ${RED}│     PERMANENTLY ERASED!                     ${NC}"
echo -e "  ${RED}└─────────────────────────────────────────────┘${NC}"
echo ""
echo -ne "  ${WHITE}Type ${YELLOW}YES${WHITE} to confirm: ${NC}"
read -r confirm < /dev/tty
if [[ "${confirm,,}" != "yes" ]]; then
  abort "Disk operation cancelled by user."
fi
echo ""

# --- Partition (MBR: boot 512M + swap 2G + root rest) ---
print_step "Partitioning ${DISK} (MBR: boot + swap + root)..."

parted -s "$DISK" -- \
  mklabel msdos \
  mkpart primary ext4 1MiB 513MiB \
  set 1 boot on \
  mkpart primary linux-swap 513MiB 2561MiB \
  mkpart primary ext4 2561MiB 100%

print_ok "Partitioned ${DISK}"

if [[ "$DISK" == *"nvme"* ]]; then
  PART_BOOT="${DISK}p1"
  PART_SWAP="${DISK}p2"
  PART_ROOT="${DISK}p3"
else
  PART_BOOT="${DISK}1"
  PART_SWAP="${DISK}2"
  PART_ROOT="${DISK}3"
fi

# --- Format ---
print_step "Formatting ${PART_BOOT} (ext4 — boot)..."
mkfs.ext4 -qFL boot "$PART_BOOT"
print_ok "Formatted ${PART_BOOT} (boot)"

print_step "Formatting ${PART_SWAP} (swap)..."
mkswap -qL swap "$PART_SWAP"
print_ok "Formatted ${PART_SWAP} (swap)"

print_step "Formatting ${PART_ROOT} (ext4 — root)..."
mkfs.ext4 -qFL nixos "$PART_ROOT"
print_ok "Formatted ${PART_ROOT} (root)"

# --- Mount ---
print_step "Mounting filesystems to /mnt..."

mount "$PART_ROOT" /mnt
mkdir -p /mnt/boot
mount "$PART_BOOT" /mnt/boot
swapon "$PART_SWAP"

print_ok "Mounted all filesystems"

# --- Summary ---
echo ""
print_info "boot : ${PART_BOOT} → /mnt/boot (512M)"
print_info "swap : ${PART_SWAP} (2G)"
print_info "root : ${PART_ROOT} → /mnt      (rest)"
echo ""
print_success_box "Disk ready — proceeding to installation"
echo ""