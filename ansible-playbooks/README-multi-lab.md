# Multi-Lab RHOSO Deployment

This document describes how to deploy multiple RHOSO labs in parallel using the `deploy-multiple-labs.sh` script.

## Overview

The multi-lab deployment script allows you to:

- Deploy multiple RHOSO labs simultaneously
- Use the same bastion host connectivity logic as the single-lab deployment
- Parse lab configuration files automatically
- Use external credentials files for security
- Control parallel execution with configurable job limits
- Monitor individual lab deployment progress

## Prerequisites

1. **Lab Configuration File**: A file containing multiple lab configurations (like `labs_to_be_deployed`)
2. **Credentials File**: A YAML file with your Red Hat credentials
3. **SSH Access**: Ability to SSH to all bastion hosts listed in the lab configuration
4. **sshpass**: Installed on your workstation for password-based SSH connections

## Quick Start

### 1. Prepare Your Credentials File

Create a credentials file based on the example:

```bash
cp credentials.yml.example my_credentials.yml
# Edit my_credentials.yml with your actual Red Hat credentials
```

Example `my_credentials.yml`:
```yaml
# Red Hat Registry Service Account Credentials
registry_username: "12345678|myserviceaccount"
registry_password: "eyJhbGciOiJSUzUxMiJ9..."

# Red Hat Customer Portal Credentials
rhc_username: "your-rh-username@email.com"
rhc_password: "YourRHPassword123"
```

### 2. Test Lab Configuration Parsing

Before running the actual deployment, test that your lab configuration file is parsed correctly:

```bash
./test-multi-lab-parsing.sh ../labs_to_be_deployed
```

This will show you:
- How many labs were detected
- What configuration data was extracted for each lab
- Any parsing issues that need to be resolved

### 3. Run Multi-Lab Deployment

Deploy all labs with default settings (3 parallel jobs):

```bash
./deploy-multiple-labs.sh --labs ../labs_to_be_deployed --credentials my_credentials.yml
```

## Advanced Usage

### Deploy Specific Phase

Deploy only a specific phase across all labs:

```bash
# Deploy only prerequisites phase
./deploy-multiple-labs.sh --labs ../labs_to_be_deployed --credentials my_credentials.yml prerequisites

# Deploy only control-plane phase
./deploy-multiple-labs.sh --labs ../labs_to_be_deployed --credentials my_credentials.yml control-plane
```

### Control Parallel Execution

Adjust the number of parallel deployments:

```bash
# Deploy with 5 parallel jobs
./deploy-multiple-labs.sh --labs ../labs_to_be_deployed --credentials my_credentials.yml -j 5

# Deploy with only 1 job (sequential)
./deploy-multiple-labs.sh --labs ../labs_to_be_deployed --credentials my_credentials.yml -j 1
```

### Dry Run Mode

Test the deployment without making changes:

```bash
./deploy-multiple-labs.sh --labs ../labs_to_be_deployed --credentials my_credentials.yml --dry-run
```

### Verbose Output

Enable verbose Ansible output for troubleshooting:

```bash
./deploy-multiple-labs.sh --labs ../labs_to_be_deployed --credentials my_credentials.yml --verbose
```

## Lab Configuration File Format

The script expects a lab configuration file with the following structure:

```
Service	Assigned Email	Details
openshift-cnv.osp-on-ocp-cnv.prod-lab1	
- unassigned -

Messages
OpenShift Console: https://console-openshift-console.apps.cluster-lab1.example.com

RHOSO External IP Allocation Details:
=======================================

Allocated IP Addresses:
EXTERNAL_IP_WORKER_1=192.168.4.0
EXTERNAL_IP_WORKER_2=192.168.4.1
EXTERNAL_IP_WORKER_3=192.168.4.2
EXTERNAL_IP_BASTION=192.168.4.3

User admin with password AdminPassword123 is cluster admin.
You can access your bastion via SSH:
ssh lab-user@ssh.example.com -p 30001

Enter ssh password when prompted: SSHPassword123

Data
openshift-cnv.osp-on-ocp-cnv.prod:
  bastion_public_hostname: ssh.example.com
  bastion_ssh_password: SSHPassword123
  bastion_ssh_port: '30001'
  bastion_ssh_user_name: lab-user
  guid: lab1
  openshift_cluster_admin_password: AdminPassword123
  # ... additional YAML configuration data
```

### Key Elements Parsed

The script extracts the following information from each lab entry:

1. **Lab ID**: From the service name (e.g., `prod-lab1`)
2. **SSH Connection**: Hostname, port, and password from SSH command
3. **Admin Password**: OpenShift cluster admin password
4. **External IPs**: Worker and bastion IP addresses
5. **Console URL**: OpenShift console URL
6. **Data Section**: All YAML configuration under the "Data" section

## Deployment Process

For each lab, the script:

1. **Parses Configuration**: Extracts lab-specific settings
2. **Creates Inventory**: Generates Ansible inventory with lab details
3. **Injects Credentials**: Adds Red Hat credentials from the credentials file
4. **Connects to Bastion**: SSH to the lab's bastion host
5. **Sets Up Environment**: Installs required packages and Python libraries
6. **Copies Files**: Transfers deployment files to bastion
7. **Runs Deployment**: Executes Ansible playbooks on the bastion
8. **Logs Progress**: Maintains separate log files for each lab

## Monitoring Progress

### Real-time Status

The script provides real-time status updates:

```
[DEPLOY] Multi-Lab RHOSO Deployment - Phase: full
[INFO] Timestamp: Thu Oct  2 15:30:00 UTC 2025
[INFO] Labs config: ../labs_to_be_deployed
[INFO] Credentials: my_credentials.yml
[INFO] Max parallel jobs: 3
[LAB-prod-75h26] Starting deployment in background
[LAB-prod-rcspg] Starting deployment in background
[LAB-prod-xs7xj] Starting deployment in background
[LAB-prod-75h26] Completed successfully
[LAB-prod-rcspg] Completed successfully
[LAB-prod-xs7xj] Failed with exit code 1
```

### Log Files

Each lab deployment creates a separate log file:

```
/tmp/rhoso-multi-deploy-<pid>/lab_<lab-id>/deployment.log
```

These logs contain the complete Ansible output for each lab.

## Available Phases

| Phase | Description |
|-------|-------------|
| `prerequisites` | Install required operators (NMState, MetalLB) |
| `install-operators` | Install OpenStack operators |
| `security` | Configure secrets and security |
| `nfs-server` | Configure NFS server |
| `network-isolation` | Set up network isolation |
| `control-plane` | Deploy OpenStack control plane |
| `data-plane` | Configure compute nodes |
| `validation` | Verify deployment |
| `full` | Run complete deployment (default) |
| `optional` | Enable optional services (Heat, Swift) |

## Troubleshooting

### Common Issues

1. **Parsing Errors**: Run `./test-multi-lab-parsing.sh` to validate your lab configuration file
2. **SSH Connection Failures**: Verify bastion hostnames, ports, and passwords
3. **Missing Credentials**: Ensure your credentials file has all required fields
4. **Permission Issues**: Check that SSH keys are present on bastion hosts
5. **Resource Limits**: Reduce parallel jobs if experiencing resource constraints

### Debug Mode

For detailed troubleshooting, use verbose mode and check individual log files:

```bash
./deploy-multiple-labs.sh --labs ../labs_to_be_deployed --credentials my_credentials.yml --verbose -j 1
```

### Manual Verification

You can manually verify connectivity to each lab:

```bash
# Test single lab connectivity
./test-bastion-connectivity.sh

# Test specific bastion
ssh lab-user@ssh.ocpv06.rhdp.net -p 30940
```

## Performance Considerations

- **Parallel Jobs**: Default is 3 concurrent deployments. Adjust based on your system resources
- **Network Bandwidth**: Multiple simultaneous deployments require adequate bandwidth
- **Bastion Resources**: Each bastion host needs sufficient resources for deployment
- **Time Estimates**: Full deployment typically takes 30-60 minutes per lab

## Security Notes

- **Credentials File**: Keep your credentials file secure and exclude from version control
- **SSH Passwords**: Consider using SSH keys instead of passwords for better security
- **Log Files**: Deployment logs may contain sensitive information; handle appropriately
- **Temporary Files**: The script cleans up temporary files automatically

## Examples

### Deploy All Labs with Custom Settings

```bash
./deploy-multiple-labs.sh \
  --labs ../labs_to_be_deployed \
  --credentials my_credentials.yml \
  --jobs 2 \
  --verbose \
  full
```

### Deploy Only Control Plane Phase

```bash
./deploy-multiple-labs.sh \
  --labs ../labs_to_be_deployed \
  --credentials my_credentials.yml \
  control-plane
```

### Test Configuration Without Deployment

```bash
./deploy-multiple-labs.sh \
  --labs ../labs_to_be_deployed \
  --credentials my_credentials.yml \
  --dry-run
```

This multi-lab deployment capability significantly reduces the time and effort required to deploy RHOSO across multiple lab environments while maintaining the same reliability and features as single-lab deployments.
