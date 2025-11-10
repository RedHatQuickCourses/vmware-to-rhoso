# Lab Inventory Generator

This script (`generate-lab-inventories.sh`) parses lab configuration files and generates individual `hosts-{guid}.yml` inventory files for each lab, making it easier to manage multiple lab deployments.

## Usage

```bash
./generate-lab-inventories.sh <labs_config_file> [OPTIONS]
```

### Arguments

- `<labs_config_file>`: Path to the labs configuration file (e.g., `my_labs_to_be_deployed`)

### Options

- `-o, --output-dir DIR`: Output directory for inventory files (default: `inventory`)
- `-f, --force`: Overwrite existing inventory files
- `-d, --dry-run`: Show what would be generated without creating files
- `-h, --help`: Show help message

## Examples

### Basic Usage
```bash
# Generate inventory files for all labs
./generate-lab-inventories.sh my_labs_to_be_deployed
```

### Advanced Usage
```bash
# Generate with custom output directory
./generate-lab-inventories.sh my_labs_to_be_deployed --output-dir /tmp/inventories

# Dry run to see what would be generated
./generate-lab-inventories.sh my_labs_to_be_deployed --dry-run

# Force overwrite existing files
./generate-lab-inventories.sh my_labs_to_be_deployed --force
```

## Output

The script generates individual inventory files in the format `hosts-{guid}.yml` for each lab found in the configuration file.

### Generated Files Structure

```
inventory/
├── hosts-prod-btww2.yml    # Lab 1 inventory
├── hosts-prod-k9qcm.yml    # Lab 2 inventory
└── hosts.yml               # Original template
```

### Generated Inventory Content

Each generated inventory file contains:

- **Lab-specific variables**: GUID, bastion connection details, passwords
- **OpenShift configuration**: Console URL, admin password
- **Network configuration**: External IP addresses for worker nodes and bastion
- **SSH proxy configuration**: Proper jump host setup for internal resources

Example generated file (`hosts-prod-btww2.yml`):

```yaml
---
# Ansible inventory for RHOSO deployment via SSH jump host (bastion)
# Generated for Lab: prod-btww2 (GUID: prod-btww2)
# Generated on: Thu Oct  2 16:29:10 CEST 2025

all:
  vars:
    # Lab-specific variables
    lab_guid: "prod-btww2"
    bastion_user: "lab-user"
    bastion_hostname: "ssh.ocpv08.rhdp.net"
    bastion_port: "30609"
    bastion_password: "sV2mlI17og4O"
    
    # OpenShift Console URL and credentials  
    ocp_console_url: "https://console-openshift-console.apps.cluster-k6bn5.dynamic.redhatworkshops.io"
    ocp_admin_password: "valEKzCStNMPlf0y"
    
    # External IP configuration
    rhoso_external_ip_worker_1: "192.168.4.32"
    rhoso_external_ip_worker_2: "192.168.4.33"
    rhoso_external_ip_worker_3: "192.168.4.34"
    rhoso_external_ip_bastion: "192.168.4.35"

# ... (bastion, nfsserver, compute_nodes sections)
```

## Integration with Deployment Scripts

### Single Lab Deployment

Use the generated inventory files with the single-lab deployment script:

```bash
# Deploy specific lab using generated inventory
./deploy-via-jumphost.sh --inventory inventory/hosts-prod-btww2.yml --credentials credentials.yml

# Deploy with specific phase
./deploy-via-jumphost.sh --inventory inventory/hosts-prod-btww2.yml --credentials credentials.yml control-plane

# Dry run
./deploy-via-jumphost.sh --inventory inventory/hosts-prod-btww2.yml --credentials credentials.yml --dry-run
```

### Multi-Lab Deployment

The multi-lab deployment script can still be used with the original configuration file:

```bash
# Deploy all labs in parallel
./deploy-multiple-labs.sh --labs my_labs_to_be_deployed --credentials credentials.yml

# Deploy with limited parallelism
./deploy-multiple-labs.sh --labs my_labs_to_be_deployed --credentials credentials.yml --max-parallel 2
```

## Benefits

1. **Individual Lab Management**: Deploy specific labs without affecting others
2. **Configuration Isolation**: Each lab has its own inventory file
3. **Easy Debugging**: Inspect and modify individual lab configurations
4. **Selective Deployment**: Deploy only the labs you need
5. **Version Control**: Track changes to specific lab configurations

## Input File Format

The script expects a lab configuration file in the format provided by the lab provisioning system. See `my_labs_to_be_deployed` for an example.

Required information per lab:
- Service identifier (e.g., `openshift-cnv.osp-on-ocp-cnv.prod-btww2`)
- SSH connection details (`ssh lab-user@hostname -p port`)
- SSH password
- OpenShift admin password
- External IP addresses
- Lab-specific data section

## Troubleshooting

### Common Issues

1. **File Already Exists**: Use `--force` to overwrite existing files
2. **No Labs Found**: Check the input file format and ensure it contains valid lab entries
3. **Missing Data**: Verify the lab configuration file has all required sections

### Debugging

Use `--dry-run` to see what would be generated:

```bash
./generate-lab-inventories.sh my_labs_to_be_deployed --dry-run
```

This shows:
- Which labs were detected
- What files would be created
- Lab configuration summary

## Related Scripts

- `deploy-via-jumphost.sh`: Single lab deployment with custom inventory
- `deploy-multiple-labs.sh`: Multi-lab parallel deployment
- `test-multi-lab-parsing.sh`: Test lab configuration parsing logic
