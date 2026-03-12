# GitLab Cheat Sheet

## Management

- **Start:** `./gitlab.sh start`
- **Update:** `./gitlab.sh update`
- **Uninstall:** `./gitlab.sh uninstall`

## Access

- **URL:** `http://<HOST_IP>:8929`
- **SSH:** `ssh -p 8922 git@<HOST_IP>`
- **Admin Users:** `root`
- **Admin Password:** Check `~/.bash_history` (if first install) or `/opt/gitlab/.env`.

## Architecture

- **Image:** `gitlab/gitlab-ce:latest`
- **Engine:** Podman Rootless
- **SELinux:** Enabled (`:Z` mappings)
- **UI Management:** Integrated with **Arcane**

## Configuration

- **Config:** `/opt/gitlab/config`
- **Data:** `/opt/gitlab/data`
- **Logs:** `/opt/gitlab/logs`
- **Runtime Env:** `/opt/gitlab/.env`
