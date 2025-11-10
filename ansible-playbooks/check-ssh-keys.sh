#!/bin/bash
# Check what SSH keys are available on the bastion and update inventory accordingly

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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
    echo -e "${BLUE}[CHECK]${NC} $1"
}

# Get configuration from inventory
if [[ ! -f "inventory/hosts.yml" ]]; then
    print_error "inventory/hosts.yml not found. Please run this script from the ansible-playbooks directory."
    exit 1
fi

BASTION_USER=$(grep "bastion_user:" inventory/hosts.yml | cut -d'"' -f2)
BASTION_HOST=$(grep "bastion_hostname:" inventory/hosts.yml | cut -d'"' -f2)
BASTION_PORT=$(grep "bastion_port:" inventory/hosts.yml | cut -d'"' -f2)
CURRENT_GUID=$(grep "lab_guid:" inventory/hosts.yml | cut -d'"' -f2)

print_header "Checking SSH keys on bastion: $BASTION_USER@$BASTION_HOST:$BASTION_PORT"
print_status "Current GUID in inventory: $CURRENT_GUID"

# Check what SSH keys are available on bastion
print_header "Listing SSH keys on bastion..."
ssh -p ${BASTION_PORT} ${BASTION_USER}@${BASTION_HOST} 'ls -la /home/'${BASTION_USER}'/.ssh/*.pem 2>/dev/null || echo "No .pem files found"'

print_header "Listing all files in .ssh directory..."
ssh -p ${BASTION_PORT} ${BASTION_USER}@${BASTION_HOST} 'ls -la /home/'${BASTION_USER}'/.ssh/'

# Try to detect the correct GUID from available key files
print_header "Detecting correct GUID from available keys..."
AVAILABLE_KEYS=$(ssh -p ${BASTION_PORT} ${BASTION_USER}@${BASTION_HOST} 'ls /home/'${BASTION_USER}'/.ssh/*.pem 2>/dev/null | grep -o "[a-z0-9]\{5\}key\.pem" | sed "s/key\.pem//" || echo ""')

if [[ -n "$AVAILABLE_KEYS" ]]; then
    print_status "Found SSH key(s) with GUID(s): $AVAILABLE_KEYS"
    
    # Take the first one found
    DETECTED_GUID=$(echo "$AVAILABLE_KEYS" | head -1)
    print_status "Using GUID: $DETECTED_GUID"
    
    if [[ "$DETECTED_GUID" != "$CURRENT_GUID" ]]; then
        print_warning "GUID mismatch detected!"
        print_warning "Inventory has: $CURRENT_GUID"
        print_warning "Bastion has key for: $DETECTED_GUID"
        print_status "Updating inventory with correct GUID..."
        
        # Update the inventory file
        sed -i.bak "s/lab_guid: \"$CURRENT_GUID\"/lab_guid: \"$DETECTED_GUID\"/" inventory/hosts.yml
        print_status "✅ Updated inventory/hosts.yml (backup saved as .bak)"
        print_status "New GUID: $DETECTED_GUID"
    else
        print_status "✅ GUID matches - checking key accessibility..."
    fi
    
    # Test the key
    print_header "Testing SSH key: /home/${BASTION_USER}/.ssh/${DETECTED_GUID}key.pem"
    if ssh -p ${BASTION_PORT} ${BASTION_USER}@${BASTION_HOST} "ssh -i /home/${BASTION_USER}/.ssh/${DETECTED_GUID}key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 cloud-user@nfsserver 'echo SSH key test successful'" 2>/dev/null; then
        print_status "✅ SSH key works for nfsserver!"
    else
        print_error "❌ SSH key test failed for nfsserver"
        print_warning "The key exists but may not be authorized or nfsserver may not be accessible"
    fi
    
    if ssh -p ${BASTION_PORT} ${BASTION_USER}@${BASTION_HOST} "ssh -i /home/${BASTION_USER}/.ssh/${DETECTED_GUID}key.pem -o StrictHostKeyChecking=no -o ConnectTimeout=5 cloud-user@compute01 'echo SSH key test successful'" 2>/dev/null; then
        print_status "✅ SSH key works for compute01!"
    else
        print_error "❌ SSH key test failed for compute01"
        print_warning "The key exists but may not be authorized or compute01 may not be accessible"
    fi
    
else
    print_error "❌ No SSH keys found matching pattern *key.pem"
    print_warning "Expected pattern: {5-char-guid}key.pem (e.g., s7ffskey.pem)"
    print_warning "Please check if the SSH keys exist or have a different naming pattern"
fi

print_header "Summary"
print_status "If the inventory was updated, you can now try running the deployment again:"
print_status "./deploy-via-jumphost.sh nfs-server"
