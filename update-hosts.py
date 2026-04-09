#!/usr/bin/env python3
"""
auto-hosts-update: Update /etc/hosts using Steven Black's pre-built hosts lists.

Configuration files:
  /etc/auto-hosts/config     - extension toggles and settings
  /etc/auto-hosts/whitelist  - domains to un-block (one per line)
  /etc/auto-hosts/blacklist  - additional domains to block (one per line)
  /etc/auto-hosts/myhosts    - raw host entries appended verbatim
"""

import os
import sys
import subprocess
import urllib.request
import urllib.error
import time

CONFIG_DIR   = "/etc/auto-hosts"
CONFIG_FILE  = f"{CONFIG_DIR}/config"
WHITELIST    = f"{CONFIG_DIR}/whitelist"
BLACKLIST    = f"{CONFIG_DIR}/blacklist"
MYHOSTS      = f"{CONFIG_DIR}/myhosts"
HOSTS_FILE   = "/etc/hosts"
BASE_URL     = "https://raw.githubusercontent.com/StevenBlack/hosts/master"

# Steven Black names extensions in this alphabetical order in the URL path
EXTENSION_ORDER = ["fakenews", "gambling", "porn", "social"]


def log(msg):
    print(f"auto-hosts: {msg}", flush=True)


def parse_config():
    config = {ext: False for ext in EXTENSION_ORDER}
    config["redirect_ip"] = "0.0.0.0"

    if not os.path.exists(CONFIG_FILE):
        return config

    with open(CONFIG_FILE) as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" not in line:
                continue
            key, _, value = line.partition("=")
            key   = key.strip().upper()
            value = value.strip().lower()
            lower_key = key.lower()
            if lower_key in EXTENSION_ORDER:
                config[lower_key] = value in ("true", "yes", "1", "on")
            elif key == "REDIRECT_IP":
                config["redirect_ip"] = value.strip()

    return config


def build_url(config):
    enabled = [ext for ext in EXTENSION_ORDER if config[ext]]
    if not enabled:
        return f"{BASE_URL}/hosts"
    return f"{BASE_URL}/alternates/{'-'.join(enabled)}/hosts"


def download(url, retries=3):
    for attempt in range(1, retries + 1):
        try:
            log(f"Downloading {url} (attempt {attempt})")
            req = urllib.request.Request(
                url, headers={"User-Agent": "auto-hosts-fedora/1.0"}
            )
            with urllib.request.urlopen(req, timeout=30) as resp:
                return resp.read().decode("utf-8")
        except urllib.error.URLError as e:
            log(f"Download failed: {e}")
            if attempt < retries:
                time.sleep(5 * attempt)

    log("ERROR: All download attempts failed")
    sys.exit(1)


def read_list(path):
    """Read a file and return non-empty, non-comment lines."""
    if not os.path.exists(path):
        return []
    with open(path) as f:
        return [
            line.strip()
            for line in f
            if line.strip() and not line.strip().startswith("#")
        ]


def apply_whitelist(content, whitelist):
    """Remove hosts entries whose hostname is in the whitelist."""
    if not whitelist:
        return content
    allow = set(whitelist)
    out = []
    for line in content.splitlines():
        stripped = line.strip()
        if stripped and not stripped.startswith("#"):
            parts = stripped.split()
            # Hosts lines: <ip> <hostname> [aliases...]
            if len(parts) >= 2 and parts[1] in allow:
                continue
        out.append(line)
    return "\n".join(out)


def build_blacklist_block(redirect_ip, blacklist):
    lines = ["# Custom blacklist (auto-hosts)"]
    for domain in blacklist:
        lines.append(f"{redirect_ip} {domain}")
    return "\n".join(lines)


def write_hosts(content):
    """Write atomically, then restore SELinux context."""
    tmp = HOSTS_FILE + ".auto-hosts-new"
    try:
        with open(tmp, "w") as f:
            f.write(content)
        os.replace(tmp, HOSTS_FILE)
    except Exception:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise

    # Restore SELinux label (net_conf_t) after atomic rename
    try:
        subprocess.run(
            ["restorecon", HOSTS_FILE],
            check=True,
            capture_output=True,
        )
    except FileNotFoundError:
        pass  # SELinux not in use on this system
    except subprocess.CalledProcessError as e:
        log(f"Warning: restorecon failed: {e.stderr.decode().strip()}")


def main():
    if os.geteuid() != 0:
        log("ERROR: Must be run as root")
        sys.exit(1)

    config = parse_config()

    enabled_extensions = [ext for ext in EXTENSION_ORDER if config[ext]]
    if enabled_extensions:
        log(f"Extensions enabled: {', '.join(enabled_extensions)}")
    else:
        log("Extensions enabled: none (base list only)")

    url     = build_url(config)
    content = download(url)

    whitelist = read_list(WHITELIST)
    if whitelist:
        log(f"Applying whitelist ({len(whitelist)} entries)")
        content = apply_whitelist(content, whitelist)

    blacklist = read_list(BLACKLIST)
    myhosts_raw = ""
    if os.path.exists(MYHOSTS):
        with open(MYHOSTS) as f:
            myhosts_raw = f.read().strip()

    parts = [content.rstrip()]

    if blacklist:
        log(f"Applying blacklist ({len(blacklist)} entries)")
        parts.append("\n" + build_blacklist_block(config["redirect_ip"], blacklist))

    if myhosts_raw:
        log("Appending myhosts entries")
        parts.append("\n# Custom hosts (myhosts)\n" + myhosts_raw)

    final = "\n".join(parts) + "\n"

    write_hosts(final)
    log(f"Successfully updated {HOSTS_FILE}")


if __name__ == "__main__":
    main()
