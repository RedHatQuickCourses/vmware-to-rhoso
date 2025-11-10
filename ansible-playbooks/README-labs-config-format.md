# Lab Configuration File Format Reference

This document describes the expected format for lab configuration files used with the multi-lab deployment scripts.

## Overview

The lab configuration file contains information about multiple lab environments that need to be deployed. Each lab entry includes connection details, network configuration, and deployment parameters.

## File Structure

The configuration file follows a specific text-based format with multiple sections per lab:

```
Service	Assigned Email	Details
openshift-cnv.osp-on-ocp-cnv.prod-<LAB_ID>	
- unassigned -

[Lab Information Section]
[Network Configuration Section]
[Authentication Section]
[Data Section with YAML]
```

## Required Sections per Lab

### 1. Service Header
```
Service	Assigned Email	Details
openshift-cnv.osp-on-ocp-cnv.prod-<LAB_ID>	
- unassigned -
```

**Key Points:**
- The service name **must** follow the pattern: `openshift-cnv.osp-on-ocp-cnv.prod-<LAB_ID>`
- The `<LAB_ID>` will be extracted as the unique identifier for the lab
- Lab IDs should contain only alphanumeric characters and hyphens

### 2. Lab Information Section
```
Messages
OpenShift Console: https://console-openshift-console.apps.cluster-<GUID>.dynamic.redhatworkshops.io
OpenShift API for command line 'oc' client: https://api.cluster-<GUID>.dynamic.redhatworkshops.io:6443
Download oc client from http://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.16/openshift-client-linux.tar.gz
```

**Parsed Elements:**
- OpenShift Console URL (automatically extracted)
- API server URL
- Lab UI URL

### 3. Network Configuration Section
```
RHOSO External IP Allocation Details:
=======================================

Allocation Name: cluster-<GUID>
Cluster: <CLUSTER_NAME>
Network Subnet: 192.168.0.0/24
Network CIDR: 192.168.0.0/24

Allocated IP Addresses:
EXTERNAL_IP_WORKER_1=192.168.X.10
EXTERNAL_IP_WORKER_2=192.168.X.11
EXTERNAL_IP_WORKER_3=192.168.X.12
EXTERNAL_IP_BASTION=192.168.X.13
PUBLIC_NET_START=192.168.X.20
PUBLIC_NET_END=192.168.X.30
CONVERSION_HOST_IP=192.168.X.25

Environment Variables (copy and paste):
export EXTERNAL_IP_WORKER_1=192.168.X.10
export EXTERNAL_IP_WORKER_2=192.168.X.11
export EXTERNAL_IP_WORKER_3=192.168.X.12
export EXTERNAL_IP_BASTION=192.168.X.13
export PUBLIC_NET_START=192.168.X.20
export PUBLIC_NET_END=192.168.X.30
export CONVERSION_HOST_IP=192.168.X.25
```

**Parsed Elements:**
- External IP addresses for worker nodes (automatically extracted from `EXTERNAL_IP_*=` lines)
- Bastion external IP
- Network range information

### 4. Authentication Section
```
Authentication via htpasswd is enabled on this cluster.

User admin with password <ADMIN_PASSWORD> is cluster admin.
OpenShift GitOps ArgoCD: https://openshift-gitops-server-openshift-gitops.apps.cluster-<GUID>.dynamic.redhatworkshops.io
You can access your bastion via SSH:
ssh lab-user@<BASTION_HOST> -p <BASTION_PORT>

Enter ssh password when prompted: <SSH_PASSWORD>
```

**Parsed Elements:**
- Admin password (from "User admin with password X is cluster admin")
- SSH connection details (hostname, port from SSH command)
- SSH password (from "Enter ssh password when prompted:")

### 5. Data Section (YAML Format)
```
Data
openshift-cnv.osp-on-ocp-cnv.prod:
  bastion_public_hostname: <BASTION_HOST>
  bastion_ssh_command: ssh lab-user@<BASTION_HOST> -p <BASTION_PORT>
  bastion_ssh_password: <SSH_PASSWORD>
  bastion_ssh_port: '<BASTION_PORT>'
  bastion_ssh_user_name: lab-user
  cloud_provider: openshift_cnv
  guid: <LAB_GUID>
  openshift_api_server_url: https://api.cluster-<GUID>.dynamic.redhatworkshops.io:6443
  openshift_api_url: https://api.cluster-<GUID>.dynamic.redhatworkshops.io:6443
  openshift_client_download_url: >-
    http://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable-4.16/openshift-client-linux.tar.gz
  openshift_cluster_admin_password: <ADMIN_PASSWORD>
  openshift_cluster_admin_username: admin
  openshift_cluster_console_url: >-
    https://console-openshift-console.apps.cluster-<GUID>.dynamic.redhatworkshops.io
  openshift_cluster_ingress_domain: apps.cluster-<GUID>.dynamic.redhatworkshops.io
  # ... additional configuration parameters
```

**Key Points:**
- Must start with "Data" on its own line
- Followed by "openshift-cnv.osp-on-ocp-cnv.prod:" header
- Contains YAML-formatted configuration data
- All parameters are available to the deployment scripts

## Example Lab Configuration

See `labs_to_be_deployed.example` for a complete example with 3 labs:

- **prod-lab001**: Uses cluster abc123, bastion ssh.ocpv01.rhdp.net:30001
- **prod-lab002**: Uses cluster def456, bastion ssh.ocpv02.rhdp.net:30002  
- **prod-lab003**: Uses cluster ghi789, bastion ssh.ocpv03.rhdp.net:30003

## Key Parameters Extracted

The parsing script extracts these critical parameters for each lab:

| Parameter | Source | Usage |
|-----------|--------|-------|
| `lab_id` | Service name suffix | Unique lab identifier |
| `bastion_hostname` | SSH command line | Bastion host for SSH connection |
| `bastion_port` | SSH command line | SSH port for bastion |
| `bastion_password` | SSH password prompt | Password for bastion SSH |
| `ocp_admin_password` | Admin user line | OpenShift cluster admin password |
| `ocp_console_url` | Console URL line | OpenShift web console URL |
| `external_ip_worker_*` | EXTERNAL_IP lines | External IPs for worker nodes |
| `external_ip_bastion` | EXTERNAL_IP lines | External IP for bastion |
| `guid` | Data section | Lab GUID from YAML data |

## Validation

To validate your lab configuration file format:

```bash
# Test parsing without deployment
./test-multi-lab-parsing.sh your_labs_file.txt

# Check what labs were detected
./deploy-multiple-labs.sh --labs your_labs_file.txt --credentials creds.yml --dry-run
```

## Common Issues

### 1. Lab ID Extraction
- **Problem**: Lab IDs contain special characters or spaces
- **Solution**: Use only alphanumeric characters and hyphens in lab IDs

### 2. SSH Connection Details
- **Problem**: SSH command format doesn't match expected pattern
- **Solution**: Ensure SSH command follows exact format: `ssh lab-user@hostname -p port`

### 3. Password Extraction
- **Problem**: Passwords contain spaces or special characters
- **Solution**: Ensure passwords are single words without spaces

### 4. YAML Data Section
- **Problem**: YAML formatting is incorrect
- **Solution**: Ensure proper indentation (2 spaces) and valid YAML syntax

### 5. Missing Required Fields
- **Problem**: Some required fields are missing from the data section
- **Solution**: Ensure all required fields are present:
  - `bastion_public_hostname`
  - `bastion_ssh_password`
  - `bastion_ssh_port`
  - `guid`
  - `openshift_cluster_admin_password`

## Creating Your Own Lab Configuration

1. **Start with the example**: Copy `labs_to_be_deployed.example`
2. **Update lab IDs**: Change `prod-lab001`, `prod-lab002`, etc. to your lab IDs
3. **Update connection details**: Replace hostnames, ports, and passwords
4. **Update network configuration**: Set correct external IP addresses
5. **Update YAML data**: Ensure all parameters match your environment
6. **Test parsing**: Run `./test-multi-lab-parsing.sh your_file.txt`

## Integration with Deployment Scripts

The parsed configuration is used by:

- **`deploy-multiple-labs.sh`**: Main multi-lab deployment script
- **`test-multi-lab-parsing.sh`**: Configuration validation script

Each lab's configuration is automatically converted into:
- Ansible inventory files with proper bastion connectivity
- Environment variables for deployment scripts
- SSH connection parameters for bastion access

## Best Practices

1. **Consistent Naming**: Use consistent lab ID patterns
2. **Unique Networks**: Ensure each lab uses different IP ranges
3. **Secure Passwords**: Use strong, unique passwords for each lab
4. **Validation**: Always test parsing before deployment
5. **Documentation**: Document any custom parameters in the YAML section

This format ensures reliable parsing and successful multi-lab deployments while maintaining compatibility with the existing single-lab deployment logic.
