#!/bin/bash
# Test script to verify bastion host connectivity and SSH proxy functionality
# This script helps troubleshoot common connectivity issues

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
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Function to extract values from inventory
get_inventory_value() {
    local key="$1"
    grep "$key:" inventory/hosts.yml | sed "s/.*$key: *['\"]\\?\\([^'\"]*\\)['\"]\\?.*/\\1/" | head -1
}

# Main test function
main() {
    print_header "Testing Bastion Host Connectivity"
    
    # Check if inventory file exists
    if [[ ! -f "inventory/hosts.yml" ]]; then
        print_error "Inventory file inventory/hosts.yml not found!"
        exit 1
    fi
    
    # Extract connection details
    local bastion_host=$(get_inventory_value "bastion_hostname")
    local bastion_port=$(get_inventory_value "bastion_port")
    local bastion_user=$(get_inventory_value "bastion_user")
    local bastion_password=$(get_inventory_value "bastion_password")
    local lab_guid=$(get_inventory_value "lab_guid")
    
    print_status "Configuration found:"
    echo "  Bastion: ${bastion_user}@${bastion_host}:${bastion_port}"
    echo "  Lab GUID: ${lab_guid}"
    echo ""
    
    # Test 1: Check if sshpass is available
    print_header "Test 1: Checking sshpass availability"
    if command -v sshpass &> /dev/null; then
        print_status "sshpass is available"
    else
        print_warning "sshpass not found. Install with: sudo dnf install sshpass"
        print_warning "Continuing with manual SSH (you'll need to enter passwords manually)"
    fi
    echo ""
    
    # Test 2: Test basic SSH connectivity to bastion
    print_header "Test 2: Testing SSH connectivity to bastion"
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" && "$bastion_password" != "changeme" ]]; then
        if sshpass -p "$bastion_password" ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "echo 'SSH connection successful'" 2>/dev/null; then
            print_status "SSH connection to bastion successful"
        else
            print_error "SSH connection to bastion failed"
            echo "  Check your bastion_hostname, bastion_port, bastion_user, and bastion_password"
            exit 1
        fi
    else
        print_warning "Testing SSH manually (enter password when prompted):"
        echo "ssh -p $bastion_port $bastion_user@$bastion_host 'echo SSH connection successful'"
        if ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "echo 'SSH connection successful'"; then
            print_status "SSH connection to bastion successful"
        else
            print_error "SSH connection to bastion failed"
            exit 1
        fi
    fi
    echo ""
    
    # Test 3: Check SSH keys on bastion
    print_header "Test 3: Checking SSH keys on bastion"
    local ssh_key_check="ls -la /home/$bastion_user/.ssh/${lab_guid}key.pem 2>/dev/null || echo 'SSH key not found'"
    
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" && "$bastion_password" != "changeme" ]]; then
        local key_result=$(sshpass -p "$bastion_password" ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$ssh_key_check" 2>/dev/null)
    else
        print_warning "Enter password to check SSH keys:"
        local key_result=$(ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$ssh_key_check")
    fi
    
    if [[ "$key_result" == *"SSH key not found"* ]]; then
        print_error "SSH key /home/$bastion_user/.ssh/${lab_guid}key.pem not found on bastion"
        print_warning "Make sure your lab SSH keys are uploaded to the bastion host"
    else
        print_status "SSH key found on bastion"
        echo "  $key_result"
    fi
    echo ""
    
    # Test 4: Test connectivity to internal hosts through bastion
    print_header "Test 4: Testing connectivity to internal hosts through bastion"
    local nfs_server_hostname=$(get_inventory_value "nfs_server_hostname")
    local compute_hostname=$(get_inventory_value "compute_hostname")
    
    print_status "Testing connectivity to NFS server ($nfs_server_hostname)..."
    local nfs_test_cmd="ssh -i /home/$bastion_user/.ssh/${lab_guid}key.pem -o ConnectTimeout=10 -o StrictHostKeyChecking=no cloud-user@$nfs_server_hostname 'echo NFS server reachable' 2>/dev/null || echo 'NFS server not reachable'"
    
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" && "$bastion_password" != "changeme" ]]; then
        local nfs_result=$(sshpass -p "$bastion_password" ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$nfs_test_cmd" 2>/dev/null)
    else
        print_warning "Enter password to test NFS connectivity:"
        local nfs_result=$(ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$nfs_test_cmd")
    fi
    
    if [[ "$nfs_result" == *"NFS server reachable"* ]]; then
        print_status "NFS server ($nfs_server_hostname) is reachable through bastion"
    else
        print_warning "NFS server ($nfs_server_hostname) not reachable - it may not be running yet"
    fi
    
    print_status "Testing connectivity to compute node ($compute_hostname)..."
    local compute_test_cmd="ssh -i /home/$bastion_user/.ssh/${lab_guid}key.pem -o ConnectTimeout=10 -o StrictHostKeyChecking=no cloud-user@$compute_hostname 'echo Compute node reachable' 2>/dev/null || echo 'Compute node not reachable'"
    
    if command -v sshpass &> /dev/null && [[ -n "$bastion_password" && "$bastion_password" != "changeme" ]]; then
        local compute_result=$(sshpass -p "$bastion_password" ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$compute_test_cmd" 2>/dev/null)
    else
        print_warning "Enter password to test compute connectivity:"
        local compute_result=$(ssh -o StrictHostKeyChecking=no -p "$bastion_port" "$bastion_user@$bastion_host" "$compute_test_cmd")
    fi
    
    if [[ "$compute_result" == *"Compute node reachable"* ]]; then
        print_status "Compute node ($compute_hostname) is reachable through bastion"
    else
        print_warning "Compute node ($compute_hostname) not reachable - it may not be running yet"
    fi
    echo ""
    
    # Test 5: Test Ansible connectivity
    print_header "Test 5: Testing Ansible connectivity"
    if command -v ansible &> /dev/null; then
        print_status "Testing Ansible ping to bastion..."
        if ansible bastion -m ping -i inventory/hosts.yml; then
            print_status "Ansible can connect to bastion successfully"
        else
            print_error "Ansible cannot connect to bastion"
            print_warning "Check your inventory configuration and SSH connectivity"
        fi
    else
        print_warning "Ansible not installed locally - skipping Ansible connectivity test"
    fi
    echo ""
    
    print_header "Connectivity Test Summary"
    print_status "Basic connectivity tests completed!"
    print_status "If all tests passed, you should be able to run the deployment."
    print_status "If any tests failed, check the troubleshooting section in README.md"
}

# Show usage if help requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "Usage: $0"
    echo ""
    echo "This script tests connectivity to your bastion host and internal lab hosts."
    echo "Run this script from the ansible-playbooks directory."
    echo ""
    echo "The script will:"
    echo "  1. Check if sshpass is available"
    echo "  2. Test SSH connectivity to bastion"
    echo "  3. Check for SSH keys on bastion"
    echo "  4. Test connectivity to internal hosts through bastion"
    echo "  5. Test Ansible connectivity (if Ansible is installed)"
    exit 0
fi

# Run main function
main "$@"
