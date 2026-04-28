# 初始化 Windows DevBox

## Install
```powershell
Invoke-Expression -Command (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/devbox.ps1").Content
```

# 初始化 Claude Code 环境 (Windows)

一次性脚本，安装 Node.js、Claude Code 和 agency CLI，配置 copilot-api 代理和 6 个 agency MCP 服务器。

## Install
```powershell
Invoke-Expression (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dianshu/config/main/Windows/init-claude.ps1").Content
```

# 初始化 Windows PC

## Install
```powershell
Invoke-Expression -Command (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dianshu/config/refs/heads/main/Windows/pc.ps1").Content
```
