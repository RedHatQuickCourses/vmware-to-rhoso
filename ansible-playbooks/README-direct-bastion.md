# RHOSO Direct Bastion Deployment

This guide explains how to run the RHOSO ansible-playbooks directly from the bastion host instead of using a jumphost.

## Overview

The `deploy-from-bastion.sh` script allows you to execute the RHOSO deployment directly on the bastion host, eliminating the need for SSH jump host connectivity. This approach can be useful when:

- You have direct access to the bastion host
- You want to avoid SSH connection complexity
- You need to run deployments locally for debugging purposes
- Network connectivity issues prevent jumphost usage

## Prerequisites

1. **Direct access to the bastion host** - You must be logged into the bastion host directly
2. **Sudo access** - The script will automatically install required packages using sudo
3. **Internet connectivity** - For downloading packages and Python libraries

**Note**: The script automatically installs all required dependencies including:
- Ansible 2.12 or newer
- OpenShift CLI (oc) if available in system repositories
- Python 3.11 and pip
- Required Python libraries (kubernetes, openshift, jmespath, etc.)
- Additional system packages (git, sshpass, etc.)

## Setup

### 1. Copy the Repository

First, copy the entire repository to your bastion host:

```bash
# On your local machine, copy to bastion
scp -r ansible-playbooks/ lab-user@your-bastion-host:/home/lab-user/rhoso-deployment/
```

Or clone directly on the bastion:

```bash
# On the bastion host
git clone <repository-url> rhoso-deployment
cd rhoso-deployment/ansible-playbooks
```

### 2. Create Inventory File

Copy the bastion-specific inventory template:

```bash
cp inventory/hosts-bastion.yml.example inventory/hosts-bastion.yml
```

Edit the inventory file with your lab-specific values:

```bash
vim inventory/hosts-bastion.yml
```

**Key differences from jumphost inventory:**
- `bastion` host uses `localhost` with `ansible_connection: local`
- No SSH proxy configuration needed
- Direct SSH connections to NFS server and compute nodes

### 3. Configure Credentials

You can provide credentials in two ways:

#### Option A: Edit inventory directly
Update the credential fields in `inventory/hosts-bastion.yml`:
- `registry_username` and `registry_password`
- `rhc_username` and `rhc_password`

#### Option B: Use external credentials file
Create a separate credentials file:

```yaml
# credentials.yml
registry_username: "12345678|myserviceaccount"
registry_password: "eyJhbGciOiJSUzUxMiJ9..."
rhc_username: "your-rh-username@email.com"
rhc_password: "YourRHPassword123"
```

## Usage

### Basic Commands

```bash
# Check inventory configuration
./deploy-from-bastion.sh -c

# Run full deployment
./deploy-from-bastion.sh

# Run specific phase
./deploy-from-bastion.sh control-plane

# Dry run (check mode)
./deploy-from-bastion.sh -d full

# Verbose output
./deploy-from-bastion.sh -v prerequisites

# Use external credentials
./deploy-from-bastion.sh --credentials credentials.yml full

# Use custom inventory
./deploy-from-bastion.sh --inventory my-lab/hosts-bastion.yml full
```

### Background Execution

```bash
# Run in background
./deploy-from-bastion.sh -b full

# Run in background and follow logs
./deploy-from-bastion.sh --follow-logs full

# Check status of background deployments
./deploy-from-bastion.sh --status

# Stop a background deployment
./deploy-from-bastion.sh --stop <PID>
```

### Available Phases

- `prerequisites` - Install required operators (NMState, MetalLB)
- `install-operators` - Install OpenStack operators
- `security` - Configure secrets and security
- `nfs-server` - Configure NFS server
- `network-isolation` - Set up network isolation
- `control-plane` - Deploy OpenStack control plane
- `data-plane` - Configure compute nodes
- `validation` - Verify deployment
- `full` - Run complete deployment (default)
- `optional` - Enable optional services (Heat, Swift)

## Differences from Jumphost Deployment

| Aspect | Jumphost (`deploy-via-jumphost.sh`) | Direct Bastion (`deploy-from-bastion.sh`) |
|--------|-----------------------------------|------------------------------------------|
| **Execution Location** | Runs from external machine, SSH to bastion | Runs directly on bastion host |
| **SSH Connectivity** | Requires SSH jump host setup | Direct SSH to target hosts |
| **Inventory** | Uses `hosts.yml` with proxy config | Uses `hosts-bastion.yml` with local config |
| **Bastion Connection** | `ansible_host: bastion_hostname` | `ansible_connection: local` |
| **File Transfer** | Copies files via SCP to bastion | Files already present on bastion |
| **Dependencies** | Installs dependencies on bastion remotely | Uses local dependencies |

## Troubleshooting

### Common Issues

**Note**: Most dependency issues are now automatically resolved by the script. The following are manual solutions if automatic installation fails:

1. **Ansible not found (automatic installation failed)**
   ```bash
   # Manual installation on RHEL/CentOS
   sudo dnf install -y ansible-core python3-pip python3-kubernetes python3-jmespath python3-yaml python3-requests sshpass
   ```

2. **OpenShift CLI not found**
   ```bash
   # Download and install oc manually
   curl -LO https://mirror.openshift.com/pub/openshift-v4/clients/ocp/stable/openshift-client-linux.tar.gz
   tar -xzf openshift-client-linux.tar.gz
   sudo mv oc /usr/local/bin/
   ```

3. **Python 3.11 dependencies missing (automatic installation failed)**
   ```bash
   # Manual installation for Python 3.11
   sudo dnf install -y python3.11 python3.11-pip
   /usr/bin/python3.11 -m pip install --user kubernetes openshift jmespath pyyaml requests urllib3
   ```

4. **SSH key permissions**
   ```bash
   # Fix SSH key permissions
   chmod 600 /home/lab-user/.ssh/*key.pem
   ```

5. **Inventory configuration errors**
   ```bash
   # Check inventory syntax
   ansible-inventory -i inventory/hosts-bastion.yml --list
   
   # Test connectivity
   ansible -i inventory/hosts-bastion.yml all -m ping
   ```

### Log Files

All deployments create detailed log files in the `logs/` directory:
- `deployment_<lab_id>_<timestamp>.log` - Main deployment log
- Background deployments also create PID files in `pids/` directory

### Getting Help

```bash
# Show detailed usage information
./deploy-from-bastion.sh --help

# Check current status
./deploy-from-bastion.sh --status
```

## Migration from Jumphost

If you're migrating from jumphost deployment to direct bastion deployment:

1. Copy your existing `inventory/hosts.yml` to `inventory/hosts-bastion.yml`
2. Update the bastion host configuration:
   ```yaml
   bastion:
     hosts:
       localhost:  # Changed from bastion-jumphost
         ansible_connection: local  # Changed from SSH
         ansible_python_interpreter: "{{ ansible_playbook_python }}"
   ```
3. Remove SSH proxy configurations from other hosts
4. Test with a dry run: `./deploy-from-bastion.sh -d -c`

## Security Considerations

- Credentials are temporarily stored in inventory files during deployment
- Use external credentials files when possible
- Ensure proper file permissions on credential files (600)
- Clean up temporary files after deployment
- Consider using Ansible Vault for sensitive data

## Performance Benefits

Running directly from the bastion can provide:
- Faster execution (no SSH overhead)
- Better error handling and logging
- Easier debugging and troubleshooting
- More reliable network connectivity to OpenShift
