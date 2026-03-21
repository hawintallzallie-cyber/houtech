#!/bin/bash
# ============================================================
#  HOUTECH NETWORK STACK — AUTO PROVISIONING SCRIPT
#  USB Label: HOUTECH_SETUP
#  Run this once on a fresh Linux mini PC install
# ============================================================
set -e

LOG="/var/log/houtech-setup.log"
SCRIPT_DIR="/opt/houtech-setup"

# Trap any error and log the line number before exiting
trap 'log "ERROR: Setup failed at line $LINENO — check log above for details."; exit 1' ERR

# Ensure setup directory always exists with assets from GitHub
mkdir -p /opt/houtech-setup/custom-theme
curl -fsSL "https://raw.githubusercontent.com/hawintallzallie-cyber/houtech/main/custom-theme/houtech.css" \
  -o /opt/houtech-setup/custom-theme/houtech.css 2>/dev/null || true
curl -fsSL "https://raw.githubusercontent.com/hawintallzallie-cyber/houtech/main/custom-theme/houtech.js" \
  -o /opt/houtech-setup/custom-theme/houtech.js 2>/dev/null || true
curl -fsSL "https://raw.githubusercontent.com/hawintallzallie-cyber/houtech/main/custom-theme/transparent-logo.png" \
  -o /opt/houtech-setup/custom-theme/transparent-logo.png 2>/dev/null || true

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG"
}

log "============================================"
log " HOUTECH SETUP STARTING"
log "============================================"

# ------------------------------------------------------------
# STEP 0: POWER RESILIENCE & AUTO-RECOVERY SETTINGS
# ------------------------------------------------------------
log "[0/5] Configuring power resilience and auto-recovery..."

# ── 0a. Auto-login on boot (no password prompt blocking startup) ──
# Detect the primary non-root user
MAIN_USER=$(getent passwd {1000..1100} | head -1 | cut -d: -f1)
if [ -n "$MAIN_USER" ]; then
  AUTOLOGIN_FILE="/etc/systemd/system/getty@tty1.service.d/autologin.conf"
  if grep -q "autologin $MAIN_USER" "$AUTOLOGIN_FILE" 2>/dev/null; then
    log "Auto-login already configured for $MAIN_USER — skipping."
  else
    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > "$AUTOLOGIN_FILE" <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $MAIN_USER --noclear %I \$TERM
EOF
    log "Auto-login configured for user: $MAIN_USER"
  fi
fi

# ── 0b. Disable sleep, suspend, hibernate, and hybrid-sleep ──
systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
log "Sleep/suspend/hibernate disabled."

# ── 0c. Prevent system from sleeping on lid close or idle (logind) ──
sed -i 's/^#*HandleLidSwitch=.*/HandleLidSwitch=ignore/' /etc/systemd/logind.conf
sed -i 's/^#*HandleLidSwitchExternalPower=.*/HandleLidSwitchExternalPower=ignore/' /etc/systemd/logind.conf
sed -i 's/^#*HandleSuspendKey=.*/HandleSuspendKey=ignore/' /etc/systemd/logind.conf
sed -i 's/^#*HandleHibernateKey=.*/HandleHibernateKey=ignore/' /etc/systemd/logind.conf
sed -i 's/^#*IdleAction=.*/IdleAction=ignore/' /etc/systemd/logind.conf
sed -i 's/^#*PowerKeyAction=.*/PowerKeyAction=ignore/' /etc/systemd/logind.conf
# Append if lines didn't exist
grep -q "^HandleLidSwitch=" /etc/systemd/logind.conf || echo "HandleLidSwitch=ignore" >> /etc/systemd/logind.conf
grep -q "^IdleAction=" /etc/systemd/logind.conf       || echo "IdleAction=ignore"       >> /etc/systemd/logind.conf
# Reload daemon config only — do NOT restart logind (it kills the active session/display)
systemctl daemon-reload 2>/dev/null || true
log "Lid close, idle, and power key actions disabled (takes effect on next boot)."

# ── 0d. Disable screen blanking and DPMS (display power saving) ──
if command -v xset &>/dev/null; then
  xset s off 2>/dev/null || true
  xset -dpms 2>/dev/null || true
  xset s noblank 2>/dev/null || true
fi
# Persist via X11 config
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/10-houtech-nodpms.conf <<EOF
Section "ServerFlags"
  Option "BlankTime"  "0"
  Option "StandbyTime" "0"
  Option "SuspendTime" "0"
  Option "OffTime"    "0"
EndSection

Section "Monitor"
  Identifier "Monitor0"
  Option "DPMS" "false"
EndSection
EOF
log "Screen blanking and DPMS disabled."

# ── 0e. Set GRUB to auto-boot after power loss (no menu wait) ──
if [ -f /etc/default/grub ]; then
  sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' /etc/default/grub
  sed -i 's/^GRUB_TIMEOUT_STYLE=.*/GRUB_TIMEOUT_STYLE=hidden/' /etc/default/grub
  # Remove 'quiet splash' so boot issues are visible if needed
  sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=""/' /etc/default/grub
  update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
  log "GRUB timeout set to 0 — instant boot after power restoration."
fi

# ── 0f. Enable systemd auto-restart on failed services ──
# Create a global systemd override for auto-restart on all services
mkdir -p /etc/systemd/system.conf.d
cat > /etc/systemd/system.conf.d/houtech-restart.conf <<EOF
[Manager]
DefaultRestartSec=5s
EOF
log "Global systemd restart delay set to 5s."

# ── 0g. Watchdog timer — auto-reboot if system hangs ──
if [ -f /etc/systemd/system.conf ]; then
  sed -i 's/^#*RuntimeWatchdogSec=.*/RuntimeWatchdogSec=30/' /etc/systemd/system.conf
  sed -i 's/^#*RebootWatchdogSec=.*/RebootWatchdogSec=10min/' /etc/systemd/system.conf
  grep -q "^RuntimeWatchdogSec=" /etc/systemd/system.conf || echo "RuntimeWatchdogSec=30"   >> /etc/systemd/system.conf
  grep -q "^RebootWatchdogSec="  /etc/systemd/system.conf || echo "RebootWatchdogSec=10min" >> /etc/systemd/system.conf
fi
log "Systemd watchdog enabled — system will auto-reboot if it hangs for 30s."

# ── 0h. Set BIOS/EFI "restore on power loss" via kernel param ──
# Most mini PCs respect the AC power restore setting in BIOS.
# This note is logged as a reminder since it requires BIOS config.
log "REMINDER: Set BIOS → Power Management → 'Restore on AC Power Loss' = [Power On]"
log "          This ensures the device boots automatically after a power outage."

# ── 0i. Filesystem — reduce journal writes to protect against corrupt shutdowns ──
# Set journald to volatile (RAM only) to reduce disk wear and corruption risk
mkdir -p /etc/systemd/journald.conf.d
cat > /etc/systemd/journald.conf.d/houtech-journal.conf <<EOF
[Journal]
Storage=volatile
Compress=yes
SystemMaxUse=50M
EOF
systemctl restart systemd-journald 2>/dev/null || true
log "systemd journal set to volatile (RAM) — protects against corrupt shutdowns."

# ── 0j. Enable fsck auto-repair on unclean shutdown ──
# tune2fs sets max mount count and interval to trigger fsck after dirty boot
ROOT_DEV=$(findmnt -n -o SOURCE /)
if [[ "$ROOT_DEV" == /dev/* ]]; then
  tune2fs -c 1 -i 0 "$ROOT_DEV" 2>/dev/null || true
  log "fsck auto-repair enabled on $ROOT_DEV — runs after every unclean shutdown."
fi

# ── 0k. Docker restart policy already set to 'unless-stopped' ──
# Pi-hole container uses --restart unless-stopped (set in Step 4)
# Docker daemon itself is enabled via systemctl enable docker (set in Step 2)
log "Docker and Pi-hole are configured to auto-restart after power loss."

log "Power resilience configuration complete."

# ------------------------------------------------------------
# STEP 1: SET STATIC IP ON ETH0 (192.168.77.77)
# ------------------------------------------------------------
log "[1/6] Configuring static IP on Ethernet interface..."

# Detect ethernet interface name (eth0, enp1s0, ens3, etc.)
ETH_IFACE=$(ip link show | awk -F': ' '/^[0-9]+: e/{print $2; exit}')
log "Detected ethernet interface: $ETH_IFACE"

# ── Auto-detect the router's gateway IP from DHCP lease ──
# First make sure we have a DHCP lease to read from
log "Detecting router gateway automatically..."
GATEWAY=""

# Method 1: Read from current routing table (most reliable)
GATEWAY=$(ip route show default 2>/dev/null | awk '/default via/{print $3}' | head -1)

# Method 2: Read from NetworkManager DHCP lease as fallback
if [ -z "$GATEWAY" ]; then
  GATEWAY=$(nmcli -t -f IP4.GATEWAY device show "$ETH_IFACE" 2>/dev/null | cut -d: -f2 | head -1)
fi

# Method 3: Read from dhclient lease file as fallback
if [ -z "$GATEWAY" ]; then
  GATEWAY=$(grep -r "routers" /var/lib/dhcp/ 2>/dev/null | awk '{print $NF}' | tr -d ';' | head -1)
fi

# Method 4: Try common router IPs as last resort
if [ -z "$GATEWAY" ]; then
  for gw in 192.168.1.1 192.168.0.1 10.0.0.1 172.16.0.1; do
    if ping -c 1 -W 1 "$gw" &>/dev/null; then
      GATEWAY="$gw"
      log "Gateway found via ping: $GATEWAY"
      break
    fi
  done
fi

# Determine subnet from gateway IP
if [ -n "$GATEWAY" ]; then
  # Extract the first three octets from gateway (e.g. 192.168.1 from 192.168.1.1)
  SUBNET=$(echo "$GATEWAY" | cut -d. -f1-3)
  STATIC_IP="${SUBNET}.77"
  log "Router gateway detected: $GATEWAY"
  log "Subnet detected: ${SUBNET}.0/24"
  log "Assigning static IP: $STATIC_IP"
else
  # Absolute fallback — use default values and warn
  GATEWAY="192.168.1.1"
  STATIC_IP="192.168.1.77"
  log "WARNING: Could not detect gateway — using fallback: $GATEWAY"
  log "WARNING: If this is wrong, update manually with nmcli after setup."
fi

# ── Apply static IP using detected values ──
# Detect if using NetworkManager or netplan or systemd-networkd
if command -v nmcli &>/dev/null; then
  log "Using NetworkManager for static IP..."
  # Check if already configured with the correct IP
  EXISTING_IP=$(nmcli -t -f IP4.ADDRESS con show "houtech-static" 2>/dev/null | cut -d: -f2 | cut -d/ -f1)
  if [ "$EXISTING_IP" = "$STATIC_IP" ]; then
    log "Static IP ${STATIC_IP} already configured in NetworkManager — skipping."
  else
    nmcli con delete "houtech-static" 2>/dev/null || true
    nmcli con add type ethernet \
      con-name "houtech-static" \
      ifname "$ETH_IFACE" \
      ipv4.method manual \
      ipv4.addresses "${STATIC_IP}/24" \
      ipv4.gateway "$GATEWAY" \
      ipv4.dns "127.0.0.1,1.1.1.1" \
      connection.autoconnect yes \
      connection.autoconnect-priority 100
    nmcli con up "houtech-static"
  fi

elif [ -d /etc/netplan ]; then
  log "Using Netplan for static IP..."
  # cat > overwrites so this is always idempotent
  cat > /etc/netplan/99-houtech-static.yaml <<EOF
network:
  version: 2
  ethernets:
    $ETH_IFACE:
      dhcp4: false
      addresses:
        - ${STATIC_IP}/24
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses: [127.0.0.1, 1.1.1.1]
EOF
  netplan apply

else
  log "Using /etc/network/interfaces for static IP..."
  # Guard against duplicate entries on re-run
  if grep -q "Houtech static IP" /etc/network/interfaces 2>/dev/null; then
    log "Static IP already present in /etc/network/interfaces — skipping."
  else
    cat >> /etc/network/interfaces <<EOF

# Houtech static IP
auto $ETH_IFACE
iface $ETH_IFACE inet static
  address $STATIC_IP
  netmask 255.255.255.0
  gateway $GATEWAY
  dns-nameservers 127.0.0.1 1.1.1.1
EOF
    ifdown "$ETH_IFACE" 2>/dev/null || true
    ifup "$ETH_IFACE" 2>/dev/null || true
  fi
fi

log "Static IP ${STATIC_IP} configured on $ETH_IFACE (gateway: $GATEWAY)"

# ------------------------------------------------------------
# STEP 2: SECURITY HARDENING
# ------------------------------------------------------------
log "[2/6] Configuring firewall, Fail2Ban, and SSH hardening..."

# ── 2a. Check for port 53 conflict (systemd-resolved) ──
log "Checking for port 53 conflicts..."
PORT53_PROC=$(ss -tlnup 'sport = :53' 2>/dev/null | grep ':53' | awk '{print $NF}' | head -1)
if echo "$PORT53_PROC" | grep -q "systemd-resolve"; then
  log "WARNING: systemd-resolved is occupying port 53!"
  log "WARNING: Pi-hole DNS will NOT work until this is resolved."
  echo ""
  echo "╔══════════════════════════════════════════════════════════════╗"
  echo "║  ⚠️  PORT 53 CONFLICT DETECTED — ACTION REQUIRED             ║"
  echo "║                                                              ║"
  echo "║  systemd-resolved is holding port 53.                       ║"
  echo "║  Pi-hole DNS will be blocked until fixed.                   ║"
  echo "║                                                              ║"
  echo "║  Attempting automatic fix now...                            ║"
  echo "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  # Auto-fix: disable DNSStubListener
  sed -i 's/^#*DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf
  grep -q "^DNSStubListener=" /etc/systemd/resolved.conf || echo "DNSStubListener=no" >> /etc/systemd/resolved.conf
  ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
  systemctl restart systemd-resolved 2>/dev/null || true
  log "Port 53 auto-fix applied — DNSStubListener disabled."
  log "Verify with: ss -tlnup sport = :53"
else
  log "Port 53 is free — Pi-hole DNS will bind successfully."
fi

# ── 2b. Install UFW and set strict firewall rules ──
log "Installing and configuring UFW firewall..."
apt-get install -y -qq ufw

# Check if UFW is already active with the correct rules before resetting
if ufw status | grep -q "8080/tcp" && ufw status | grep -q "Status: active"; then
  log "UFW already configured with correct rules — skipping reset."
else
  ufw --force reset
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow 53/tcp   comment 'Pi-hole DNS TCP'
  ufw allow 53/udp   comment 'Pi-hole DNS UDP'
  ufw allow 80/tcp   comment 'HTTP'
  ufw allow 8080/tcp comment 'Pi-hole Admin UI'
  ufw allow 3389/tcp comment 'XRDP Remote Desktop'
  ufw --force enable
  log "UFW firewall active. Allowed: 53 (DNS), 80 (HTTP), 8080 (Pi-hole UI), 3389 (RDP)"
  log "All other inbound ports are BLOCKED."
fi

# ── 2c. Install and configure Fail2Ban ──
log "Installing Fail2Ban..."
apt-get install -y -qq fail2ban

cat > /etc/fail2ban/jail.d/houtech.conf <<'JAILEOF'
[DEFAULT]
bantime  = 1h
findtime = 10m
maxretry = 15
backend  = systemd

[sshd]
enabled  = true
port     = ssh
maxretry = 15
bantime  = 1h
logpath  = %(sshd_log)s

[xrdp]
enabled  = true
port     = 3389
maxretry = 15
bantime  = 1h
filter   = xrdp
logpath  = /var/log/xrdp.log

[pihole-admin]
enabled  = true
port     = http,8080
maxretry = 15
bantime  = 1h
filter   = apache-auth
logpath  = /var/log/lighttpd/error.log
JAILEOF

cat > /etc/fail2ban/filter.d/xrdp.conf <<'FILTEREOF'
[Definition]
failregex = .*\[xrdp\].*\[ERROR\].*password check failed.*<HOST>
            .*\[xrdp\].*\[WARN\].*xrdp_mm_process_login_response.*<HOST>
ignoreregex =
FILTEREOF

systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2Ban active — 15 failed attempts triggers a 1-hour ban."
log "Protected: SSH, XRDP (RDP port 3389), Pi-hole Admin UI"

# ── 2d. Disable root SSH login and harden SSH config ──
log "Hardening SSH configuration..."
if [ -f /etc/ssh/sshd_config ]; then
  sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/'        /etc/ssh/sshd_config
  sed -i 's/^#*MaxAuthTries.*/MaxAuthTries 4/'               /etc/ssh/sshd_config
  sed -i 's/^#*LoginGraceTime.*/LoginGraceTime 30/'          /etc/ssh/sshd_config
  grep -q "^PermitRootLogin"  /etc/ssh/sshd_config || echo "PermitRootLogin no"  >> /etc/ssh/sshd_config
  grep -q "^MaxAuthTries"     /etc/ssh/sshd_config || echo "MaxAuthTries 4"      >> /etc/ssh/sshd_config
  grep -q "^LoginGraceTime"   /etc/ssh/sshd_config || echo "LoginGraceTime 30"   >> /etc/ssh/sshd_config
  systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true
  log "Root SSH login DISABLED. MaxAuthTries=4. LoginGraceTime=30s."
else
  log "WARNING: sshd_config not found — SSH hardening skipped."
fi

log "Security hardening complete."

# ------------------------------------------------------------
# STEP 3: INSTALL DOCKER
# ------------------------------------------------------------
log "[3/6] Installing Docker..."

if command -v docker &>/dev/null; then
  log "Docker already installed — skipping."
else
  log "Installing Docker dependencies..."
  apt-get update -qq
  apt-get install -y -qq ca-certificates curl gnupg lsb-release

  log "Adding Docker GPG key and apt repository..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/debian/gpg \
    -o /etc/apt/keyrings/docker.asc
  chmod a+r /etc/apt/keyrings/docker.asc

  # Debian 13 Trixie is not yet in Docker's repo list — use bookworm packages
  # which are fully compatible. Detect version and fall back to bookworm if needed.
  DEBIAN_CODENAME=$(. /etc/os-release && echo "$VERSION_CODENAME")
  if [ "$DEBIAN_CODENAME" = "trixie" ] || [ "$DEBIAN_CODENAME" = "forky" ]; then
    DOCKER_CODENAME="bookworm"
    log "Debian $DEBIAN_CODENAME detected — using Docker bookworm repo for compatibility."
  else
    DOCKER_CODENAME="$DEBIAN_CODENAME"
  fi

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/debian $DOCKER_CODENAME stable" \
    | tee /etc/apt/sources.list.d/docker.list > /dev/null

  apt-get update -qq
  apt-get install -y -qq \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin

  systemctl enable docker
  systemctl start docker
  log "Docker installed successfully (repo: $DOCKER_CODENAME)."
fi

# ------------------------------------------------------------
# STEP 3: INSTALL XRDP
# ------------------------------------------------------------
log "[4/6] Installing XRDP for remote desktop..."

if command -v xrdp &>/dev/null && systemctl is-active --quiet xrdp; then
  log "XRDP already installed and running — skipping."
else
  apt-get install -y -qq xrdp

  # Allow XRDP through UFW if active
  if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
    ufw allow 3389/tcp
    log "UFW rule added for RDP port 3389"
  fi

  # Add xrdp user to ssl-cert group (required for certificate access)
  usermod -aG ssl-cert xrdp 2>/dev/null || true

  # Enable and start XRDP service
  systemctl enable xrdp
  systemctl restart xrdp
  log "XRDP installed and running on port 3389"
fi
log "Connect via: mstsc (Windows) or Remmina (Linux) → ${STATIC_IP}:3389"

# ------------------------------------------------------------
# STEP 4: DEPLOY PI-HOLE IN DOCKER
# ------------------------------------------------------------
log "[5/6] Deploying Pi-hole in Docker..."

mkdir -p /opt/pihole/etc-pihole
mkdir -p /opt/pihole/etc-dnsmasq.d

# Check if Pi-hole is already running and healthy
PIHOLE_RUNNING=$(docker inspect -f '{{.State.Running}}' pihole 2>/dev/null || echo "false")
if [ "$PIHOLE_RUNNING" = "true" ]; then
  log "Pi-hole container already running — skipping deployment."
else
  # Stop and remove any stopped/crashed container before re-creating
  docker stop pihole 2>/dev/null || true
  docker rm   pihole 2>/dev/null || true

  docker run -d \
    --name pihole \
    --restart unless-stopped \
    -e TZ="America/Chicago" \
    -e WEBPASSWORD="houtech2024" \
    -e PIHOLE_DNS_1="1.1.1.1" \
    -e PIHOLE_DNS_2="8.8.8.8" \
    -v /opt/pihole/etc-pihole:/etc/pihole \
    -v /opt/pihole/etc-dnsmasq.d:/etc/dnsmasq.d \
    -p 53:53/tcp \
    -p 53:53/udp \
    -p 8080:80 \
    --dns=127.0.0.1 \
    --dns=1.1.1.1 \
    pihole/pihole:latest

  log "Pi-hole container started. Waiting 20 seconds for initialization..."
  sleep 20

  # Force set Pi-hole web password
  docker exec pihole pihole setpassword houtech2024 2>/dev/null || \
  docker exec pihole pihole -a -p houtech2024 2>/dev/null || true
  log "Pi-hole web password set to: houtech2024"
fi

# ------------------------------------------------------------
# STEP 4b: INJECT HOUTECH CUSTOM THEME INTO PI-HOLE
# ------------------------------------------------------------
log "Injecting Houtech custom theme into Pi-hole..."

# Copy theme files into container
docker cp "$SCRIPT_DIR/custom-theme/houtech.css" pihole:/tmp/houtech.css
docker cp "$SCRIPT_DIR/custom-theme/houtech.js"  pihole:/tmp/houtech.js

# Inject CSS into the correct theme files (default-auto loads dark/darker)
docker exec pihole bash -c "
  for THEME in \
    /var/www/html/admin/style/themes/default-dark.css \
    /var/www/html/admin/style/themes/default-darker.css \
    /var/www/html/admin/style/pi-hole.css; do
    if [ -f \"\$THEME\" ]; then
      if ! grep -q 'HOUTECH PI-HOLE THEME' \"\$THEME\"; then
        cat /tmp/houtech.css >> \"\$THEME\"
        echo \"Injected CSS into \$THEME\"
      fi
    fi
  done
" && log "Houtech CSS injected into theme files." || log "WARNING: Could not inject CSS."

# Copy JS as standalone file — do NOT append to footer.js or login.js
docker exec pihole bash -c "cp /tmp/houtech.js /var/www/html/admin/scripts/js/houtech.js" && \
  log "Houtech JS copied." || log "WARNING: Could not copy JS."

# Inject script tag into footer.lp and header_authenticated.lp
docker exec pihole bash -c "
  for LUA in \
    /var/www/html/admin/scripts/lua/footer.lp \
    /var/www/html/admin/scripts/lua/header_authenticated.lp; do
    if [ -f \"\$LUA\" ]; then
      if ! grep -q 'houtech.js' \"\$LUA\"; then
        echo '<script src=\"<?=webhome?>scripts/js/houtech.js\"></script>' >> \"\$LUA\"
        echo \"Injected script tag into \$LUA\"
      fi
    fi
  done
  # Also inject into login.lp
  if ! grep -q 'houtech.js' /var/www/html/admin/login.lp; then
    sed -i 's|<script src=\"<?=pihole.fileversion.*login.js.*\"></script>|&\n<script src=\"<?=webhome?>scripts/js/houtech.js\"></script>|' /var/www/html/admin/login.lp
    echo 'Injected script tag into login.lp'
  fi
" && log "Houtech JS tags injected into .lp files." || log "WARNING: Could not inject JS tags."

# ── PATCH LOGIN PAGE ──────────────────────────────────────────
log "Patching login page..."
docker exec pihole bash -c "
  FILE=/var/www/html/admin/login.lp

  # Replace logo img
  sed -i 's|<img src=\"<?=webhome?>img/logo.svg\" alt=\"Pi-hole logo\" class=\"loginpage-logo\" width=\"140\" height=\"202\">|<img src=\"<?=webhome?>img/logo.png\" alt=\"HouTech logo\" class=\"loginpage-logo\" width=\"200\" height=\"200\" style=\"object-fit:contain;\">|g' \"\$FILE\"

  # Remove Pi-hole title text below logo
  sed -i 's|<div class=\"panel-title text-center\">.*logo-lg.*</div>||g' \"\$FILE\"

  # Replace footer links
  sed -i 's|href=\"https://docs.pi-hole.net/\"|href=\"https://houtech.org\"|g' \"\$FILE\"
  sed -i 's|href=\"https://github.com/pi-hole/\"|href=\"https://houtech.org\"|g' \"\$FILE\"
  sed -i 's|href=\"https://discourse.pi-hole.net/\"|href=\"https://houtech.org\"|g' \"\$FILE\"
  sed -i 's|Pi-hole Discourse|HouTech|g' \"\$FILE\"

  # Replace donate section
  sed -i 's|href=\"https://pi-hole.net/donate/\".*>|href=\"https://houtech.org\" rel=\"noopener noreferrer\" target=\"_blank\">|g' \"\$FILE\"
  sed -i 's|<i class=\"fa fa-heart text-red\"></i> Donate</a></strong> if you found this useful.|<i class=\"fa fa-shield\"></i> HouTech Network Solutions</a></strong>|g' \"\$FILE\"

  # Replace Pi-hole text
  sed -i 's|After installing Pi-hole for the first time|After installing HouTech for the first time|g' \"\$FILE\"
  sed -i 's|Your Pi-hole has two-factor|Your HouTech system has two-factor|g' \"\$FILE\"
  sed -i 's|log in to see Pi-hole diagnosis|log in to see HouTech diagnosis|g' \"\$FILE\"
  sed -i 's|pihole setpassword|houtech setpassword|g' \"\$FILE\"
" && log "Login page patched." || log "WARNING: Could not patch login page."

# ── COPY LOGO INTO PI-HOLE IMG DIRECTORY ─────────────────────
if [ -f "$SCRIPT_DIR/custom-theme/transparent-logo.png" ]; then
  docker cp "$SCRIPT_DIR/custom-theme/transparent-logo.png" pihole:/var/www/html/admin/img/logo.png 2>/dev/null || true
  log "Houtech logo injected into /img/."
fi

log "[6/6] Installing Pi-hole watchdog service..."

if systemctl is-active --quiet houtech-watchdog; then
  log "Pi-hole watchdog already installed and running — skipping."
else
  # Create a systemd service that checks Pi-hole every 60s and restarts if down
  cat > /etc/systemd/system/houtech-watchdog.service <<EOF
[Unit]
Description=Houtech Pi-hole Watchdog
After=docker.service network-online.target
Wants=network-online.target

[Service]
Type=simple
Restart=always
RestartSec=10
ExecStart=/bin/bash -c 'while true; do \
  if ! docker inspect -f "{{.State.Running}}" pihole 2>/dev/null | grep -q true; then \
    echo "[$(date)] Pi-hole down — restarting..." >> /var/log/houtech-watchdog.log; \
    docker start pihole 2>/dev/null || true; \
  fi; \
  sleep 60; \
done'

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable houtech-watchdog
  systemctl start houtech-watchdog
  log "Pi-hole watchdog service installed and running."
fi

log "============================================"
log " HOUTECH SETUP COMPLETE"
log "============================================"
log ""
log "  Pi-hole Admin UI  → http://${STATIC_IP}:8080/admin"
log "  Pi-hole Password  → houtech2024"
log "  RDP Access        → ${STATIC_IP}:3389"
log "  Static IP         → ${STATIC_IP} on $ETH_IFACE (gateway: $GATEWAY)"
log ""
log "  FIREWALL (UFW)"
log "  Open ports: 53 (DNS), 80 (HTTP), 8080 (Pi-hole), 3389 (RDP)"
log "  All other inbound ports: BLOCKED"
log ""
log "  FAIL2BAN"
log "  Max attempts: 15  |  Ban duration: 1 hour"
log "  Protected: SSH, RDP, Pi-hole Admin UI"
log "  Check bans: fail2ban-client status"
log ""
log "  SSH"
log "  Root login: DISABLED"
log "  Max auth tries: 4"
log ""
log "  Power Recovery    → Auto-boot on power restore (set BIOS too!)"
log "  Watchdog          → Pi-hole auto-restarts if it crashes"
log "  Watchdog Log      → /var/log/houtech-watchdog.log"
log ""
log "  !! Change your default password after first login !!"
log "============================================"
