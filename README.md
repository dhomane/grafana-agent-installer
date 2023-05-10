# Grafana Agent Installer Scripts

# Windows Installer

```
$username = "myUsername"
$password = "myPassword"
$scriptContent = Invoke-WebRequest -Uri "https://raw.githubusercontent.com/dhomane/grafana-agent-installer/main/grafana-agent-windows-installer.ps1" -UseBasicParsing | Select-Object -ExpandProperty Content
Invoke-Command -ScriptBlock ([ScriptBlock]::Create($scriptContent)) -ArgumentList $username, $password
```

# Linux Installer

```
curl -sSL https://raw.githubusercontent.com/dhomane/grafana-agent-installer/main/grafana-agent-linux-installer.sh | bash -x

```
