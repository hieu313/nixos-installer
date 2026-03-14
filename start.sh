#!/usr/bin/env bash
# =============================================================================
# NixOS Auto Installer — VMware / BIOS / Flakes
# =============================================================================

set -euo pipefail

export NIX_CONFIG="experimental-features = nix-command flakes"

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

# --- Idempotency check ---
if mountpoint -q /mnt 2>/dev/null; then
  EXISTING_ROOT=$(findmnt -no SOURCE /mnt 2>/dev/null || true)
  EXISTING_BOOT=$(findmnt -no SOURCE /mnt/boot 2>/dev/null || true)
  EXISTING_SWAP=$(swapon --show=NAME --noheadings 2>/dev/null | head -1 || true)

  if [[ -n "$EXISTING_ROOT" && -n "$EXISTING_BOOT" && -n "$EXISTING_SWAP" ]]; then
    print_warn_box "Existing partition layout detected"
    print_info "root : ${EXISTING_ROOT} → /mnt"
    print_info "boot : ${EXISTING_BOOT} → /mnt/boot"
    print_info "swap : ${EXISTING_SWAP}"
    echo ""
    echo -ne "  ${WHITE}Use existing layout (y) or Re-partition (n)? [y/n]: ${NC}"
    read -r reuse_choice < /dev/tty

    if [[ "$reuse_choice" == "y" || "$reuse_choice" == "Y" || -z "$reuse_choice" ]]; then
      DISK=$(lsblk -npo PKNAME "$EXISTING_ROOT" | head -1)
      if [[ "$DISK" == *"nvme"* ]]; then
        PART_BOOT="${DISK}p1"; PART_SWAP="${DISK}p2"; PART_ROOT="${DISK}p3"
      else
        PART_BOOT="${DISK}1"; PART_SWAP="${DISK}2"; PART_ROOT="${DISK}3"
      fi
      echo ""
      print_success_box "Reusing existing layout — skipping partition"
      echo ""

      # Jump past partitioning
      PHASE2_SKIP=1
    fi
  fi
fi

if [[ "${PHASE2_SKIP:-0}" -ne 1 ]]; then

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

fi # end PHASE2_SKIP

# --- Summary ---
echo ""
print_info "boot : ${PART_BOOT} → /mnt/boot (512M)"
print_info "swap : ${PART_SWAP} (2G)"
print_info "root : ${PART_ROOT} → /mnt      (rest)"
echo ""
print_success_box "Disk ready — proceeding to installation"
echo ""

# =============================================================================
# PHASE 3 — NIXOS INSTALLATION
# =============================================================================
print_header "Phase 3 — NixOS Installation"

# --- Generate hardware config ---
print_step "Generating hardware configuration..."
nixos-generate-config --root /mnt
print_ok "Generated /mnt/etc/nixos/hardware-configuration.nix"

FLAKE_DIR="/mnt/etc/nixos"
HARDWARE_CFG="/mnt/etc/nixos/hardware-configuration.nix"

# --- Idempotency: reuse existing flake? ---
PHASE3_SKIP=0
if [[ -f "${FLAKE_DIR}/flake.nix" ]]; then
  print_warn_box "Existing flake detected at ${FLAKE_DIR}"
  echo -ne "  ${WHITE}Use existing flake (y) or Reconfigure (n)? [y/n]: ${NC}"
  read -r flake_reuse < /dev/tty
  if [[ "$flake_reuse" == "y" || "$flake_reuse" == "Y" || -z "$flake_reuse" ]]; then
    PHASE3_SKIP=1
    print_info "Reusing existing flake"
  fi
fi

if [[ "$PHASE3_SKIP" -ne 1 ]]; then

  # --- Choose mode ---
  echo ""
  echo -e "  ${WHITE}How do you want to configure NixOS?${NC}"
  echo -e "  ${DIM}────────────────────────────────────────────${NC}"
  echo -e "  ${CYAN}[A]${NC}  Generate minimal flake (first-time install)"
  echo -e "  ${CYAN}[B]${NC}  Clone from existing dotfiles repo"
  echo -e "  ${DIM}────────────────────────────────────────────${NC}"
  echo ""
  echo -ne "  ${WHITE}Choice [a/b]: ${NC}"
  read -r install_mode < /dev/tty
  install_mode="${install_mode,,}"

  if [[ "$install_mode" != "a" && "$install_mode" != "b" ]]; then
    install_mode="a"
  fi

  # -----------------------------------------------------------------------
  # Mode A — Generate minimal flake from scratch
  # -----------------------------------------------------------------------
  if [[ "$install_mode" == "a" ]]; then
    echo ""
    echo -ne "  ${WHITE}Hostname : ${NC}"
    read -r NIXOS_HOST < /dev/tty
    NIXOS_HOST="${NIXOS_HOST:-nixos-vm}"

    echo -ne "  ${WHITE}Username : ${NC}"
    read -r NIXOS_USER < /dev/tty
    NIXOS_USER="${NIXOS_USER:-user}"
    echo ""

    print_step "Generating flake.nix for \"${NIXOS_HOST}\"..."

    cat > "${FLAKE_DIR}/flake.nix" <<FLAKE
{
  description = "NixOS — ${NIXOS_HOST}";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: {
    nixosConfigurations.${NIXOS_HOST} = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./hardware-configuration.nix
        ./configuration.nix
      ];
    };
  };
}
FLAKE
    print_ok "Generated flake.nix"

    print_step "Generating configuration.nix..."

    cat > "${FLAKE_DIR}/configuration.nix" <<'CONF_HEAD'
{ config, pkgs, ... }:

{
CONF_HEAD

    cat >> "${FLAKE_DIR}/configuration.nix" <<CONF_BODY
  networking.hostName = "${NIXOS_HOST}";

  boot.loader.grub = {
    enable = true;
    device = "${DISK}";
  };

  time.timeZone = "Asia/Ho_Chi_Minh";

  users.users.${NIXOS_USER} = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    initialPassword = "changeme";
  };

  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    htop
  ];

  services.openssh.enable = true;

  system.stateVersion = "24.11";
}
CONF_BODY
    print_ok "Generated configuration.nix"

    # nix flake requires a git repo to read flake.nix
    git -C "$FLAKE_DIR" init -q
    git -C "$FLAKE_DIR" add -A

  # -----------------------------------------------------------------------
  # Mode B — Clone from existing repo
  # -----------------------------------------------------------------------
  else
    echo ""
    echo -e "  ${WHITE}Enter your NixOS flake repository URL:${NC}"
    echo -e "  ${DIM}  e.g. https://github.com/user/nixos-config${NC}"
    echo -e "  ${DIM}  e.g. git@github.com:user/nixos-config.git${NC}"
    echo ""
    echo -ne "  ${WHITE}Flake repo URL: ${NC}"
    read -r FLAKE_REPO < /dev/tty

    if [[ -z "$FLAKE_REPO" ]]; then
      abort "No flake repo URL provided."
    fi

    print_step "Cloning flake into ${FLAKE_DIR}..."

    cp "$HARDWARE_CFG" /tmp/hardware-configuration.nix
    rm -rf "$FLAKE_DIR"

    if ! git clone "$FLAKE_REPO" "$FLAKE_DIR" 2>/dev/null; then
      print_fail "Clone failed"
      abort "Failed to clone ${FLAKE_REPO}. Check the URL and try again."
    fi
    print_ok "Cloned flake repository"

    print_step "Injecting hardware-configuration.nix into flake..."
    HARDWARE_DEST=$(find "$FLAKE_DIR" -name "hardware-configuration.nix" -not -path "*/.git/*" | head -1)
    if [[ -n "$HARDWARE_DEST" ]]; then
      cp /tmp/hardware-configuration.nix "$HARDWARE_DEST"
      print_ok "Replaced ${HARDWARE_DEST}"
    else
      cp /tmp/hardware-configuration.nix "${FLAKE_DIR}/hardware-configuration.nix"
      print_ok "Copied to ${FLAKE_DIR}/hardware-configuration.nix"
    fi
  fi

fi # end PHASE3_SKIP

# --- Detect hostname target ---
echo ""
FLAKE_HOSTS=$(nix flake show "path:${FLAKE_DIR}" --json --no-write-lock-file 2>/dev/null \
  | jq -r '.nixosConfigurations // {} | keys[]' 2>/dev/null || true)

if [[ -z "${NIXOS_HOST:-}" ]]; then
  if [[ -n "$FLAKE_HOSTS" ]]; then
    echo -e "  ${WHITE}Available NixOS configurations:${NC}"
    echo -e "  ${DIM}────────────────────────────────${NC}"
    i=1
    mapfile -t HOST_LIST <<< "$FLAKE_HOSTS"
    for h in "${HOST_LIST[@]}"; do
      echo -e "  ${CYAN}[$i]${NC}  $h"
      ((i++))
    done
    echo -e "  ${DIM}────────────────────────────────${NC}"
    echo ""

    if [[ ${#HOST_LIST[@]} -eq 1 ]]; then
      NIXOS_HOST="${HOST_LIST[0]}"
      print_info "Auto-selected: ${NIXOS_HOST}"
    else
      while true; do
        echo -ne "  ${WHITE}Select config [1-${#HOST_LIST[@]}] or type name: ${NC}"
        read -r host_choice < /dev/tty
        if [[ "$host_choice" =~ ^[0-9]+$ ]] && (( host_choice >= 1 && host_choice <= ${#HOST_LIST[@]} )); then
          NIXOS_HOST="${HOST_LIST[$((host_choice - 1))]}"
          break
        elif [[ -n "$host_choice" ]]; then
          NIXOS_HOST="$host_choice"
          break
        fi
        echo -e "  ${RED}Invalid choice. Try again.${NC}"
      done
    fi
  else
    echo -ne "  ${WHITE}Hostname (flake target): ${NC}"
    read -r NIXOS_HOST < /dev/tty
    if [[ -z "$NIXOS_HOST" ]]; then
      abort "No hostname provided."
    fi
  fi
fi

echo ""
print_info "Installing: ${FLAKE_DIR}#${NIXOS_HOST}"
echo ""

# --- nixos-install ---
echo ""
echo -e "  ${WAIT}  ${WHITE}Running nixos-install (this may take a while)...${NC}"
echo ""

if ! nixos-install --root /mnt --flake "${FLAKE_DIR}#${NIXOS_HOST}" --no-root-passwd; then
  echo ""
  echo -e "  ${FAIL}  ${RED}nixos-install failed${NC}"
  abort "Installation failed. Check the output above for errors."
fi

echo ""
echo -e "  ${PASS}  ${GREEN}nixos-install completed successfully${NC}"

# --- Set root password ---
echo ""
echo -e "  ${WHITE}Set root password for the new system:${NC}"
while ! nixos-enter --root /mnt --command "passwd root" < /dev/tty; do
  echo -e "  ${RED}Passwords did not match. Try again.${NC}"
done
echo -e "  ${PASS}  ${GREEN}Root password set${NC}"

if [[ -n "${NIXOS_USER:-}" ]]; then
  echo ""
  print_info "User \"${NIXOS_USER}\" initial password: changeme"
  print_info "Change it after first login with: passwd"
fi

# --- Done ---
print_success_box "NixOS installation complete!"
echo ""
print_info "Flake  : ${FLAKE_DIR}#${NIXOS_HOST}"
print_info "Root   : ${PART_ROOT} → /mnt"
print_info "Boot   : ${PART_BOOT} → /mnt/boot"
echo ""
echo -e "  ${YELLOW}┌─────────────────────────────────────────────┐${NC}"
echo -e "  ${YELLOW}│  Ready to reboot into your new system!      ${NC}"
echo -e "  ${YELLOW}│  Run: ${WHITE}reboot${YELLOW}                               ${NC}"
echo -e "  ${YELLOW}└─────────────────────────────────────────────┘${NC}"
echo ""