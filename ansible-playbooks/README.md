# Red Hat OpenStack Services on OpenShift (RHOSO) Deployment Ansible Playbooks

This repository contains Ansible playbooks that automate the deployment of Red Hat OpenStack Services on OpenShift (RHOSO) based on the connected environment documentation. The playbooks convert the step-by-step manual instructions into idempotent, automated workflows.

## Overview

These playbooks automate the following deployment phases:

1. **Prerequisites** - Verify cluster access and install required operators (NMState, MetalLB)
2. **Install Operators** - Deploy the OpenStack operators and initialize them
3. **NFS Server Configuration** - Set up NFS storage for Glance and Cinder
4. **Network Isolation** - Configure OpenShift networking for OpenStack networks
5. **Security Configuration** - Create required secrets and security configurations
6. **Control Plane** - Deploy the OpenStack control plane services
7. **Data Plane** - Configure and deploy the compute nodes
8. **Validation** - Verify the deployment and access OpenStack services

## Prerequisites

### Software Requirements

- Ansible 2.12 or newer
- Python 3.8+
- OpenShift CLI (`oc`) configured with cluster access
- SSH key-based authentication to lab nodes

### Lab Environment Requirements

- Operational OpenShift 4.16+ cluster with Multus CNI support
- Bastion host with `oc` and `podman` command line tools
- NFS server node (RHEL 9.4)
- Compute node (RHEL 9.4)
- Network connectivity between all components

### Required Credentials

You must provide the following credentials:

1. **Red Hat Registry Service Account** 
   - Username and password/token from [Registry Service Accounts](https://access.redhat.com/articles/RegistryAuthentication#creating-registry-service-accounts-6)

2. **Red Hat Customer Portal Credentials**
   - Username and password from [Red Hat Customer Portal](https://www.redhat.com/wapps/ugc/protected/password.html)

## Quick Start

### SSH Jump Host Scenario (Recommended)

This deployment method is designed for environments where the OpenShift cluster can only be reached through a bastion/jump host. The playbooks will connect to the bastion host and then use SSH proxy commands to reach internal hosts (NFS server, compute nodes).

#### Prerequisites

1. **SSH Access to Bastion**: You must be able to SSH to your bastion host
2. **sshpass**: Install `sshpass` on your workstation for password-based SSH connections
3. **SSH Keys**: Ensure your lab SSH keys are available on the bastion host at `/home/lab-user/.ssh/`

#### 1. Configure Inventory

Edit `inventory/hosts.yml` and update the following variables with your lab details:

```yaml
# REQUIRED: Update these values for your environment
lab_guid: "your-lab-guid"                     # e.g., "a1b2c"
bastion_hostname: "ssh.ocpvdev01.rhdp.net"    # Your actual bastion hostname
bastion_port: "31295"                         # Your actual SSH port
bastion_password: "your-bastion-password"     # Your actual password
bastion_user: "lab-user"                      # Usually lab-user

# REQUIRED: Add your Red Hat credentials
registry_username: "your-registry-service-account"
registry_password: "your-registry-token"
rhc_username: "your-rh-username"
rhc_password: "your-rh-password"

# OPTIONAL: Internal hostnames (usually defaults work)
nfs_server_hostname: "nfsserver"              # Internal hostname for NFS server
compute_hostname: "compute01"                 # Internal hostname for compute node

# OPTIONAL: External IPs for OpenShift worker nodes (update if different)
rhoso_external_ip_worker_1: "172.21.0.21"    # External IP for worker node 1
rhoso_external_ip_worker_2: "172.21.0.22"    # External IP for worker node 2
rhoso_external_ip_worker_3: "172.21.0.23"    # External IP for worker node 3
```

#### 2. Optional: Configure SSH (Alternative Method)

For better SSH management, you can copy `ssh-config.template` to `~/.ssh/config` and update it with your values. This allows direct SSH to internal hosts:

```bash
cp ssh-config.template ~/.ssh/config
# Edit ~/.ssh/config with your actual values
```

#### 3. Check Configuration

```bash
./deploy-via-jumphost.sh --check-inventory
```

#### 4. Run Deployment

```bash
# Full deployment
./deploy-via-jumphost.sh

# Or specific phases
./deploy-via-jumphost.sh prerequisites
./deploy-via-jumphost.sh control-plane

# Dry run (check mode)
./deploy-via-jumphost.sh --dry-run full
```

#### Troubleshooting SSH Jump Host Issues

1. **SSH Connection Failures**: Ensure `sshpass` is installed and your bastion credentials are correct
2. **Permission Denied**: Verify SSH keys are present on bastion at `/home/lab-user/.ssh/LAB_GUIDkey.pem`
3. **Proxy Command Errors**: Check that internal hostnames (nfsserver, compute01) are resolvable from bastion
4. **Timeout Issues**: Internal hosts may take time to boot; retry after a few minutes

### Direct Bastion Access Scenario

If you're running directly on the bastion host:

#### 1. Install Required Collections

```bash
ansible-galaxy collection install -r requirements.yml
```

#### 2. Configure Inventory

Edit `inventory/hosts.yml` for direct access (no SSH jump)

#### 3. Run Deployment

```bash
ansible-playbook site.yml
```

## Individual Role Execution

You can run individual roles for troubleshooting or partial deployments:

```bash
# Prerequisites only
ansible-playbook site.yml --tags prerequisites

# Network configuration only  
ansible-playbook site.yml --tags network-isolation

# Control plane only
ansible-playbook site.yml --tags control-plane
```

## Project Structure

```
ansible-playbooks/
├── site.yml                 # Main playbook orchestrating all roles
├── ansible.cfg              # Ansible configuration
├── requirements.yml         # Required Ansible collections
├── inventory/
│   └── hosts.yml            # Inventory template (MUST be customized)
├── vars/
│   └── main.yml            # Global variables and configuration
└── roles/
    ├── prerequisites/       # Install required operators
    ├── install-operators/   # Deploy OpenStack operators
    ├── nfs-server/         # Configure NFS storage
    ├── network-isolation/   # Set up network isolation
    ├── security/           # Configure secrets and security
    ├── control-plane/      # Deploy OpenStack control plane
    ├── data-plane/         # Configure compute nodes
    └── validation/         # Verify deployment and access
```

## Key Variables

### Lab Environment (`vars/main.yml`)

- `guid`: Lab environment GUID 
- `networks`: Network configuration for all OpenStack networks
- `compute_nodes`: Compute node configuration
- `nfs_server_ip`: NFS server IP address

### Worker Node External IPs (`vars/main.yml`)

- `worker_external_ips`: Configuration for OpenShift worker node external interfaces
  - `rhoso_external_ip_worker_1`: External IP for worker node 1 (default: 172.21.0.21)
  - `rhoso_external_ip_worker_2`: External IP for worker node 2 (default: 172.21.0.22)
  - `rhoso_external_ip_worker_3`: External IP for worker node 3 (default: 172.21.0.23)

### Timeouts

- `operator_wait_timeout`: 600 seconds (operator installation)
- `deployment_wait_timeout`: 1800 seconds (deployment completion)

## Network Configuration

The playbooks use the following network layout:

| Network     | VLAN | CIDR            | Purpose                    |
|-------------|------|-----------------|----------------------------|
| ctlplane    | n/a  | 172.22.0.0/24   | Control plane network      |
| external    | n/a  | 172.21.0.0/24   | External/public network    |
| internalapi | 20   | 172.17.0.0/24   | Internal API network       |
| storage     | 21   | 172.18.0.0/24   | Storage network            |
| tenant      | 22   | 172.19.0.0/24   | Tenant/VM network          |

## Common Issues and Troubleshooting

### 1. Authentication Issues

**Problem**: SSH authentication failures to lab nodes
**Solution**: Ensure SSH keys are properly configured and accessible

### 2. Operator Installation Timeout

**Problem**: Operators fail to install within timeout period
**Solution**: Increase `operator_wait_timeout` in `vars/main.yml` or check cluster resources

### 3. Registry Authentication

**Problem**: Container image pull failures
**Solution**: Verify Red Hat registry credentials are correct and active

### 4. Network Configuration Issues

**Problem**: Network isolation setup fails
**Solution**: Verify OpenShift worker nodes have the required network interfaces

### 5. Control Plane Deployment Timeout

**Problem**: OpenStack services don't come up within timeout
**Solution**: Check cluster resources and increase `deployment_wait_timeout`

## Verification Commands

After successful deployment, verify the installation:

```bash
# Check OpenStack services
oc rsh -n openstack openstackclient
openstack compute service list
openstack network agent list

# Check running pods
oc get pods -n openstack-operators
oc get pods -n openstack

# Check control plane status
oc get openstackcontrolplane -n openstack

# Check data plane status  
oc get openstackdataplanedeployment -n openstack
```

## Security Notes

- Default passwords are set to 'openstack' (base64 encoded)
- Change default passwords in production environments
- SSH keys are managed automatically by the playbooks
- Secrets are created with appropriate OpenShift RBAC controls

## Support

This playbook automation is based on the official RHOSO documentation. For issues:

1. Check the troubleshooting section above
2. Verify your lab environment meets all prerequisites  
3. Review Ansible output for specific error messages
4. Consult the original AsciiDoc documentation for manual steps

## Contributing

When modifying these playbooks:

1. Maintain idempotency - tasks should be safe to run multiple times
2. Use appropriate Ansible modules instead of shell commands where possible
3. Add proper error handling and verification steps
4. Update documentation for any new variables or requirements
5. Test thoroughly in a lab environment before production use
