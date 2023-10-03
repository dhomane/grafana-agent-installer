# Read user inputs
$customer_id = Read-Host "Enter customer_id"
$region = Read-Host "Enter region"
$env_type = Read-Host "Enter env_type"
$stage = Read-Host "Enter stage"

$filePath = "C:\Program Files\Grafana Agent\agent-config.yaml"

# Define replacements
$replacements = @{
    "customer_id: undefined" = "customer_id: $customer_id"
    "region: undefined" = "region: $region"
    "env_type: undefined" = "env_type: $env_type"
    "stage: undefined" = "stage: $stage"
}

# Read the file, perform replacements, and write back
(Get-Content -Path $filePath) | ForEach-Object {
    $line = $_
    foreach ($key in $replacements.Keys) {
        $line = $line -replace $key, $replacements[$key]
    }
    $line
} | Set-Content -Path $filePath

# Display the updated configuration
cat $filePath


# Restart the Grafana Agent service
Restart-Service "Grafana Agent"
