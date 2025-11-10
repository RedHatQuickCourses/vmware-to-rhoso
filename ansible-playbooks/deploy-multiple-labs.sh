#!/bin/bash

# Multi-Lab RHOSO Deployment Script
# This script deploys multiple RHOSO labs using existing complete inventory files
# It automatically discovers available labs and supports both sequential and parallel execution

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_status() { echo -e "${GREEN}[STATUS]${NC} $1"; }

# Default values
CREDENTIALS_FILE="credentials.yml"
MAX_PARALLEL=1  # Conservative default to avoid resource conflicts
LABS_FILE=""
DRY_RUN=false
PHASE="full"  # Default to full deployment

# Usage function
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy multiple RHOSO labs in parallel using existing complete inventory files.

Optional Arguments:
  --labs <file>         Path to the labs configuration file (not used, for compatibility)
  --credentials <file>  Path to the credentials YAML file (default: credentials.yml)
  --max-parallel <num>  Maximum number of parallel deployments (default: 1)
  --phase <phase>       Deployment phase to run (default: full)
  --dry-run            Show what would be deployed without actually deploying
  --help               Show this help message

Available phases:
  prerequisites  - Install required operators (NMState, MetalLB)
  install-operators - Install OpenStack operators
  security      - Configure secrets and security
  nfs-server    - Configure NFS server
  network-isolation - Set up network isolation
  control-plane - Deploy OpenStack control plane
  data-plane    - Configure compute nodes
  validation    - Verify deployment
  full          - Run complete deployment (default)
  optional      - Enable optional services (Heat, Swift)

Examples:
  $0                                    # Deploy all available labs (full deployment)
  $0 --credentials my_credentials.yml   # Use custom credentials
  $0 --max-parallel 3                  # Deploy up to 3 labs in parallel
  $0 --dry-run                         # Show what would be deployed

Note: This script automatically discovers available inventory files from inventory/hosts-*.yml
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --labs)
            LABS_FILE="$2"
            shift 2
            ;;
        --credentials)
            CREDENTIALS_FILE="$2"
            shift 2
            ;;
        --max-parallel)
            MAX_PARALLEL="$2"
            shift 2
            ;;
        --phase)
            PHASE="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --help)
            usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate credentials file exists
if [[ ! -f "$CREDENTIALS_FILE" ]]; then
    print_error "Credentials file not found: $CREDENTIALS_FILE"
    exit 1
fi

print_status "Multi-Lab RHOSO Deployment Script"
print_info "Credentials file: $CREDENTIALS_FILE"
print_info "Max parallel deployments: $MAX_PARALLEL"
print_info "Deployment phase: $PHASE"
print_info "Dry run: $DRY_RUN"

# Dynamically discover available inventory files
declare -A LABS=()

print_status "Discovering available inventory files..."
for inventory_file in inventory/hosts-*.yml; do
    if [[ -f "$inventory_file" ]]; then
        # Extract lab ID from filename (hosts-XXXXX.yml -> prod-XXXXX)
        lab_guid=$(basename "$inventory_file" .yml | sed 's/hosts-//')
        lab_id="prod-${lab_guid}"
        LABS["$lab_id"]="$inventory_file"
        print_info "Found lab: $lab_id -> $inventory_file"
    fi
done

if [[ ${#LABS[@]} -eq 0 ]]; then
    print_error "No inventory files found in inventory/hosts-*.yml"
    exit 1
fi

print_success "Configured ${#LABS[@]} labs using existing inventory files"

# List the labs found
print_info "Labs to be deployed:"
for lab_id in "${!LABS[@]}"; do
    inventory_file="${LABS[$lab_id]}"
    print_info "  - $lab_id (${inventory_file})"
done

if [[ "$DRY_RUN" == "true" ]]; then
    print_warning "Dry run mode - no actual deployments will be performed"
    
    # Show what would be deployed
    for lab_id in "${!LABS[@]}"; do
        inventory_file="${LABS[$lab_id]}"
        print_info "Would deploy lab: $lab_id using $inventory_file (phase: $PHASE)"
        
        # Extract some info from inventory
        if [[ -f "$inventory_file" ]]; then
            bastion_host=$(grep "bastion_hostname:" "$inventory_file" | head -1 | sed 's/.*bastion_hostname: *"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown")
            bastion_port=$(grep "bastion_port:" "$inventory_file" | head -1 | sed 's/.*bastion_port: *"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown")
            lab_guid=$(grep "lab_guid:" "$inventory_file" | head -1 | sed 's/.*lab_guid: *"\([^"]*\)".*/\1/' 2>/dev/null || echo "unknown")
            print_info "  Bastion: $bastion_host:$bastion_port"
            print_info "  GUID: $lab_guid"
        fi
    done
    
    exit 0
fi

# Pre-install Ansible collections to avoid conflicts during parallel execution
print_status "Pre-installing Ansible collections..."
if ansible-galaxy collection install -r requirements.yml --force > /tmp/ansible-collections-install.log 2>&1; then
    print_success "Ansible collections installed successfully"
else
    print_error "Failed to install Ansible collections. Check /tmp/ansible-collections-install.log"
    exit 1
fi

# Deploy function that runs in background
deploy_single_lab() {
    local lab_id="$1"
    local inventory_file="$2"
    
    print_info "[$lab_id] Starting deployment using inventory: $inventory_file"
    
    # Create temporary inventory with credentials
    local temp_inventory="temp_inventory_${lab_id}.yml"
    cp "$inventory_file" "$temp_inventory"
    
    # Inject credentials if available
    if [[ -f "$CREDENTIALS_FILE" ]]; then
        local registry_username=$(grep "^registry_username:" "$CREDENTIALS_FILE" | sed 's/registry_username: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
        local registry_password=$(grep "^registry_password:" "$CREDENTIALS_FILE" | sed 's/registry_password: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
        local rhc_username=$(grep "^rhc_username:" "$CREDENTIALS_FILE" | sed 's/rhc_username: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
        local rhc_password=$(grep "^rhc_password:" "$CREDENTIALS_FILE" | sed 's/rhc_password: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
        
        if [[ -n "$registry_username" ]]; then
            sed -i "s/registry_username: \"\"/registry_username: \"$registry_username\"/" "$temp_inventory"
        fi
        if [[ -n "$registry_password" ]]; then
            sed -i "s/registry_password: \"\"/registry_password: \"$registry_password\"/" "$temp_inventory"
        fi
        if [[ -n "$rhc_username" ]]; then
            sed -i "s/rhc_username: \"\"/rhc_username: \"$rhc_username\"/" "$temp_inventory"
        fi
        if [[ -n "$rhc_password" ]]; then
            sed -i "s/rhc_password: \"\"/rhc_password: \"$rhc_password\"/" "$temp_inventory"
        fi
    fi
    
    # Run deployment
    local log_file="deployment_${lab_id}.log"
    if ./deploy-via-jumphost.sh --inventory "$temp_inventory" --credentials "$CREDENTIALS_FILE" "$PHASE" > "$log_file" 2>&1; then
        print_success "[$lab_id] Deployment completed successfully"
        echo "SUCCESS" > "status_${lab_id}.txt"
    else
        print_error "[$lab_id] Deployment failed - check $log_file"
        echo "FAILED" > "status_${lab_id}.txt"
    fi
    
    # Cleanup
    rm -f "$temp_inventory"
}

# Start deployments in parallel
print_status "Starting parallel deployments..."
declare -a bg_pids=()
active_jobs=0

for lab_id in "${!LABS[@]}"; do
    inventory_file="${LABS[$lab_id]}"
    
    # Verify inventory file exists
    if [[ ! -f "$inventory_file" ]]; then
        print_error "Inventory file not found: $inventory_file"
        continue
    fi
    
    print_info "Processing lab: $lab_id (active_jobs=$active_jobs)"
    
    # Wait if we have reached max parallel limit
    while [[ "$active_jobs" -ge "$MAX_PARALLEL" ]]; do
        print_info "Waiting for job to complete (active_jobs=$active_jobs >= MAX_PARALLEL=$MAX_PARALLEL)"
        
        # Check if any background job has finished
        for i in "${!bg_pids[@]}"; do
            pid="${bg_pids[$i]}"
            if ! kill -0 "$pid" 2>/dev/null; then
                # Job finished, remove from array
                unset bg_pids[$i]
                ((active_jobs--))
                print_info "Job PID $pid completed, active_jobs now = $active_jobs"
                break
            fi
        done
        
        sleep 2
    done
    
    # Start deployment in background
    print_info "Starting deployment for lab $lab_id using inventory: $inventory_file"
    deploy_single_lab "$lab_id" "$inventory_file" &
    
    bg_pid=$!
    bg_pids+=("$bg_pid")
    ((active_jobs++))
    
    print_info "Started deployment for lab $lab_id (PID: $bg_pid), active_jobs = $active_jobs"
    
    # Longer delay between deployments to avoid resource conflicts
    sleep 5
done

print_info "All deployments launched. PIDs: ${bg_pids[*]}"

# Wait for all deployments to complete
print_status "Waiting for all deployments to complete..."

while [[ ${#bg_pids[@]} -gt 0 ]]; do
    for i in "${!bg_pids[@]}"; do
        pid="${bg_pids[$i]}"
        if ! kill -0 "$pid" 2>/dev/null; then
            # Job finished
            unset bg_pids[$i]
            print_info "Deployment PID $pid finished"
        fi
    done
    
    if [[ ${#bg_pids[@]} -gt 0 ]]; then
        print_info "Still waiting for ${#bg_pids[@]} deployments: ${bg_pids[*]}"
        sleep 5
    fi
done

# Summary
print_status "Deployment Summary"
success_count=0
failure_count=0

for lab_id in "${!LABS[@]}"; do
    if [[ -f "status_${lab_id}.txt" ]]; then
        status=$(cat "status_${lab_id}.txt")
        if [[ "$status" == "SUCCESS" ]]; then
            ((success_count++))
            print_success "$lab_id: SUCCESS"
        else
            ((failure_count++))
            print_error "$lab_id: FAILED"
        fi
        rm -f "status_${lab_id}.txt"
    else
        print_error "$lab_id: UNKNOWN STATUS"
        ((failure_count++))
    fi
done

print_status "Final Results:"
print_success "Successful deployments: $success_count"
if [[ "$failure_count" -gt 0 ]]; then
    print_error "Failed deployments: $failure_count"
fi

print_info "Individual deployment logs:"
for lab_id in "${!LABS[@]}"; do
    if [[ -f "deployment_${lab_id}.log" ]]; then
        print_info "  - deployment_${lab_id}.log"
    fi
done

exit 0
