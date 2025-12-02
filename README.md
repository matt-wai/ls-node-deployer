# 🐳 Lightsail Node Deployer

Auto-deploy **frps** and **Nginx Proxy Manager** on AWS Lightsail (or any Ubuntu/Debian server).

## Quick Start

### Lightsail Startup Script

```bash
git clone https://github.com/matt-wai/ls-node-deployer.git
cd ls-node-deployer
chmod +x setup.sh scripts/*.sh
./setup.sh --frps-token YOUR_TOKEN --npm-email admin@yourdomain.com --npm-password YOUR_PASSWORD
```

### Interactive Mode

```bash
./setup.sh
```

Will prompt for required values.

## Options

| Flag | Description | Default |
|------|-------------|---------|
| `--frps-token` | Token for frps auth | (prompted) |
| `--frps-port` | frps bind port | 6819 |
| `--npm-email` | NPM admin email | (prompted) |
| `--npm-password` | NPM admin password | (prompted) |
| `--skip-frps` | Skip frps installation | - |
| `--skip-npm` | Skip NPM installation | - |

## Examples

```bash
# Full setup
./setup.sh --frps-token mysecret --npm-email me@example.com --npm-password hunter2

# Only frps
./setup.sh --frps-token mysecret --skip-npm

# Only NPM
./setup.sh --npm-email me@example.com --npm-password hunter2 --skip-frps
```

## Firewall Ports

Open these in Lightsail networking:

| Port | Service |
|------|---------|
| 6819 | frps |
| 80 | HTTP |
| 81 | NPM Admin |
| 443 | HTTPS |

## What Gets Installed

### frps
- Binary: `/opt/frps/frps`
- Config: `/etc/frps/frps.toml`
- Service: `systemctl status frps`

### Nginx Proxy Manager
- Location: `/opt/nginx-proxy-manager/`
- Admin: `http://<ip>:81`

