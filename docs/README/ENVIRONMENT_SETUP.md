# Professional Environment Setup: Dev, Pre & Pro

This guide outlines the process to create an isolated development lifecycle within a single Ubuntu WSL instance.

## 1. User Infrastructure
Create the separate environments as isolated Linux users.

```bash
# From your main Ubuntu user
sudo adduser dev
sudo adduser pre
# Production usually resides in /opt, but we will use the 'pro' user for management
sudo adduser pro
```

### Enable Persistence (Critical for Podman/Background services)
```bash
sudo loginctl enable-linger dev
sudo loginctl enable-linger pre
sudo loginctl enable-linger pro
```

## 2. Permissions (Rootless Podman)
Configure sub-UIDs so each user can run nested containers.

```bash
sudo usermod --add-subuids 100000-165535 --add-subgids 100000-165535 dev
sudo usermod --add-subuids 200000-265535 --add-subgids 200000-265535 pre
sudo usermod --add-subuids 300000-365535 --add-subgids 300000-365535 pro
```

## 3. Environment Roles

| Environment | Path | Purpose |
| :--- | :--- | :--- |
| **Development** | `/home/dev/projects/` | Daily coding. Directly connected to GitHub. |
| **Pre-Production** | `/home/pre/testing/` | Deployment tests. Cloned from GitHub 'develop' branch. |
| **Production** | `/opt/services/` | Live instance. Managed by 'pro' user. Stable releases only. |

## 4. GitHub Connection (Dev User)
Switch to the dev user to setup the workspace.

```bash
sudo su - dev
mkdir -p ~/projects && cd ~/projects
git clone <your-repository-url>
```

## 5. Terminal Integration (Windows Terminal)
Add these profiles to your `settings.json` in Windows Terminal:

```json
{
    "name": "Ub 24 - Dev",
    "commandline": "wsl.exe -d Ubuntu-24.04 -u dev --cd ~",
    "startingDirectory": "//wsl$/Ubuntu-24.04/home/dev"
},
{
    "name": "Ub 24 - Pre",
    "commandline": "wsl.exe -d Ubuntu-24.04 -u pre --cd ~",
    "startingDirectory": "//wsl$/Ubuntu-24.04/home/pre"
}
```

## 6. Styling (Optional but Recommended)
Install **Oh My Bash** or **Powerlevel10k** in each user to distinguish them visually (different colors for each prompt).

---
> [!IMPORTANT]
> **Git is your only bridge**. Never copy files manually between `dev` and `pre`. Always `git push` from Dev and `git pull` from Pre.
