#!/bin/bash
# Test SSH connectivity to lab resources 
# This script can be run from your workstation (using jump host) or directly from the bastion

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_header() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Check if we have the inventory file
if [[ ! -f "inventory/hosts.yml" ]]; then
    print_error "inventory/hosts.yml not found. Please run this script from the ansible-playbooks directory."
    exit 1
fi

# Get configuration from inventory
GUID=$(grep "lab_guid:" inventory/hosts.yml | cut -d'"' -f2)
BASTION_USER=$(grep "bastion_user:" inventory/hosts.yml | cut -d'"' -f2)
BASTION_HOST=$(grep "bastion_hostname:" inventory/hosts.yml | cut -d'"' -f2)
BASTION_PORT=$(grep "bastion_port:" inventory/hosts.yml | cut -d'"' -f2)

if [[ "$GUID" == "changeme" ]]; then
    print_error "Please update the lab_guid in inventory/hosts.yml"
    exit 1
fi

print_header "SSH Connectivity Test for RHOSO Lab Environment"
print_status "Configuration:"
print_status "  GUID: $GUID"
print_status "  Bastion: $BASTION_USER@$BASTION_HOST:$BASTION_PORT"

# Detect if we're running from workstation or bastion
if [[ $(hostname) == *"bastion"* ]] || [[ -f "/home/${BASTION_USER}/.ssh/${GUID}key.pem" ]]; then
    print_header "Running on bastion - testing direct SSH"
    SSH_PREFIX=""
    SSH_KEY_PATH="/home/${BASTION_USER}/.ssh/${GUID}key.pem"
else
    print_header "Running from workstation - testing via jump host"
    SSH_PREFIX="ssh -p ${BASTION_PORT} ${BASTION_USER}@${BASTION_HOST}"
    SSH_KEY_PATH="/home/${BASTION_USER}/.ssh/${GUID}key.pem"
    
    # Test bastion connectivity first
    print_header "Testing bastion connectivity"
    if ssh -p ${BASTION_PORT} -o ConnectTimeout=10 -o StrictHostKeyChecking=no ${BASTION_USER}@${BASTION_HOST} 'echo "Bastion connection successful"' >/dev/null 2>&1; then
        print_status "✅ Bastion connection successful"
    else
        print_error "❌ Cannot connect to bastion. Please check your connection and credentials."
        print_error "Try: ssh -p ${BASTION_PORT} ${BASTION_USER}@${BASTION_HOST}"
        exit 1
    fi
fi

# Test NFS server connectivity
print_header "Testing NFS server connectivity"
if [[ -n "$SSH_PREFIX" ]]; then
    # Via jump host
    TEST_CMD="$SSH_PREFIX 'ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@nfsserver \"echo NFS server connection successful\"'"
else
    # Direct from bastion
    TEST_CMD="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@nfsserver 'echo \"NFS server connection successful\"'"
fi

if eval $TEST_CMD >/dev/null 2>&1; then
    print_status "✅ NFS server (nfsserver) - Connection successful"
else
    print_error "❌ NFS server (nfsserver) - Connection failed"
    if [[ -n "$SSH_PREFIX" ]]; then
        print_warning "Try manually: $SSH_PREFIX"
        print_warning "Then from bastion: ssh -i $SSH_KEY_PATH cloud-user@nfsserver"
    else
        print_warning "Try manually: ssh -i $SSH_KEY_PATH cloud-user@nfsserver"
    fi
    exit 1
fi

# Test compute node connectivity
print_header "Testing compute node connectivity"
if [[ -n "$SSH_PREFIX" ]]; then
    # Via jump host
    TEST_CMD="$SSH_PREFIX 'ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@compute01 \"echo Compute node connection successful\"'"
else
    # Direct from bastion
    TEST_CMD="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@compute01 'echo \"Compute node connection successful\"'"
fi

if eval $TEST_CMD >/dev/null 2>&1; then
    print_status "✅ Compute node (compute01) - Connection successful"
else
    print_error "❌ Compute node (compute01) - Connection failed"
    if [[ -n "$SSH_PREFIX" ]]; then
        print_warning "Try manually: $SSH_PREFIX"
        print_warning "Then from bastion: ssh -i $SSH_KEY_PATH cloud-user@compute01"
    else
        print_warning "Try manually: ssh -i $SSH_KEY_PATH cloud-user@compute01"
    fi
    exit 1
fi

# Test sudo access on NFS server
print_header "Testing sudo access on NFS server"
if [[ -n "$SSH_PREFIX" ]]; then
    TEST_CMD="$SSH_PREFIX 'ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@nfsserver \"sudo whoami\"'"
else
    TEST_CMD="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@nfsserver 'sudo whoami'"
fi

if eval $TEST_CMD >/dev/null 2>&1; then
    print_status "✅ NFS server sudo access - Working"
else
    print_error "❌ NFS server sudo access - Failed"
    exit 1
fi

# Test sudo access on compute node
print_header "Testing sudo access on compute node"
if [[ -n "$SSH_PREFIX" ]]; then
    TEST_CMD="$SSH_PREFIX 'ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@compute01 \"sudo whoami\"'"
else
    TEST_CMD="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no -o ConnectTimeout=10 cloud-user@compute01 'sudo whoami'"
fi

if eval $TEST_CMD >/dev/null 2>&1; then
    print_status "✅ Compute node sudo access - Working"
else
    print_error "❌ Compute node sudo access - Failed"
    exit 1
fi

print_header "🎉 All SSH connectivity tests passed! ✅"
print_status "The ansible playbooks should now work correctly with:"
echo "  - NFS server configuration (nfs-server role)"
echo "  - Compute node configuration (data-plane role)"
print_status ""
if [[ -n "$SSH_PREFIX" ]]; then
    print_status "You can now run: ./deploy-via-jumphost.sh"
else
    print_status "You can now run: ansible-playbook site.yml"
fi
