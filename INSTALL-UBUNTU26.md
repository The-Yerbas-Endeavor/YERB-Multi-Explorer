# Install YERB Multi-Explorer on Ubuntu 26.04

Use a normal Linux account that has sudo privileges. Do not perform the installation from a root login shell.

## 1. Log in as your ordinary user

Example prompt:

```text
ex@EX-Multi:~$
```

Confirm sudo access:

```bash
sudo -v
```

## 2. Clone the repository

```bash
git clone https://github.com/The-Yerbas-Endeavor/YERB-Multi-Explorer.git
cd YERB-Multi-Explorer
```

## 3. Launch the sudo-user installer

Run the launcher without placing `sudo` before it:

```bash
chmod +x installer/install-sudo-user.sh
bash installer/install-sudo-user.sh
```

The launcher verifies that:

- the current account is not root
- `sudo` is installed
- the account has working sudo privileges
- Python 3 is available for configuration conversion

It then elevates only the privileged installer process.

## 4. Answer the installation prompts

The installer requests:

- explorer domain, or blank for IP-only access
- Yerbas RPC username and password
- MongoDB password
- optional Let's Encrypt setup
- optional Yerbas bootstrap-index download

The bootstrap prompt displays available release metadata, estimated space requirements, and reuse/resume options when available.

## Account separation

The login user only launches and administers the installation. Production services run under dedicated accounts:

```text
yerbas        Yerbas Core daemon
yerbexplorer  Explorer and PM2
mongodb       MongoDB
www-data      Nginx
```

## Configuration conversion

The upstream explorer configuration template contains comments. The launcher automatically converts it into strict JSON before the installer updates it with `jq`.

The generated configuration is written to:

```text
/opt/yerb-multi-explorer/settings.json
```

No manual JSON5 conversion is required.

## Common commands

```bash
sudo yerb-explorer-health
sudo yerb-explorer-update
sudo systemctl status yerbasd --no-pager
sudo systemctl status mongod --no-pager
sudo systemctl status nginx --no-pager
sudo systemctl status pm2-yerbexplorer --no-pager
```

## Incorrect launch methods

Do not use:

```bash
sudo bash installer/install-sudo-user.sh
sudo -i
su -
```

The launcher intentionally refuses to run as root.
