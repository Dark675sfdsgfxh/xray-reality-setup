# sing-box Client Setup Guide

Route all system traffic through your VLESS + REALITY server on Linux.

## Supported Distributions

| Distro        | Init System                       | Script            |
|---------------|-----------------------------------|-------------------|
| Alpine Linux  | OpenRC                            | `setup-alpine.sh` |
| Debian Linux  | systemd                           | `setup-debian.sh` |
| Ubuntu Linux  | systemd                           | `setup-debian.sh` |
| Devuan Linux  | sysvinit / OpenRC (auto-detected) | `setup-devuan.sh` |

Use `setup.sh` to auto-detect OS and run the appropriate script.

---

## Quick Start (Automated)

### 1. Get Your VLESS Link

Run `xray-setup.sh` on your server and copy the VLESS share link. It looks like:

```
vless://UUID@SERVER:PORT?encryption=none&flow=xtls-rprx-vision&security=reality&sni=DEST&fp=chrome&pbk=PUBLIC_KEY&sid=SHORT_ID&type=tcp#NAME
```

Keep this link ready - the script will ask you to paste it.

### 2. Download and Run

**Option A: Auto-detect OS (recommended)**

```sh
# Download all scripts
curl -LO https://github.com/YOUR_REPO/raw/main/client/setup.sh
curl -LO https://github.com/YOUR_REPO/raw/main/client/common.sh
curl -LO https://github.com/YOUR_REPO/raw/main/client/setup-alpine.sh
curl -LO https://github.com/YOUR_REPO/raw/main/client/setup-debian.sh
curl -LO https://github.com/YOUR_REPO/raw/main/client/setup-devuan.sh
chmod +x setup*.sh

# Run - automatically detects Alpine, Debian, Ubuntu, or Devuan
./setup.sh
```

**Option B: Run OS-specific script directly**

```sh
# Alpine Linux
curl -LO https://github.com/YOUR_REPO/raw/main/client/setup-alpine.sh
chmod +x setup-alpine.sh
./setup-alpine.sh

# Debian / Ubuntu Linux
curl -LO https://github.com/YOUR_REPO/raw/main/client/setup-debian.sh
chmod +x setup-debian.sh
./setup-debian.sh

# Devuan Linux
curl -LO https://github.com/YOUR_REPO/raw/main/client/setup-devuan.sh
chmod +x setup-devuan.sh
./setup-devuan.sh
```

### 3. Enter Your VLESS Link

The script will prompt you to paste your VLESS link:

```
Enter your VLESS share link
(paste the link from xray-setup.sh output on your server)

  VLESS link: <paste your link here>
```

This interactive prompt avoids storing your credentials in bash history.

The script will then:
- Parse your VLESS link and generate config
- Prompt you to choose a DNS provider
- Prompt for logging preference (disabled by default)
- Install sing-box from GitHub releases
- Create and enable the init service
- Enable TUN kernel module
- Start routing all traffic through your server
- Verify the connection

### DNS Provider Selection

During setup, you'll be prompted to choose a DNS provider:

```
Choose DNS provider:

  1) DNS.SB          Germany   | No logging, DNSSEC
  2) Mullvad DNS     Sweden    | No logging, privacy-focused
  3) Cloudflare      USA       | Fast, no logging (Cloudflare policy)
  4) Google          USA       | Fast, logs for 24-48h
  5) Quad9           Zurich    | Malware blocking, DNSSEC
  6) AdGuard DNS     Cyprus    | Ad blocking, no logging

  Select DNS [1-6, default=1]:
```

DNS queries are routed through the VLESS tunnel and exit from your server's IP to the selected provider. For consistency, choose the same DNS provider you selected during server setup.

### Logging Preference

You'll be asked whether to enable logging:

```
╔══════════════════════════════════════════════════════════╗
║  Logging Preference                                      ║
╠══════════════════════════════════════════════════════════╣
║                                                          ║
║  Logs can help with troubleshooting but may contain      ║
║  connection metadata (timestamps, errors).               ║
║                                                          ║
║  For maximum privacy, keep logging disabled.             ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝

  Enable logging? [y/N]:
```

**Default: Disabled** - no connection data is stored.

When enabled, warnings and errors are logged to `/var/log/sing-box.log`.

### 3. Verify

```sh
# Check your public IP (should match server IP)
curl https://ifconfig.me
```

---

## Service Management

### Alpine Linux (OpenRC)

```sh
rc-service sing-box start     # Start
rc-service sing-box stop      # Stop
rc-service sing-box restart   # Restart
rc-service sing-box status    # Check status

rc-update add sing-box default    # Enable at boot
rc-update del sing-box default    # Disable at boot
```

### Debian / Ubuntu Linux (systemd)

```sh
systemctl start sing-box      # Start
systemctl stop sing-box       # Stop
systemctl restart sing-box    # Restart
systemctl status sing-box     # Check status

systemctl enable sing-box     # Enable at boot
systemctl disable sing-box    # Disable at boot

journalctl -u sing-box -f     # View logs
```

### Devuan Linux (SysVinit)

```sh
/etc/init.d/sing-box start    # Start
/etc/init.d/sing-box stop     # Stop
/etc/init.d/sing-box restart  # Restart
/etc/init.d/sing-box status   # Check status

update-rc.d sing-box defaults     # Enable at boot
update-rc.d sing-box remove       # Disable at boot
```

---

## File Locations

**Installed files:**

| File | Path |
|------|------|
| Config | `/etc/sing-box/config.json` |
| Logs | `/var/log/sing-box.log` (if enabled) |
| Binary | `/usr/local/bin/sing-box` |
| Service (Alpine/Devuan) | `/etc/init.d/sing-box` |
| Service (Debian) | `/etc/systemd/system/sing-box.service` |

**Setup scripts:**

| Script | Purpose |
|--------|---------|
| `setup.sh` | OS auto-detection wrapper |
| `common.sh` | Shared functions library |
| `setup-alpine.sh` | Alpine Linux (OpenRC) |
| `setup-debian.sh` | Debian/Ubuntu (systemd) |
| `setup-devuan.sh` | Devuan (SysVinit/OpenRC) |

---

## Verification Commands

```sh
# Check TUN interface exists
ip addr show sing-tun

# Check routing table
ip route show table main | grep sing-tun

# Check public IP
curl -s https://ifconfig.me

# View logs
tail -f /var/log/sing-box.log

# Validate config
sing-box check -c /etc/sing-box/config.json
```

---

## Troubleshooting

### TUN device not created

```sh
# Load TUN module
modprobe tun
lsmod | grep tun

# Alpine: install kernel if missing
apk add linux-lts
```

### Permission denied

sing-box requires root for TUN mode. Run the service as root or set capabilities:

```sh
setcap cap_net_admin,cap_net_bind_service=+ep /usr/local/bin/sing-box
```

### Connection timeout

1. Verify server is running and reachable
2. Check credentials match exactly (copy link again)
3. Ensure firewall allows outbound to server port

### DNS leaks

The default config routes DNS through the proxy. Verify at https://dnsleaktest.com/

---

## Optional: SOCKS/HTTP Proxy Mode

If you prefer application-level proxy instead of TUN (system-wide), edit `/etc/sing-box/config.json` and replace the `inbounds` section:

```json
"inbounds": [
  {
    "type": "socks",
    "tag": "socks-in",
    "listen": "127.0.0.1",
    "listen_port": 1080
  },
  {
    "type": "http",
    "tag": "http-in",
    "listen": "127.0.0.1",
    "listen_port": 8080
  }
]
```

Then configure applications to use:
- SOCKS5: `127.0.0.1:1080`
- HTTP: `127.0.0.1:8080`

Or set environment variables:

```sh
export http_proxy="http://127.0.0.1:8080"
export https_proxy="http://127.0.0.1:8080"
export all_proxy="socks5://127.0.0.1:1080"
```

---

## References

- [sing-box Documentation](https://sing-box.sagernet.org/)
- [sing-box GitHub](https://github.com/SagerNet/sing-box)
- [VLESS Protocol](https://xtls.github.io/en/config/outbounds/vless.html)
- [REALITY Protocol](https://github.com/XTLS/REALITY)
