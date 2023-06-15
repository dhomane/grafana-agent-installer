# Prompt user for Grafana username and password

$username = Read-Host "Enter the Grafana username"
$password = Read-Host "Enter the Grafana password" -AsSecureString

# Convert the password to plain text

$password = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($password))


# Prompt user for external labels

$stage = Read-Host "Enter the stage label"
$env_type = Read-Host "Enter the env_type label"
$region = Read-Host "Enter the region label"
$cloud_platform = Read-Host "Enter the cloud_platform label"
$customer_id = Read-Host "Enter the customer_id label"

# Script to install Grafana agent for Windows

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12


Write-Host "Setting up Grafana agent"


if ( -Not [bool](([System.Security.Principal.WindowsIdentity]::GetCurrent()).groups -match "S-1-5-32-544") ) {

    Write-Host "ERROR: The script needs to be run with Administrator privileges"

    exit
}

# Temporarily disable Windows Proxy

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "ProxyEnable" -Value 0


# Download and Install Grafana Agent


Write-Host "Downloading Grafana agent Windows Installer"

$DOWLOAD_URL = "https://github.com/grafana/agent/releases/latest/download/grafana-agent-installer.exe.zip"
$OUTPUT_ZIP_FILE = "C:\grafana-agent-installer.exe.zip"
$OUTPUT_FILE = "C:\grafana-agent-installer.exe"

Invoke-WebRequest -Uri $DOWLOAD_URL -OutFile $OUTPUT_ZIP_FILE
Expand-Archive -LiteralPath $OUTPUT_ZIP_FILE -DestinationPath $OUTPUT_FILE -Force

# Install Grafana agent in silent mode
Write-Host "Installing Grafana agent for Windows"

Start-Process -FilePath "C:\grafana-agent-installer.exe\grafana-agent-installer.exe" -ArgumentList "/S /EnableExporter true /v/qn" -Wait


# Create Config File for Grafana Agent


$content = @"
server:
  log_level: warn
  
integrations:

  agent:
    enabled: true

    relabel_configs:
    - action: replace
      source_labels:
      - agent_hostname
      target_label: instance

  prometheus_remote_write:
  - basic_auth:
      password: $password
      username: $username
    url: https://prometheus-prod-10-prod-us-central-0.grafana.net/api/prom/push

    write_relabel_configs:
        - source_labels: [__name__]
          regex: "up|windows_cpu_time_total|windows_cs_hostname|windows_cs_logical_processors|windows_cs_physical_memory_bytes|windows_iis_current_connections|windows_logical_disk_free_bytes|windows_logical_disk_read_bytes_total|windows_logical_disk_size_bytes|windows_logical_disk_write_bytes_total|windows_net_bytes_total|windows_net_current_bandwidth|windows_os_info|windows_os_physical_memory_free_bytes|windows_system_system_up_time"
          action: keep

  windows_exporter:
    enabled: true

metrics:
  configs:
  - name: integrations
    remote_write:
    - basic_auth:
        password: $password
        username: $username
      url: https://prometheus-prod-10-prod-us-central-0.grafana.net/api/prom/push

  global:
    scrape_interval: 60s
    scrape_timeout: 30s

    external_labels:
    
      stage: $stage
      env_type: $env_type
      region: $region
      cloud_platform: $cloud_platform
      customer_id: $customer_id

  wal_directory: /tmp/grafana-agent-wal
"@

Set-Content -Path "C:\agent-config.yaml" -Value $content 


# Replace Grafana username and API Key

(Get-Content -Path "C:\agent-config.yaml") | ForEach-Object { $_ -replace '$username', $username -replace '$password', $password } | Set-Content -Path "C:\agent-config.yaml"
 

Move-Item "C:\agent-config.yaml" "C:\Program Files\Grafana Agent\agent-config.yaml" -Force


Write-Host "Wait for Grafana service to initialize"

# Wait for service to initialize after first install
Start-Sleep -s 5


# Restart Grafana agent to load new configuration
Write-Host "Restarting Grafana agent service"


Stop-Service "Grafana Agent"

Start-Service "Grafana Agent"


# Show Grafana agent service status
Get-Service "Grafana Agent"
 

# Add Recovery options

sc.exe config "Grafana Agent" start= delayed-auto

sc.exe failure "Grafana Agent" reset= 0 actions= restart/1000/restart/1000/restart/1000 

# Re-enable Windows Proxy

Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings" -Name "ProxyEnable" -Value 1

# Delete Temporary Files

Remove-Item "C:\grafana-agent-installer.exe.zip" -Force -Confirm:$false
Remove-Item "C:\grafana-agent-installer.exe" -Force -Confirm:$false
