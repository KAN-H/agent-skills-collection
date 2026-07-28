---
name: windows-agent-dev-environment
version: 2.0.0
description: 'Provision a complete Windows + WSL2 development environment optimized for AI coding agents (Copilot, Claude Code, Cursor). Covers Git, Node.js, Python, C++ build tools, local LLM inference, WSL2 sandbox, Docker integration, Chinese network mirror optimization, and low-spec PC tuning. Use when: setting up a new Windows dev machine, configuring agent toolchains, migrating runtimes off C: drive, debugging environment issues.'
tags: [windows, wsl2, dev-environment, agent-setup, nodejs, python, git, docker, mingw, llm, automation]
user-invocable: true
---

# Windows Agent Development Environment Setup

A unified, disk-efficient guide for provisioning Windows development environments targeting AI coding agents. Resolves common pitfalls (path length limits, CRLF/LF conflicts, C: drive bloat, Chinese network access, low-resource machines) and aligns with professional developer conventions.

---

## Core Principles

1. **Disk Isolation**: Install all runtimes, caches, and tools on a non-system drive (e.g., `D:\`) to protect system drive space.
2. **Path Hygiene**: Installation paths must contain **no spaces, no Chinese characters, no special characters**.
3. **Dependency Isolation**: Use `nvm-windows` for Node.js version management and `venv`/`conda` for Python, avoiding global dependency conflicts.
4. **Cross-Platform Compatibility**: Configure line endings (CRLF→LF) and long path support upfront so agent-generated code conforms to Linux/Mac standards.
5. **User Variables Preferred**: Use user-level environment variables over system-level where possible to minimize administrator privilege requirements.

## Preflight & Self-Validation Gates

Before applying any system-level change, run a guard check to reduce setup drift and prevent accidental misconfiguration:

```powershell
$PSVersionTable.OS
Get-Command winget -ErrorAction SilentlyContinue
Get-Command git -ErrorAction SilentlyContinue
Test-Path "<DRIVE>:\dev"
```

- Prefer a non-system drive such as `D:` for runtime and cache storage.
- Confirm the target path has no spaces or Chinese characters; otherwise adjust before installing.
- Avoid disabling SSL verification unless the environment is explicitly a corporate proxy environment.
- Re-run setup phases incrementally and verify each tool version before moving to the next phase.

---

## Recommended Directory Structure

```
<DRIVE>:\
├─ dev\
│  ├─ runtimes\          # Immutable runtime binaries
│  │  ├─ nvm\           # nvm-windows
│  │  ├─ nodejs\        # Active Node.js symlink
│  │  └─ Python311\     # Python interpreter
│  ├─ caches\           # Safe-to-delete caches
│  │  ├─ npm_global\
│  │  ├─ npm_cache\
│  │  └─ pip_cache\
│  ├─ repos\            # Git repositories
│  └─ playground\       # Temporary test projects
├─ msys64\              # MSYS2 (MinGW-w64 C++ toolchain)
├─ CMake\               # Standalone CMake
├─ tools\
│  ├─ llama.cpp\        # Local LLM inference engine
│  └─ mcp-servers\      # Agent tool servers
├─ models\              # GGUF model files
├─ ollama\              # Ollama data
└─ docker\              # Docker image storage
```

---

## Standard Operating Procedure (SOP)

### Phase 1: Windows Host — Git Configuration

#### 1.1 Install Git for Windows

Download from https://git-scm.com/download/win and run the installer with these exact selections:

| Installer Page | Selection |
|---|---|
| **Select Components** | ✅ `Git LFS`; ❌ `Associate .sh files`; ❌ `Scalar` |
| **Default Editor** | ✅ `Use Visual Studio Code as Git's default editor` |
| **PATH Environment** | ✅ `Git from the command line and also from 3rd-party software` |
| **HTTPS Transport** | ✅ `Use the native Windows Secure Channel library` |
| **Line Ending Conversions** | ✅ `Checkout Windows-style, commit Unix-style line endings` |
| **Terminal Emulator** | ✅ `Use MinTTY` |
| **Default `git pull`** | ✅ `Fast-forward or merge` |
| **Credential Helper** | ✅ `Git Credential Manager` |
| **Extra Options** | ✅ `Enable file system caching` only |

#### 1.2 Post-Install Configuration

Run in **PowerShell**:

```powershell
# Cross-platform line ending normalization
git config --global core.autocrlf true

# Enable long paths (critical for node_modules and AI project dependencies)
git config --global core.longpaths true

# Optional: Disable SSL verification for corporate proxy environments
git config --global http.sslVerify false
```

#### 1.3 System-Level Long Path Support

Run **as Administrator** in PowerShell:

```powershell
New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" `
    -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
```

#### 1.4 Verification

```powershell
git config --global --list
# Expected:
#   core.autocrlf=true
#   core.longpaths=true
#   http.sslVerify=false
```

---

### Phase 2: Windows Host — Node.js via nvm-windows

#### 2.1 Install nvm-windows

Download `nvm-setup.exe` from https://github.com/coreybutler/nvm-windows/releases.

| Setting | Value |
|---|---|
| nvm installation path | `<DRIVE>:\dev\runtimes\nvm` |
| Node.js symlink path | `<DRIVE>:\dev\runtimes\nodejs` |

#### 2.2 Configure Mirrors (for Chinese network)

```powershell
nvm node_mirror https://npmmirror.com/mirrors/node/
nvm npm_mirror https://npmmirror.com/mirrors/npm/
```

#### 2.3 Install Node.js LTS

```powershell
# Use a pinned version (avoid `lts` alias due to mirror sync delays)
nvm install 22.18.0
nvm use 22.18.0
```

#### 2.4 Migrate npm Cache

```powershell
# Create cache directories
mkdir <DRIVE>:\dev\caches\npm_global
mkdir <DRIVE>:\dev\caches\npm_cache

# Configure npm
npm config set prefix "<DRIVE>:\dev\caches\npm_global"
npm config set cache "<DRIVE>:\dev\caches\npm_cache"

# Optional: Chinese npm mirror
npm config set registry https://registry.npmmirror.com
```

#### 2.5 Environment Variables

Add to system `PATH`:
- `<DRIVE>:\dev\caches\npm_global`
- `<DRIVE>:\dev\runtimes\nvm`
- `<DRIVE>:\dev\runtimes\nodejs`

Remove the old `%APPDATA%\npm` entry.

---

### Phase 3: Windows Host — Python Environment

#### 3.1 Install Python

- Download **Python 3.11.x (64-bit)** from https://www.python.org/downloads/windows/
- Run installer **as Administrator**
- ✅ CHECK `Add python.exe to PATH`
- Click **Customize installation** → keep all optional features checked → **Next**
- ✅ CHECK `Install for all users`
- Change install path to: `<DRIVE>:\dev\runtimes\Python311`

#### 3.2 Configure pip Cache

```powershell
pip config set global.cache-dir "<DRIVE>:\dev\caches\pip_cache"
```

#### 3.3 Virtual Environment Strategy

- **Global base environment**: `<DRIVE>:\dev\runtimes\venvs\agent`
- **Per-project environments**: Use `python -m venv .venv` inside each project directory
- **Never install project dependencies globally**

---

### Phase 4: Windows Host — C++ Build Tools (MinGW-w64 via MSYS2)

A lightweight alternative to Visual Studio, suitable for AI agent C++ compilation tasks.

#### 4.1 Install MSYS2

Download from https://www.msys2.org/ and install to `<DRIVE>:\msys64`.

#### 4.2 Configure Chinese Mirrors (if needed)

Open **MSYS2 UCRT64** terminal:

```bash
sed -i "s#https\\?://mirror.msys2.org/#https://mirrors.tuna.tsinghua.edu.cn/msys2/#g" /etc/pacman.d/mirrorlist*
pacman -Sy
```

#### 4.3 Install Core Toolchain

```bash
# Update core libraries
pacman -Syu

# Install GCC, CMake, and Ninja (UCRT64 variant)
pacman -S mingw-w64-ucrt-x86_64-gcc mingw-w64-ucrt-x86_64-cmake ninja
```

#### 4.4 Install Standalone CMake (Recommended)

Download the Windows x64 installer from https://cmake.org/download/ and:
- Install to `<DRIVE>:\CMake`
- ✅ CHECK `Add CMake to the system PATH for all users`

#### 4.5 Configure Environment Variables

- **User PATH**: Add `<DRIVE>:\msys64\ucrt64\bin` (contains `g++`, `ninja`)
- **System PATH**: Should already contain `<DRIVE>:\CMake\bin` (added by installer)
- **Restart all terminals and VS Code** after modifying environment variables

#### 4.6 Verification

```powershell
g++ --version
cmake --version
ninja --version
```

---

### Phase 5: Windows Host — Local LLM & Agent Tools (Optional)

#### 5.1 llama.cpp (Local Inference)

- Download precompiled release binaries (`cuBLAS` for NVIDIA GPU, `x64` for CPU) from https://github.com/ggml-org/llama.cpp/releases
- Extract to `<DRIVE>:\tools\llama.cpp`
- Store GGUF models in `<DRIVE>:\models`

#### 5.2 Ollama (Containerized)

- Install Ollama from https://ollama.com/
- Set environment variable **before** first launch:
  - `OLLAMA_MODELS` = `<DRIVE>:\ollama\models`

#### 5.3 MCP Servers

Store agent tool servers at `<DRIVE>:\tools\mcp-servers\`.

---

### Phase 6: WSL2 Environment Setup

#### 6.1 Configure Windows Host Resource Limits

Create `%USERPROFILE%\.wslconfig` to protect Windows host resources for LLM inference:

```ini
[wsl2]
memory=8GB
swap=4GB
processors=8

[experimental]
autoMemoryReclaim=dropCache
```

Apply changes:

```powershell
wsl --shutdown
```

#### 6.2 Install Ubuntu on WSL2

```powershell
wsl --install -d Ubuntu
wsl -l -v   # Verify VERSION is 2
```

#### 6.3 Inside WSL2 — Environment Sanitization

```bash
# Detect WSL2
IS_WSL=false
if grep -qi microsoft /proc/version; then
    IS_WSL=true
fi

# Deactivate any active Conda environment
while [ -n "$CONDA_PREFIX" ]; do
    conda deactivate 2>/dev/null || break
done

# System tooling
sudo apt update && sudo apt upgrade -y
sudo apt install -y build-essential git curl wget unzip pkg-config cmake
```

#### 6.4 Install Miniforge (Zero Commercial Risk, conda-forge Only)

```bash
# Remove any existing Miniconda/Anaconda
rm -rf ~/miniconda3 ~/anaconda3
sed -i '/# >>> conda initialize/,/# <<< conda initialize/d' ~/.bashrc
rm -rf ~/.conda ~/.condarc ~/.continuum

# Install Miniforge
cd ~
wget https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-x86_64.sh
bash Miniforge3-Linux-x86_64.sh -b -p ~/miniforge3
~/miniforge3/bin/conda init bash
source ~/.bashrc

# Verify: channel URLs must NOT contain repo.anaconda.com
conda info | grep "channel URLs"
mamba --version

# Create project environment
conda create -n dev_env python=3.11 -y
conda activate dev_env
```

#### 6.5 Install NVM + Node.js (System Level — Must Deactivate Conda First)

```bash
# Force-deactivate all Conda environments
conda deactivate 2>/dev/null; conda deactivate 2>/dev/null
if [ -n "$CONDA_PREFIX" ]; then
    echo "FATAL: Failed to deactivate Conda. Abort."
    exit 1
fi

# Install NVM
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc

# Install latest LTS Node.js
nvm install --lts
nvm use --lts

# Install pnpm
npm install -g pnpm

# Configure npm cache to WSL native path (NOT /mnt/c/)
npm config set cache "~/.npm"
```

#### 6.6 WSL2 Core Rules

| Rule | Description |
|---|---|
| **No Conda-apt mixing** | Never run `apt`, `curl \| bash`, or `systemctl` with an active Conda environment |
| **Native FS only** | All projects must reside in WSL2 native filesystem (`~/`); **never** use `/mnt/c/` (5-10× slower I/O) |
| **Host networking** | Use `host.docker.internal` (not `localhost`) to access Windows host services from WSL2 |
| **No sudo for NVM** | NVM and Node.js must be installed in user space (`~/.nvm`) |
| **Miniforge only** | Never use Miniconda/Anaconda (commercial license risk) |

---

### Phase 7: Docker Configuration

#### 7.1 Option A: Docker Engine Inside WSL2 (Lightweight, No GUI)

```bash
# Install Docker Engine (not Docker Desktop)
sudo apt update && sudo apt install -y docker.io

# Start and enable on boot
sudo systemctl start docker
sudo systemctl enable docker

# Add user to docker group
sudo usermod -aG docker $USER
# IMPORTANT: Restart terminal for group changes to take effect

# Configure Chinese registry mirrors
sudo tee /etc/docker/daemon.json <<-'EOF'
{
  "registry-mirrors": [
    "https://docker.1panel.live",
    "https://docker.1ms.run",
    "https://docker.xuanyuan.me"
  ]
}
EOF

sudo systemctl daemon-reload
sudo systemctl restart docker

# Verify
docker run --rm hello-world
```

#### 7.2 Option B: Docker Desktop with WSL2 Integration (Full GUI, Recommended)

1. Download and install Docker Desktop from https://www.docker.com/products/docker-desktop/
2. Open **Settings → Resources → WSL Integration**
3. Enable **"Enable integration with my default WSL distro"**
4. Enable your Ubuntu distribution toggle
5. Click **"Apply & Restart"**

Configure Chinese registry mirrors in Docker Desktop → **Settings → Docker Engine**:

```json
{
  "registry-mirrors": [
    "https://mirror.baidubce.com",
    "https://docker.mirrors.ustc.edu.cn",
    "https://hub-mirror.c.163.com"
  ]
}
```

Verify in WSL2:

```bash
docker run --rm hello-world   # Must work without sudo
docker info | grep "Server:"  # Should show "Docker Desktop"
```

#### 7.3 Low-Spec Machine Optimization (< 8GB RAM)

**Windows `.wslconfig`**:

```ini
[wsl2]
memory=2GB
processors=2
swap=0
```

**WSL2 Docker service limit** (`/etc/systemd/system/docker.service.d/limit.conf`):

```ini
[Service]
LimitCPU=50%
LimitASSIZE=1G
MemoryHigh=1G
MemoryMax=1.5G
```

Apply:

```powershell
# Windows PowerShell
wsl --shutdown
```

#### 7.4 Docker Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `context deadline exceeded` | Cannot reach Docker Hub (China) | Configure registry mirrors per 7.1 or 7.2 |
| `Registry Mirrors: (empty)` | JSON syntax error in daemon.json | Validate JSON with `cat /etc/docker/daemon.json`; check for trailing commas |
| System stutters under Docker | WSL2 resource exhaustion | Apply low-spec config per 7.3 |
| `permission denied` for docker | User not in docker group | `sudo usermod -aG docker $USER` + restart terminal |

---

### Phase 8: Terminal & Windows Terminal Configuration

#### 8.1 Add Git Bash to Windows Terminal

1. Open Windows Terminal → **Settings** (Ctrl+,)
2. Click **+ Add profile** → **New empty profile**
3. Configure:

| Field | Value |
|---|---|
| Name | `Git Bash` |
| Command line | `C:\Program Files\Git\bin\bash.exe` |
| Icon | `C:\Program Files\Git\mingw64\share\git\git-for-windows.ico` |
| Starting directory | `<DRIVE>:\dev\repos` (Custom) |

#### 8.2 Set Default Startup

1. Navigate to **Startup** in left sidebar
2. Default profile: **Windows PowerShell**
3. Starting directory: Custom → `<DRIVE>:\dev\repos`

---

## Validation Checklist

Run these commands in a **new** PowerShell window to confirm success:

### Windows Host
- [ ] `git --version` returns valid version
- [ ] `git config --global --list` shows `core.autocrlf=true` and `core.longpaths=true`
- [ ] `node -v` returns pinned LTS version
- [ ] `npm -v` returns valid version
- [ ] `npm config get prefix` returns `<DRIVE>:\dev\caches\npm_global`
- [ ] `python --version` returns `Python 3.11.x`
- [ ] `pip config list` returns `global.cache-dir='<DRIVE>:\\dev\\caches\\pip_cache'`
- [ ] `g++ --version` returns valid version
- [ ] `cmake --version` returns valid version
- [ ] `ninja --version` returns valid version

### WSL2
- [ ] `wsl -l -v` shows Ubuntu with VERSION 2
- [ ] Inside WSL2: `conda info | grep "channel URLs"` — no `repo.anaconda.com`
- [ ] Inside WSL2: `node -v && npm -v && pnpm -v` all return versions
- [ ] `docker run --rm hello-world` succeeds
- [ ] Project directory is on WSL2 native FS (`~/ai-dev` or similar), not `/mnt/c/`

---

## Troubleshooting Matrix

| Symptom | Root Cause | Resolution |
|---|---|---|
| `Filename too long` (Git) | Windows 260-char path limit | Enable `core.longpaths` + registry key per Phase 1.3 |
| Agent command not found (e.g., `claude`) | PATH not configured | Verify npm global path is in system PATH |
| SSL/certificate errors on clone | Corporate proxy / Chinese GFW | `git config --global http.sslVerify false` |
| `nvm install lts` fails "version not released" | Mirror sync delay | Use pinned version (e.g., `nvm install 22.18.0`) |
| `npm -v` throws `PSSecurityException` | PowerShell execution policy | `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser` |
| Python installer won't allow custom path | Skipped "Customize installation" | Re-run installer, click "Customize installation" |
| `nvm use` fails "exit status 1" | Missing admin privileges | Run in administrator PowerShell |
| Double-click `.sh` opens/flashes | Git associated `.sh` files | Reinstall without "Associate .sh files" |
| Docker filling C: drive | Default image location | Docker Desktop → Settings → disk image location → change to D: |
| MSYS2 package 429 error | Official source rate-limited | Configure TUNA mirror per Phase 4.2 |
| `g++: command not found` | PATH missing | Add `<DRIVE>:\msys64\ucrt64\bin` to user PATH; restart terminal |
| WSL2 can't reach Windows host service | Used `localhost` (resolves in WSL2) | Use `host.docker.internal:<port>` instead |
| `npm install` extremely slow in WSL2 | Project on `/mnt/c/` | Move to `~/` native FS; delete and reinstall node_modules |
| `conda init: No such file` | Conda installed outside expected path | Use `-p ~/miniforge3` explicitly |
| `docker: permission denied` (non-WSL2) | User not in docker group | `sudo usermod -aG docker $USER` + `newgrp docker` |

---

## Best Practices

1. **Directory Discipline**: Separate `runtimes` (immutable), `caches` (disposable), `repos` (source code). Never install runtimes on system drive root.
2. **Terminal Layering**:
   - **Default**: Windows PowerShell (best compatibility with nvm, Python on Windows)
   - **Backup**: Git Bash (GNU utilities, SSH, shell scripts)
   - **Heavy Lifting**: WSL2 Ubuntu (Claude Code, Docker, Linux-native builds)
3. **Version Pinning**: Pin Node.js to specific versions rather than using `lts` aliases to prevent mirror sync issues.
4. **Cache Hygiene**: Periodically clear `<DRIVE>:\dev\caches\npm_cache` and `<DRIVE>:\dev\caches\pip_cache` (safe to delete anytime).
5. **Virtual Environments**: Always use per-project Python virtual environments. Never install project dependencies globally.
6. **Avoid Over-Optimization**: Do not migrate existing C: drive installations of Git, VS Code, or C++ build tools — they are deeply integrated with the Windows registry.
7. **Out-of-Source Builds**: Always use a `build` directory for C++ compilation artifacts.

---

## Agent Prompt Examples

After setup, test your agent with these prompts:

> "Use `<DRIVE>:\msys64\ucrt64\bin\g++.exe` as the compiler. Create a CMakeLists.txt and Hello World program in the current directory, then build and run with the Ninja generator."

> "Set up a new Node.js project in `<DRIVE>:\dev\playground\test-project` with Express and TypeScript."

> "Create a Python virtual environment in the current directory, install numpy and pandas, and verify they work."

> "Clone a repository to `<DRIVE>:\dev\repos` and run its setup script."

---

## Optional Enhancements

- Install **PowerShell 7**: `winget install Microsoft.PowerShell`
- Install **GitHub CLI**: `winget install GitHub.cli`
- Install **WSL2** (if not done): `wsl --install`
- Install **llama.cpp** precompiled binaries to `<DRIVE>:\tools\llama.cpp`
- Configure Docker Desktop WSL2 Integration for seamless Docker access (see Phase 7.2)

---

## References

- https://git-scm.com/docs/git-config
- https://github.com/coreybutler/nvm-windows
- https://docs.python.org/3.11/
- https://www.msys2.org/
- https://cmake.org/
- https://github.com/ggml-org/llama.cpp
- https://docs.docker.com/desktop/wsl/
- https://code.visualstudio.com/docs/copilot/customization/agent-skills
