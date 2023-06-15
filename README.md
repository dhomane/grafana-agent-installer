# Grafana Agent Installer Scripts

# Windows Installer

```
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$scriptContent = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dhomane/grafana-agent-installer/main/grafana-agent-windows-installer.ps1" -UseBasicParsing | Select-Object -ExpandProperty Content

Invoke-Command -ScriptBlock ([ScriptBlock]::Create($scriptContent))

```

# Linux Installer

```
curl -sSL https://raw.githubusercontent.com/dhomane/grafana-agent-installer/main/grafana-agent-linux-installer.sh | bash -x

```
