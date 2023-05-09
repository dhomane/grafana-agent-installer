#!/bin/bash

# Input Variables

grafana_user=$1
grafana_pass=$2


# Azure Variables
RESOURCE_GROUP=$(sudo -u mstr az vm list --query "[?name=='$(hostname)'].resourceGroup" --output tsv)
VM_NAME=$(hostname)


# Get Cloud Platform

cloud=$(sudo dmidecode -s system-manufacturer)

if [[ "$cloud" == "Amazon EC2" ]]; then
    cloud_platform="AWS"
elif [[ "$cloud" == "Microsoft Corporation" ]]; then
    cloud_platform="Azure"
else
    cloud_platform="AWS"
fi


# Get Region

if [[ "${cloud_platform,,}" = "aws" ]]; then
    region=$(grep -oP '(?<=AWS_REGION_NAME=).*' /root/user-data.err)

elif [[ "${cloud_platform,,}" = "azure" ]]; then
    region=$(sudo -u mstr az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --query "location" -o tsv)

else
    region="us-east-1"
fi

# Get Environment Tier

if [[ "${cloud_platform,,}" = "aws" ]]; then
    env_type=$(aws ec2 describe-instances --region $region --filters "Name=tag:Name,Values=$VM_NAME" --query 'Reservations[*].Instances[*].Tags[?Key==`env`].Value' --output text)

elif [[ "${cloud_platform,,}" = "azure" ]]; then
    env_type=$(sudo -u mstr az vm show --resource-group $RESOURCE_GROUP --name $VM_NAME --query "tags.Env" -o tsv)

else
    env_type="prod"
fi

# Get Customer ID

if [[ "${cloud_platform,,}" = "aws" ]]; then
    customer_id=$(aws ec2 describe-instances --region $region --filters "Name=tag:Name,Values=$VM_NAME" --query 'Reservations[*].Instances[*].Tags[?Key==`CID`].Value' --output text | tr '[:lower:]' '[:upper:]')

elif [[ "${cloud_platform,,}" = "azure" ]]; then
    
    customer_id=$(sudo -u mstr az resource show --ids $(sudo -u mstr az vm show -g $RESOURCE_GROUP -n $VM_NAME --query 'id' -o tsv) --query 'tags.AID' -o tsv | tr '[:lower:]' '[:upper:]')
    
else
    customer_id="C000"
fi


# Set the Grafana Repository

echo "Installing the Grafana Agent..."

sudo cat > /etc/yum.repos.d/grafana.repo << EOF
[grafana]
name=grafana
baseurl=https://rpm.grafana.com
repo_gpgcheck=1
enabled=1
gpgcheck=1
gpgkey=https://rpm.grafana.com/gpg.key
sslverify=1
sslcacert=/etc/pki/tls/certs/ca-bundle.crt
EOF

# Verify that the repository is properly configured using yum-config-manager

yum-config-manager grafana

# Install Grafana Agent:

sudo yum install -y grafana-agent

sleep 10

# Modify Grafana Agent Port

sudo sed -i 's/^CUSTOM_ARGS=.*/CUSTOM_ARGS="-server.http.address=127.0.0.1:9900 -server.grpc.address=127.0.0.1:9901"/' /etc/sysconfig/grafana-agent

sudo systemctl daemon-reload

# Modify the Grafana Agent Config File

echo "" > /etc/grafana-agent.yaml

sudo cat > /etc/grafana-agent.yaml << EOF
server:
  log_level: debug

integrations:

  agent:
    enabled: true

  node_exporter:
    enabled: true
    textfile_directory: /var/local/mstr

    relabel_configs:
    - replacement: hostname
      target_label: instance


  prometheus_remote_write:

  - basic_auth:
      password: grafana_pass
      username: grafana_user
    url: https://prometheus-prod-10-prod-us-central-0.grafana.net/api/prom/push

    write_relabel_configs:
        - source_labels: [__name__]
          regex: "up|node_uname_info|node_cpu_seconds_total|node_disk_io_time_seconds_total|node_disk_read_bytes_total|node_disk_written_bytes_total|node_filesystem_avail_bytes|node_filesystem_size_bytes|node_load1|node_load15|node_load5|node_memory_Buffers_bytes|node_memory_MemAvailable_bytes|node_memory_Cached_bytes|node_memory_MemFree_bytes|node_memory_MemTotal_bytes|node_network_receive_bytes_total|node_network_transmit_bytes_total|dss_document_caches_in_memory|dss_intelligent_cubes_in_memory|dss_open_project_sessions|dss_open_sessions|dss_percent_cpu_time|dss_ram_used|dss_real_memory_total|dss_real_memory_used|dss_report_caches_in_memory|dss_rss|dss_size|dss_total_cpu|dss_total_document_cache_index_size|dss_total_mcm_denial|dss_total_project_sessions|dss_total_server_process_heap_cached|dss_total_server_process_heap_in_memory|dss_total_sessions|dss_total_size_cubes_in_memory|dss_total_size_document_caches_in_memory|dss_virtual_memory_used|dss_working_set_cache_ram_usage|mounts_check_failed|mstr_status_iserver|mstr_status_tomcat|mstr_status_collab_server|mstr_status_pdf_export|mstr_status_message_kafka|mstr_status_message_zookeeper|mstr_status_listener|mstr_status_collab_redis|mstr_status_platform_analytics_consumer|mstr_status_platform_analytics_redis|mstr_status_certificate_manager"
          action: keep

metrics:

  configs:

  - name: integrations
    remote_write:
    - basic_auth:
        password: grafana_pass
        username: grafana_user
      url: https://prometheus-prod-10-prod-us-central-0.grafana.net/api/prom/push


  global:
    scrape_interval: 60s
    scrape_timeout: 30s

    external_labels:

      env_type: env_label
      region: region_label
      cloud_platform: cloud_label
      customer_id: cid_label

  wal_directory: /tmp/grafana-agent-wal

EOF

# Set Hostname in Grafana Agent

HOSTNAME=$(uname -n)
sed -i "s/hostname/$HOSTNAME/" /etc/grafana-agent.yaml

# Update the label values in-place for Grafana Agent

sed -i "s/env_label/$env_type/g" /etc/grafana-agent.yaml

sed -i "s/region_label/$region/g" /etc/grafana-agent.yaml

sed -i "s/cloud_label/$cloud_platform/g" /etc/grafana-agent.yaml

sed -i "s/cid_label/$customer_id/g" /etc/grafana-agent.yaml

# Update the Credentials

sed -i "s/grafana_user/$grafana_user/g; s/grafana_pass/$grafana_pass/g" /etc/grafana-agent.yaml


# Set Permissions for Agent Config File
sudo chown root:grafana-agent /etc/grafana-agent.yaml


# Create Directory for scraping custom metrics

# Create Directory for scraping custom metrics

mkdir -p /var/local/mstr

# Create Scripts for custom metrics 

sudo cat > /root/linux_admin_script/cld_monitoring/grafana-custom-metrics.py << EOF
# Python Script that generates Prometheus-compatible metrics for DSS Performance Counters

import ast

# Retrieve contents of DSS Performance Metrics Log file

with open('/tmp/panopta_gen_dssperf_json.log', 'r') as f:
    for line in f:
        pass
    payload = line

payload_new = payload[15::]
payload_dict = ast.literal_eval(payload_new)
dss_list = payload_dict['metrics']

# Generate a new list containing Prometheus-compatible Metrics

dss_names = ['dss_virtual_memory_used', 'dss_total_cpu', 'dss_ram_used', 'dss_size', 'dss_rss', 'dss_percent_cpu_time', 'dss_real_memory_used', 'dss_real_memory_total', 'dss_working_set_cache_ram_usage', 'dss_total_sessions', 'dss_total_project_sessions', 'dss_open_sessions', 'dss_open_project_sessions', 'dss_total_size_document_caches_in_memory', 'dss_total_size_cubes_in_memory', 'dss_total_server_process_heap_in_memory', 'dss_total_server_process_heap_cached', 'dss_total_mcm_denial', 'dss_total_document_cache_index_size', 'dss_intelligent_cubes_in_memory', 'dss_document_caches_in_memory', 'dss_report_caches_in_memory']
dss_values = []

for i in range(22):
    dss_values.append(dss_list[i]['value'])
    
dss_metrics = list(zip(dss_names, dss_values))

f = open('/var/local/mstr/metrics.prom', 'w')
for t in dss_metrics:
    line = ' '.join(str(x) for x in t)
    f.write(line + '\n')
f.close()
EOF

sudo cat > /root/linux_admin_script/cld_monitoring/grafana-mstr-status.py << EOF
import ast

# Retrieve contents of MSTR Services Status
STATUS_NAMES = {'iserver', 'tomcat', 'collab-server', 'pdf-export', 'message-kafka', 'message-zookeeper', 'listener', 'collab-redis', 'platform-analytics-consumer', 'platform-analytics-redis', 'certificate-manager'}

with open('/opt/monitoring/scripts/server-status.json', 'r') as f:
    for line in f:
        pass
    output = line

output_dict = ast.literal_eval(output)
payload = output_dict['data']

# Initializing replacement values. Replace 'Stopped' with value 0 and 'Running' with value 1

replacement_val = {'Stopped': 0, 'Running': 1}

# iterating dictionary
status_metrics = []


for status in STATUS_NAMES:
    try:
        if status in payload.keys():
            status_value = replacement_val[payload[status]]
        else:
            value = next(val for key, val in payload.items() if key.startswith(status))
            status_value = replacement_val[value]
    except:
        status_value = 0

    status_name = f'mstr_status_{status.replace("-", "_")}'
    status_metrics.append((status_name, status_value))
# Generate a new list containing Prometheus-compatible Metrics

f = open('/var/local/mstr/status.prom', 'w')
for t in status_metrics:
    line = ' '.join(str(x) for x in t)
    f.write(line + '\n')
f.close()
EOF


sudo cat > /root/linux_admin_script/cld_monitoring/grafana-mounts-check.sh << EOF
#!/bin/bash

mountpoints=( $(awk '$1 !~ /^#/ && $2 ~ /^[/]/ {print $2}' /etc/fstab) )

echo "mounts_check_failed 0" > /var/local/mstr/mounts.prom

for mount in ${mountpoints[@]}; do
   if ! findmnt "$mount" &> /dev/null; then
      echo "$mount is declared in fstab but not mounted"
      echo "mounts_check_failed 1" > /var/local/mstr/mounts.prom
   else
      echo "mounts are ok"
   fi
done
EOF

# Set permissions for bash script
sudo chmod +x /root/linux_admin_script/cld_monitoring/grafana-mounts-check.sh

# Add cron jobs to run the custom scripts

(crontab -l 2>/dev/null; echo "#Ansible: custom_metrics" ; echo "*/1 * * * * /usr/bin/python3 /root/linux_admin_script/cld_monitoring/grafana-custom-metrics.py") | crontab -

(crontab -l 2>/dev/null; echo "#Ansible: mstr_status" ; echo "*/1 * * * * /usr/bin/python3 /root/linux_admin_script/cld_monitoring/grafana-mstr-status.py") | crontab -

(crontab -l 2>/dev/null; echo "#Ansible: mounts_status" ; echo "*/1 * * * * sudo bash /root/linux_admin_script/cld_monitoring/grafana-mounts-check.sh") | crontab -


# Restart and enable Grafana Agent

sudo systemctl restart grafana-agent

sudo systemctl enable --now grafana-agent

echo "Grafana agent is now installed"

