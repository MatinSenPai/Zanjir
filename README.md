# زنجیر⛓️ - Zanjir Matrix Server

**Self-hosted, secure, decentralized messaging server powered by Matrix protocol**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-ready-blue.svg)](https://www.docker.com/)
[![Matrix](https://img.shields.io/badge/matrix-dendrite-green.svg)](https://matrix.org/)

---

[![zanjir-screens-copy.webp](https://i.postimg.cc/yYjVzZzN/zanjir-screens-copy.webp)](https://postimg.cc/9r43dz03)

## Video Tutorial

[![Zanjir Project Introduction](https://i.postimg.cc/0Qq8qTFm/zanjir-copy.webp)](https://youtu.be/ZKTOs9y6rpw)

**📖 [Persian Version (نسخه فارسی)](README-FA.md)**

---
## 📋 Table of Contents

- [Features](#features)
- [Quick Start](#quick-start)
- [Installation](#installation)
- [User Guide](#user-guide)
- [Admin Panel](#admin-panel)
- [Voice/Video Calls](#voicevideo-calls)
- [Custom Port](#custom-port)
- [Troubleshooting](#troubleshooting)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

---

## ✨ Features

| Feature | Description |
|---------|-------------|
| 🔐 **Open Registration** | Users can self-register via web interface |
| 👑 **Admin Panel** | Web-based admin dashboard with audit logging |
| 📞 **Voice/Video Calls** | TURN server for reliable NAT traversal |
| 🔧 **Custom Ports** | Configurable HTTPS/HTTP ports (no 443 conflict) |
| 📱 **Element Web** | Modern, responsive Matrix client |
| 🇮🇷 **Persian UI** | Fully translated interface |
| 🐳 **Docker Powered** | One-command installation |
| 🔒 **Auto HTTPS** | Let's Encrypt or self-signed certificates |

---

## 🚀 Quick Start

**Requirements:**
- Ubuntu 20.04+ or Debian 11+
- 2GB RAM minimum
- Domain name (or IP address)
- Ports: 80, 443 (or custom), 3478, 5349 (UDP)

**One-line installation:**

```bash
git clone https://github.com/MatinSenPai/zanjir.git ~/zanjir
cd ~/zanjir
sudo bash install.sh
```

**Access:**
- **Web App**: `https://your-domain.com`
- **Admin Panel**: `https://your-domain.com/admin`

---

## 📦 Installation

### Step 1: Clone Repository

```bash
git clone https://github.com/MatinSenPai/zanjir.git
cd zanjir
```

### Step 2: Run Installer

```bash
sudo bash install.sh
```

**Installation prompts:**

1. **Server address** - Your domain or IP (e.g., `matrix.example.com` or `185.123.45.67`)
2. **Admin email** - For SSL certificates (domain mode only)
3. **HTTPS port** - Default: 443 (press Enter), or custom (e.g., 8443)

### Step 3: Create Admin User

After installation completes:

```bash
docker exec -it zanjir-dendrite /usr/bin/create-account \
    --config /etc/dendrite/dendrite.yaml \
    --username YOUR_USERNAME \
    --admin
```

**Example:**

```bash
docker exec -it zanjir-dendrite /usr/bin/create-account \
    --config /etc/dendrite/dendrite.yaml \
    --username admin \
    --admin
```

You'll be prompted to set a password.

---

## 👤 User Guide

### Registration

1. Visit `https://your-domain.com`
2. Click **"Create account"**
3. Fill in username and password
4. Start messaging!

### Using Element Web

- **Create Room**: Click `+` button → New Room
- **Invite Users**: Room settings → Invite users → Enter `@username:your-domain.com`
- **Send Messages**: Type and press Enter
- **Voice Call**: Click phone icon in room header
- **Video Call**: Click video icon in room header

### Mobile Apps

**Android:**
- [Element (Play Store)](https://play.google.com/store/apps/details?id=im.vector.app)
- [Element (F-Droid)](https://f-droid.org/packages/im.vector.app/)

**iOS:**
- [Element (App Store)](https://apps.apple.com/app/element-messenger/id1083446067)

**Configuration:**
- Homeserver URL: `https://your-domain.com`
- Identity server: Leave blank

---

## 🛡️ Admin Panel

### Access

Visit: `https://your-domain.com/admin`

Login with your admin account credentials.

### Features

#### Dashboard
- Total users count
- Active users
- Total rooms

#### User Management
- View all users
- Disable user accounts
- Delete users
- View user status

#### Audit Logs
- Track all admin actions
- Timestamps and IP addresses
- Target user tracking
- Detailed action logs

### Admin Actions

**Disable a user:**
1. Go to `Users` page
2. Find user
3. Click **"Disable"**

**Delete a user:**
1. Go to `Users` page
2. Find user
3. Click **"Delete"** → Confirm

All actions are automatically logged and visible in the **Logs** page.

---

## 📞 Voice/Video Calls

Zanjir includes a TURN server (coturn) for reliable voice/video calls.

### How It Works

TURN server helps users behind NAT/firewalls connect:
- Direct P2P when possible
- TURN relay when necessary
- Automatic fallback

### Firewall Configuration

**Required ports:**

| Port | Protocol | Purpose |
|------|----------|---------|
| 3478 | UDP | STUN/TURN |
| 5349 | UDP | TURN-TLS |

**UFW example:**

```bash
sudo ufw allow 3478/udp
sudo ufw allow 5349/udp
```

### Testing Calls

1. Create two accounts
2. Create a room, invite both users
3. Click phone/video icon
4. Accept call on other end

---

## 🔧 Custom Port

If port 443 is already in use, you can use a custom port.

### Installation with Custom Port

During `install.sh`, enter your desired port:

```
HTTPS port (default: 443): 8443
```

This will:
- Use port 8443 for HTTPS
- Use port 8080 for HTTP (auto-calculated)
- Update all configurations

### Accessing with Custom Port

```
https://your-domain.com:8443
```

### Changing Port After Installation

1. Edit `.env`:
   ```bash
   nano .env
   ```
2. Change `HTTPS_PORT` and `HTTP_PORT`
3. Restart services:
   ```bash
   docker compose down
   docker compose up -d
   ```

---

## 🔍 Troubleshooting

### Common Issues

#### Docker Installation fails (Iranian VPS)

**Error:** `connection refused` to `download.docker.com`

**Solution:** Script automatically uses Iranian mirrors:
- `docker.arvancloud.ir`
- `registry.docker.ir`

#### Registration not working

**Check:**
1. Verify `dendrite.yaml`: `registration_disabled: false`
2. Check `element-config.json`: `"UIFeature.registration": true`
3. Restart containers:
   ```bash
   docker compose restart
   ```

#### Voice calls failing

**Solutions:**
1. Check TURN server is running:
   ```bash
   docker ps | grep coturn
   ```
2. Verify firewall allows UDP 3478, 5349
3. Check TURN secret in `.env` matches `dendrite.yaml`

#### Admin panel login fails

**Solutions:**
1. Verify user is admin:
   ```bash
   docker exec -it zanjir-dendrite /usr/bin/create-account \
       --config /etc/dendrite/dendrite.yaml \
       --username YOUR_USERNAME \
       --admin
   ```
2. Check admin container logs:
   ```bash
   docker logs zanjir-admin
   ```

#### Port already in use

**Solution:** Use custom port during installation, or change port in `.env`

---

## ❓ FAQ

### General

**Q: Can I use an IP address instead of domain?**  
A: Yes! The installer detects IP mode and uses self-signed certificates.

**Q: Is federation enabled?**  
A: No, Zanjir is designed for isolated single-server deployment.

**Q: Can users video call externally?**  
A: Only within your Zanjir server (federation disabled).

### Security

**Q: How are passwords stored?**  
A: Bcrypt hashed in PostgreSQL.

**Q: Is end-to-end encryption supported?**  
A: Yes! Element/Matrix supports E2EE by default.

**Q: What about audit logs?**  
A: Admin actions logged in SQLite (`admin/audit_log.db`).

### Performance

**Q: How many users can it handle?**  
A: Dendrite is lightweight. A 2GB VPS can handle ~100-500 users.

**Q: What about backups?**  
A: Backup Docker volumes:
```bash
docker run --rm \
  -v zanjir-postgres-data:/data \
  -v $(pwd):/backup \
  ubuntu tar czf /backup/postgres-backup.tar.gz /data
```

---

## 🤝 Contributing

Contributions welcome! Please:
1. Fork the repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

---

## 📄 License

MIT License - see [LICENSE](LICENSE) file

---

## 🙏 Acknowledgments

- [Matrix.org](https://matrix.org/) - Open protocol
- [Dendrite](https://github.com/matrix-org/dendrite) - Lightweight homeserver
- [Element](https://element.io/) - Web client
- [Coturn](https://github.com/coturn/coturn) - TURN server
- [Caddy](https://caddyserver.com/) - Reverse proxy

---

## 📞 Support

- **GitHub Issues**: [Report bugs](https://github.com/MatinSenPai/zanjir/issues)
- **Discussions**: [Ask questions](https://github.com/MatinSenPai/zanjir/discussions)

---

**Made with ❤️ for secure, private communication**
