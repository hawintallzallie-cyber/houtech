# HouTech Network Appliance — Deployment System

HouTech is a local network security service based in Richmond/Sugar Land, Texas. This repository contains everything needed to provision a HouTech network appliance on any mini PC — from a fully automated Debian installer to a complete Pi-hole deployment with custom HouTech branding.

---

## What It Does

A technician plugs a Ventoy USB into any mini PC, boots from it, and walks away. The system installs Debian 13, configures the full HouTech network stack automatically, and is ready to deploy to a customer's home network within 15–25 minutes — zero manual steps required.

The deployed appliance provides:
- **Network-wide ad blocking** via Pi-hole DNS filtering
- **Whole-home coverage** — blocks ads on every device, no per-device setup
- **DNS privacy** — upstream queries routed through Cloudflare (1.1.1.1) and Google (8.8.8.8)
- **Remote management** via RDP (port 3389) and Pi-hole web UI (port 8080)
- **Hardened security** — UFW firewall, Fail2Ban intrusion protection, SSH hardening
- **Power resilience** — auto-boots after outages, auto-restarts services if they crash
- **HouTech branded UI** — Pi-hole admin interface rebranded as HouTech with custom logo, colors, and links

---

## Repository Structure

```
hawintallzallie-cyber/houtech/
│
├── setup.sh                          ← Main provisioning script
├── preseed.cfg                       ← Debian unattended installer config
├── ventoy.json                       ← Ventoy USB boot config
│
└── custom-theme/
    ├── houtech.css                   ← Pi-hole UI theme stylesheet
    ├── houtech.js                    ← Pi-hole UI rebranding script
    ├── transparent-logo.png          ← HouTech H logo (login page)
    └── patch_login.sh                ← Login page patch script
```

---

## File Reference

### `setup.sh`
The core provisioning script. Run once on a fresh Debian 13 install. Downloads all assets from this GitHub repo and configures the full stack automatically. Split into 6 steps:

| Step | What It Does |
|------|-------------|
| 0 | Power resilience — auto-login, disable sleep, GRUB timeout=0, systemd watchdog, journald to RAM, fsck auto-repair |
| 1 | Static IP — auto-detects router gateway via 4 methods, assigns `[subnet].77` as static IP |
| 2 | Security — UFW firewall (ports 53, 80, 8080, 3389 open), Fail2Ban (15 attempts = 1hr ban), SSH hardening |
| 3 | Docker — installs Docker Engine, enables on boot |
| 4 | XRDP — installs remote desktop, enables on port 3389 |
| 5 | Pi-hole — deploys in Docker, sets password, injects HouTech theme/logo/JS, patches login page |
| 6 | Watchdog — systemd service that checks Pi-hole every 60s and restarts it if down |

**Run command:**
```bash
apt-get install -y curl && curl -fsSL https://raw.githubusercontent.com/hawintallzallie-cyber/houtech/main/setup.sh | bash
```

**Log file:** `/var/log/houtech-setup.log`

---

### `preseed.cfg`
Debian 13 (Trixie) unattended installer configuration. Answers every installer prompt automatically so the OS installs with zero interaction. Key settings:

- Locale: `en_US.UTF-8` / Timezone: `America/Chicago`
- Disk: full wipe, atomic partitioning
- User: `houtech` / Password: `houtech2024`
- Desktop: XFCE minimal
- Packages: curl, wget, git, sudo, ufw, xrdp, openssh-server, ca-certificates
- `late_command`: downloads `setup.sh` from GitHub and creates a `houtech-firstboot` systemd service that runs it on first boot

---

### `ventoy.json`
Ventoy USB boot configuration. Points Ventoy at `HouTech_Setup.iso` and passes all required kernel boot parameters inline so the installer never prompts for language, hostname, domain, or user credentials.

Key boot args passed: `auto=true`, `priority=critical`, `preseed/url=` (loads preseed direct from GitHub), locale, keyboard, hostname, domain, DEBIAN_FRONTEND=noninteractive.

---

### `custom-theme/houtech.css`
CSS stylesheet injected into Pi-hole's admin interface. Overrides the default dark theme with HouTech branding:

- Background: deep navy/black (`#0a0a14`, `#13132a`)
- Accent: purple (`#7c3aed`) and purple glow (`#a855f7`)
- Fonts: Share Tech Mono (monospace), Rajdhani (headings)
- Stat cards: purple instead of bright blue/red/orange/green
- All Pi-hole default grays replaced with HouTech dark palette

Injected into: `default-dark.css` and `default-darker.css` inside the Pi-hole Docker container.

---

### `custom-theme/houtech.js`
JavaScript rebranding script injected into Pi-hole's admin UI. Runs on every page load (including the login page) and:

- Replaces all "Pi-hole" text with "HouTech" throughout the UI
- Replaces all Pi-hole links (`pi-hole.net`, `discourse.pi-hole.net`, `docs.pi-hole.net`, `github.com/pi-hole`) with `https://houtech.org`
- Replaces input placeholders and element attributes containing Pi-hole references
- Updates the browser tab title
- Uses a MutationObserver to catch dynamically loaded content

Injected as a standalone file into `/var/www/html/admin/scripts/js/houtech.js` and loaded via script tags in `footer.lp` and `login.lp`.

---

### `custom-theme/transparent-logo.png`
The HouTech "H" logo in purple. Replaces the Pi-hole raspberry logo on the login page. Copied into `/var/www/html/admin/img/logo.png` inside the Docker container.

---

### `custom-theme/patch_login.sh`
Shell script that patches `login.lp` inside the Pi-hole container to:

- Replace the raspberry logo `img` tag with the HouTech logo (200×200)
- Remove the "Pi-hole" title text below the logo
- Replace all footer links with `houtech.org`
- Replace the donate section with HouTech branding
- Replace all remaining Pi-hole text references in the forgot password and 2FA sections

---

## USB Setup

The deployment USB requires only 2 files:

```
Ventoy USB/
├── HouTech_Setup.iso    ← Fresh Debian 13 Trixie netinstall ISO (renamed)
└── ventoy.json          ← Boot config (from this repo)
```

**To prepare:**
1. Install [Ventoy](https://ventoy.net) on a USB drive
2. Download [Debian 13 Trixie netinstall ISO](https://cdimage.debian.org/cdimage/trixie_di_rc1/amd64/iso-cd/) and rename to `HouTech_Setup.iso`
3. Copy `HouTech_Setup.iso` and `ventoy.json` to the USB root

---

## Deployment Flow

```
1. Plug USB into mini PC → boot from USB
2. Ventoy loads → selects ISO automatically (3s timeout)
3. Debian installs silently (~10 min) → reboots
4. First boot → houtech-firstboot.service runs setup.sh
5. setup.sh provisions entire stack (~15 min)
6. Device ready at [subnet].77
```

---

## Default Credentials

| Service | Username | Password |
|---------|----------|----------|
| OS Login | houtech | houtech2024 |
| Pi-hole Admin | — | houtech2024 |
| RDP | houtech | houtech2024 |

> ⚠️ Change all passwords after first deployment.

---

## Access After Deploy

| Service | Address |
|---------|---------|
| Pi-hole Admin UI | `http://[device-ip]:8080/admin` |
| Remote Desktop (RDP) | `[device-ip]:3389` |
| Device IP | Auto-assigned as `[subnet].77` (e.g. `192.168.1.77`) |

---

## Firewall Rules (UFW)

| Port | Protocol | Purpose |
|------|----------|---------|
| 53 | TCP/UDP | DNS (Pi-hole) |
| 80 | TCP | HTTP |
| 8080 | TCP | Pi-hole Admin UI |
| 3389 | TCP | RDP Remote Desktop |
| All others | — | BLOCKED |

---

## Post-Deploy Checklist

- [ ] Change OS password: `passwd houtech`
- [ ] Change Pi-hole password: `docker exec -it pihole pihole setpassword [newpassword]`
- [ ] Set router DNS server to device IP (e.g. `192.168.1.77`)
- [ ] Set BIOS: Power Management → Restore on AC Power Loss = **Power On**
- [ ] Test ad blocking on a client device

---

## Internal Tools

| URL | Purpose |
|-----|---------|
| `https://houtech.org/Izu` | Technician referral link (Izu) |
| `https://houtech.org/Rayyan` | Technician referral link (Rayyan) |
| `https://houtech.org/[secret]` | Internal deployment reference page |

---

## Key Paths (On Device)

| Path | Purpose |
|------|---------|
| `/var/log/houtech-setup.log` | Full setup log |
| `/var/log/houtech-watchdog.log` | Pi-hole watchdog log |
| `/opt/houtech-setup/` | Setup assets directory |
| `/opt/pihole/etc-pihole/` | Pi-hole config (persistent) |
| `/opt/pihole/etc-dnsmasq.d/` | dnsmasq config (persistent) |
