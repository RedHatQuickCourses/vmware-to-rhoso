#!/bin/bash
# RHOSO Deployment Script for Direct Bastion Execution
# This script runs directly on the bastion host to execute ansible-playbooks locally

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging configuration
LOG_DIR="logs"
LOG_FILE=""
DEPLOYMENT_START_TIME=""

# Background process management
PID_DIR="pids"
BACKGROUND_MODE=false
FOLLOW_LOGS=false

# Initialize logging
init_logging() {
    local lab_id="${1:-default}"
    local timestamp=$(date '+%Y%m%d_%H%M%S')
    
    # Create logs directory if it doesn't exist
    mkdir -p "$LOG_DIR"
    
    # Set log file name
    LOG_FILE="$LOG_DIR/deployment_${lab_id}_${timestamp}.log"
    DEPLOYMENT_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Create log file with header
    cat > "$LOG_FILE" << EOF
================================================================================
RHOSO Deployment Log - Direct Bastion Execution
================================================================================
Lab ID: $lab_id
Start Time: $DEPLOYMENT_START_TIME
Host: $(hostname)
User: $(whoami)
Working Directory: $(pwd)
Script: $0
Arguments: $*
================================================================================

EOF
    
    echo "Logging to: $LOG_FILE"
}

# Function to log message to file
log_message() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -n "$LOG_FILE" ]]; then
        echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
    fi
}

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    log_message "INFO" "$1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    log_message "WARNING" "$1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    log_message "ERROR" "$1"
}

print_header() {
    echo -e "${BLUE}[DEPLOY]${NC} $1"
    log_message "DEPLOY" "$1"
}

# Function to finalize deployment log
finalize_log() {
    local exit_code="$1"
    local phase="$2"
    local end_time=$(date '+%Y-%m-%d %H:%M:%S')
    
    if [[ -n "$LOG_FILE" ]]; then
        cat >> "$LOG_FILE" << EOF

================================================================================
Deployment Summary
================================================================================
Phase: $phase
Start Time: $DEPLOYMENT_START_TIME
End Time: $end_time
Duration: $(($(date -d "$end_time" +%s) - $(date -d "$DEPLOYMENT_START_TIME" +%s))) seconds
Exit Code: $exit_code
Status: $([ "$exit_code" -eq 0 ] && echo "SUCCESS" || echo "FAILED")
Log File: $LOG_FILE
================================================================================
EOF
        
        if [[ "$exit_code" -eq 0 ]]; then
            print_status "Deployment completed successfully. Log saved to: $LOG_FILE"
        else
            print_error "Deployment failed. Check log for details: $LOG_FILE"
        fi
    fi
}

# Function to save background process info
save_background_process() {
    local pid="$1"
    local lab_id="$2"
    local phase="$3"
    local log_file="$4"
    local start_time="$5"
    
    mkdir -p "$PID_DIR"
    
    cat > "$PID_DIR/${pid}.info" << EOF
PID=$pid
LAB_ID=$lab_id
PHASE=$phase
LOG_FILE=$log_file
START_TIME="$start_time"
STATUS=running
EOF
    
    print_status "Background deployment started with PID: $pid"
    print_status "Log file: $log_file"
    print_status "Use '$0 --status' to check progress"
    print_status "Use '$0 --stop $pid' to stop deployment"
}

# Function to show status of background deployments
show_background_status() {
    print_header "Background Deployment Status"
    
    if [[ ! -d "$PID_DIR" ]] || [[ -z "$(ls -A "$PID_DIR" 2>/dev/null)" ]]; then
        print_status "No background deployments found"
        return 0
    fi
    
    local found_active=false
    
    for pid_file in "$PID_DIR"/*.info; do
        if [[ -f "$pid_file" ]]; then
            source "$pid_file"
            local pid=$(basename "$pid_file" .info)
            
            # Check if process is still running
            if kill -0 "$pid" 2>/dev/null; then
                found_active=true
                local duration=$(($(date +%s) - $(date -d "$START_TIME" +%s 2>/dev/null || date +%s)))
                print_status "🔄 PID: $pid | Lab: $LAB_ID | Phase: $PHASE | Duration: ${duration}s"
                print_status "   Log: $LOG_FILE"
            else
                # Process finished, update status
                sed -i 's/STATUS=running/STATUS=finished/' "$pid_file"
                print_status "✅ PID: $pid | Lab: $LAB_ID | Phase: $PHASE | Status: Finished"
                print_status "   Log: $LOG_FILE"
            fi
        fi
    done
    
    if [[ "$found_active" == "false" ]]; then
        print_status "No active background deployments"
    fi
}

# Function to stop background deployment
stop_background_deployment() {
    local target_pid="$1"
    
    if [[ ! -f "$PID_DIR/${target_pid}.info" ]]; then
        print_error "No background deployment found with PID: $target_pid"
        return 1
    fi
    
    if kill -0 "$target_pid" 2>/dev/null; then
        print_status "Stopping deployment with PID: $target_pid"
        
        # Try graceful shutdown first
        kill -TERM "$target_pid" 2>/dev/null
        sleep 5
        
        # Force kill if still running
        if kill -0 "$target_pid" 2>/dev/null; then
            print_warning "Forcing termination of PID: $target_pid"
            kill -KILL "$target_pid" 2>/dev/null
        fi
        
        # Update status
        if [[ -f "$PID_DIR/${target_pid}.info" ]]; then
            sed -i 's/STATUS=running/STATUS=stopped/' "$PID_DIR/${target_pid}.info"
        fi
        
        print_status "Deployment stopped: $target_pid"
    else
        print_status "Process $target_pid is not running (already finished)"
        if [[ -f "$PID_DIR/${target_pid}.info" ]]; then
            sed -i 's/STATUS=running/STATUS=finished/' "$PID_DIR/${target_pid}.info"
        fi
    fi
}

# Function to follow logs in real-time
follow_deployment_logs() {
    local log_file="$1"
    local pid="$2"
    
    print_header "Following deployment logs (PID: $pid)"
    print_status "Log file: $log_file"
    print_status "Press Ctrl+C to stop following (deployment will continue in background)"
    echo ""
    
    # Wait for log file to be created
    local wait_count=0
    while [[ ! -f "$log_file" ]] && [[ $wait_count -lt 30 ]]; do
        sleep 1
        ((wait_count++))
    done
    
    if [[ -f "$log_file" ]]; then
        tail -f "$log_file" &
        local tail_pid=$!
        
        # Monitor the deployment process
        while kill -0 "$pid" 2>/dev/null; do
            sleep 2
        done
        
        # Kill the tail process when deployment finishes
        kill "$tail_pid" 2>/dev/null
        
        print_header "Deployment finished (PID: $pid)"
        print_status "Final log available at: $log_file"
    else
        print_error "Log file not found: $log_file"
    fi
}

# Function to cleanup old PID files
cleanup_old_pids() {
    if [[ -d "$PID_DIR" ]]; then
        for pid_file in "$PID_DIR"/*.info; do
            if [[ -f "$pid_file" ]]; then
                local pid=$(basename "$pid_file" .info)
                if ! kill -0 "$pid" 2>/dev/null; then
                    # Process is dead, mark as finished
                    sed -i 's/STATUS=running/STATUS=finished/' "$pid_file" 2>/dev/null
                fi
            fi
        done
    fi
}

# Function to check for deployment conflicts
check_deployment_conflicts() {
    local current_lab_id="$1"
    local current_phase="$2"
    
    if [[ ! -d "$PID_DIR" ]]; then
        return 0  # No PIDs directory, no conflicts
    fi
    
    local conflicting_deployments=()
    
    for pid_file in "$PID_DIR"/*.info; do
        if [[ -f "$pid_file" ]]; then
            source "$pid_file"
            local pid=$(basename "$pid_file" .info)
            
            # Check if process is still running
            if kill -0 "$pid" 2>/dev/null; then
                # Check for conflicts
                if [[ "$LAB_ID" == "$current_lab_id" ]]; then
                    # Same lab - check for phase conflicts
                    case "$current_phase" in
                        "full")
                            # Full deployment conflicts with any other deployment
                            conflicting_deployments+=("PID $pid: $LAB_ID ($PHASE)")
                            ;;
                        *)
                            # Specific phase conflicts with full deployment or same phase
                            if [[ "$PHASE" == "full" || "$PHASE" == "$current_phase" ]]; then
                                conflicting_deployments+=("PID $pid: $LAB_ID ($PHASE)")
                            fi
                            ;;
                    esac
                fi
            fi
        fi
    done
    
    if [[ ${#conflicting_deployments[@]} -gt 0 ]]; then
        print_warning "⚠️  Potential deployment conflicts detected:"
        for conflict in "${conflicting_deployments[@]}"; do
            print_warning "   $conflict"
        done
        echo ""
        print_warning "Running multiple deployments on the same lab simultaneously may cause:"
        print_warning "• Resource conflicts in OpenShift"
        print_warning "• File system conflicts on bastion"
        print_warning "• Inconsistent deployment state"
        echo ""
        
        if [[ "$BACKGROUND_MODE" == "true" ]]; then
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                print_status "Deployment cancelled by user"
                exit 0
            fi
        else
            print_status "Consider using --status to check running deployments"
            print_status "Use --stop PID to stop conflicting deployments if needed"
        fi
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS] [PHASE]"
    echo ""
    echo "This script deploys RHOSO directly from the bastion host."
    echo ""
    echo "Options:"
    echo "  -h, --help              Show this help message"
    echo "  -c, --check-inventory   Check inventory configuration"
    echo "  -d, --dry-run          Run in check mode (no changes)"
    echo "  -v, --verbose          Enable verbose output"
    echo "  --debug-credentials    Debug credential loading and injection"
    echo "  -b, --background       Run deployment in background"
    echo "  --follow-logs          Follow deployment logs in real-time (implies --background)"
    echo "  --status               Show status of background deployments"
    echo "  --stop PID             Stop a background deployment by PID"
    echo "  --credentials FILE     Use external credentials file (YAML format)"
    echo "  --inventory FILE       Use custom inventory file (default: inventory/hosts-bastion.yml)"
    echo ""
    echo "Available phases:"
    echo "  prerequisites  - Install required operators (NMState, MetalLB)"
    echo "  install-operators - Install OpenStack operators"
    echo "  security      - Configure secrets and security"
    echo "  nfs-server    - Configure NFS server"
    echo "  network-isolation - Set up network isolation"
    echo "  control-plane - Deploy OpenStack control plane"
    echo "  data-plane    - Configure compute nodes"
    echo "  validation    - Verify deployment"
    echo "  showroom      - Configure Showroom (optional)"
    echo "  full          - Run complete deployment (default)"
    echo "  optional      - Enable optional services (Heat, Swift)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Run full deployment"
    echo "  $0 full                               # Run full deployment"
    echo "  $0 -c                                 # Check inventory configuration"
    echo "  $0 -d control-plane                   # Dry run of control plane deployment"
    echo "  $0 -v prerequisites                   # Verbose prerequisites installation"
    echo "  $0 showroom                           # Configure Showroom only"
    echo "  $0 -b full                            # Run full deployment in background"
    echo "  $0 --follow-logs install-operators    # Run and follow logs in real-time"
    echo "  $0 --status                           # Show status of background deployments"
    echo "  $0 --stop 12345                       # Stop background deployment with PID 12345"
    echo "  $0 --credentials ../my_credentials.yml full  # Use external credentials file"
    echo "  $0 --inventory ../lab1/hosts-bastion.yml full      # Use custom inventory file"
    echo ""
    echo "Credentials File Format:"
    echo "  Create a YAML file with your Red Hat credentials:"
    echo "  registry_username: \"12345678|myserviceaccount\""
    echo "  registry_password: \"eyJhbGciOiJSUzUxMiJ9...\""
    echo "  rhc_username: \"your-rh-username@email.com\""
    echo "  rhc_password: \"YourRHPassword123\""
}

# Function to parse credentials file
parse_credentials_file() {
    local credentials_file="$1"
    
    if [[ ! -f "$credentials_file" ]]; then
        print_error "Credentials file not found: $credentials_file"
        exit 1
    fi
    
    print_status "Loading credentials from: $credentials_file"
    
    # Parse YAML credentials file and export as environment variables
    # This uses a simple grep-based approach to avoid requiring yq or python
    export CRED_REGISTRY_USERNAME=$(grep "^registry_username:" "$credentials_file" | sed 's/registry_username: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
    export CRED_REGISTRY_PASSWORD=$(grep "^registry_password:" "$credentials_file" | sed 's/registry_password: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
    export CRED_RHC_USERNAME=$(grep "^rhc_username:" "$credentials_file" | sed 's/rhc_username: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
    export CRED_RHC_PASSWORD=$(grep "^rhc_password:" "$credentials_file" | sed 's/rhc_password: *["\x27]\?\([^"\x27]*\)["\x27]\?/\1/')
    
    # Validate that required credentials were found
    if [[ -z "$CRED_REGISTRY_USERNAME" || -z "$CRED_REGISTRY_PASSWORD" || -z "$CRED_RHC_USERNAME" || -z "$CRED_RHC_PASSWORD" ]]; then
        print_error "Missing required credentials in file: $credentials_file"
        echo "Required fields: registry_username, registry_password, rhc_username, rhc_password"
        exit 1
    fi
    
    print_status "Credentials loaded successfully"
    print_status "Registry username: ${CRED_REGISTRY_USERNAME%%|*}|***"  # Show only the first part before |
    print_status "RHC username: $CRED_RHC_USERNAME"
}

# Function to install required system packages
install_system_packages() {
    print_status "Checking and installing required system packages..."
    
    local packages_to_install=()
    
    # Check if ansible is installed
    if ! command -v ansible &> /dev/null; then
        print_status "Ansible not found, will install it..."
        packages_to_install+=("ansible-core" "python3-pip" "python3-kubernetes" "python3-jmespath" "python3-yaml" "python3-requests" "sshpass")
    fi
    
    # Check if Python 3.11 is available
    if ! command -v python3.11 &> /dev/null; then
        print_status "Python 3.11 not found, will install it..."
        packages_to_install+=("python3.11" "python3.11-pip")
    fi
    
    # Check if pip for Python 3.11 is available
    if command -v python3.11 &> /dev/null && ! python3.11 -m pip --version >/dev/null 2>&1; then
        print_status "Python 3.11 pip not found, will install it..."
        packages_to_install+=("python3.11-pip")
    fi
    
    # Install packages if needed
    if [[ ${#packages_to_install[@]} -gt 0 ]]; then
        print_status "Installing system packages: ${packages_to_install[*]}"
        
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y "${packages_to_install[@]}" || {
                print_error "Failed to install some packages via dnf. Please install manually:"
                printf '  sudo dnf install -y %s\n' "${packages_to_install[@]}"
                exit 1
            }
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y "${packages_to_install[@]}" || {
                print_error "Failed to install some packages via yum. Please install manually:"
                printf '  sudo yum install -y %s\n' "${packages_to_install[@]}"
                exit 1
            }
        else
            print_error "Neither dnf nor yum found. Please install packages manually:"
            printf '  %s\n' "${packages_to_install[@]}"
            exit 1
        fi
        
        print_status "System packages installed successfully"
    else
        print_status "All required system packages are already installed"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    # Install required system packages first
    install_system_packages
    
    # Check ansible version
    local ansible_version=$(ansible --version | head -1 | cut -d' ' -f3)
    print_status "Found Ansible version: $ansible_version"
    
    # Check if oc (OpenShift CLI) is available
    if ! command -v oc &> /dev/null; then
        print_warning "OpenShift CLI (oc) not found in PATH. Some operations may fail."
        print_status "Attempting to use oc from common locations..."
        
        # Try common locations for oc
        if [[ -f "/usr/local/bin/oc" ]]; then
            export PATH="/usr/local/bin:$PATH"
            print_status "Found oc at /usr/local/bin/oc"
        elif [[ -f "/home/$(whoami)/bin/oc" ]]; then
            export PATH="/home/$(whoami)/bin:$PATH"
            print_status "Found oc at /home/$(whoami)/bin/oc"
        else
            print_warning "oc not found. Please ensure OpenShift CLI is installed and in PATH."
        fi
    fi
    
    # Check if inventory file exists
    if [[ ! -f "$inventory_file" ]]; then
        print_error "Inventory file $inventory_file not found."
        exit 1
    fi
    
    print_status "Prerequisites check passed!"
}

# Function to check inventory configuration
check_inventory() {
    local inventory_file="${1:-inventory/hosts-bastion.yml}"
    print_header "Checking inventory configuration..."
    
    # Check for changeme values, but skip credential fields if they're provided via file
    local has_changeme=false
    
    if grep -q "changeme" "$inventory_file"; then
        # Check if the changeme values are in credential fields and we have credentials from file
        if [[ -n "${CRED_REGISTRY_USERNAME:-}" ]]; then
            # We have credentials from file, so check only non-credential changeme values
            if grep -v -E "(registry_username|registry_password|rhc_username|rhc_password)" "$inventory_file" | grep -q "changeme"; then
                has_changeme=true
            fi
        else
            has_changeme=true
        fi
    fi
    
    if [[ "$has_changeme" == "true" ]]; then
        print_error "Inventory file contains default 'changeme' values."
        echo ""
        echo "Please update the following in $inventory_file:"
        echo "  - lab_guid: Your lab GUID"
        if [[ -z "${CRED_REGISTRY_USERNAME:-}" ]]; then
        echo "  - registry_username: Red Hat registry service account username"
        echo "  - registry_password: Red Hat registry service account password/token"
        echo "  - rhc_username: Red Hat Customer Portal username"
        echo "  - rhc_password: Red Hat Customer Portal password"
            echo ""
            echo "Alternatively, use --credentials FILE to provide credentials externally."
        fi
        echo ""
        return 1
    fi
    
    print_status "Inventory configuration looks good!"
    return 0
}

# Function to install required collections
install_collections() {
    print_status "Installing required Ansible collections..."
    ansible-galaxy collection install -r requirements.yml --force
}

# Function to setup environment
setup_environment() {
    print_status "Setting up deployment environment..."
    
    # Ensure additional system packages that might be needed
    local additional_packages=()
    
    # Check for git (sometimes needed for ansible collections)
    if ! command -v git &> /dev/null; then
        additional_packages+=("git")
    fi
    
    # Install additional packages if needed
    if [[ ${#additional_packages[@]} -gt 0 ]]; then
        print_status "Installing additional packages: ${additional_packages[*]}"
        if command -v dnf >/dev/null 2>&1; then
            sudo dnf install -y "${additional_packages[@]}" >/dev/null 2>&1 || print_warning "Failed to install some additional packages via dnf"
        elif command -v yum >/dev/null 2>&1; then
            sudo yum install -y "${additional_packages[@]}" >/dev/null 2>&1 || print_warning "Failed to install some additional packages via yum"
        fi
    fi
    
    # Ensure required Python libraries are available
    print_status "Checking Python dependencies..."
    
    # Install for default python3
    python3 -m pip install --user --upgrade pip >/dev/null 2>&1 || true
    python3 -m pip install --user kubernetes openshift jmespath pyyaml requests urllib3 >/dev/null 2>&1 || true
    
    # Also ensure libraries are available for Python 3.11 (which Ansible uses)
    if command -v python3.11 &> /dev/null; then
        print_status "Installing Python libraries for Python 3.11..."
        
        # Ensure pip is available for Python 3.11
        if ! python3.11 -m pip --version >/dev/null 2>&1; then
            print_status "Installing pip for Python 3.11..."
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y python3.11-pip >/dev/null 2>&1 || print_warning "Failed to install python3.11-pip via dnf"
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y python3.11-pip >/dev/null 2>&1 || print_warning "Failed to install python3.11-pip via yum"
            fi
        fi
        
        # Install Python libraries for 3.11
        python3.11 -m pip install --user --upgrade pip >/dev/null 2>&1 || true
        python3.11 -m pip install --user kubernetes openshift jmespath pyyaml requests urllib3 >/dev/null 2>&1 || {
            print_warning "Failed to install some Python libraries for Python 3.11"
            print_status "Attempting to install via system packages as fallback..."
            if command -v dnf >/dev/null 2>&1; then
                sudo dnf install -y python3.11-kubernetes python3.11-jmespath python3.11-yaml python3.11-requests >/dev/null 2>&1 || true
            elif command -v yum >/dev/null 2>&1; then
                sudo yum install -y python3.11-kubernetes python3.11-jmespath python3.11-yaml python3.11-requests >/dev/null 2>&1 || true
            fi
        }
    fi
    
    print_status "Environment setup completed"
}

# Function to run deployment
run_deployment() {
    local phase="$1"
    local dry_run="$2"
    local verbose="$3"
    local inventory_file="${4:-inventory/hosts-bastion.yml}"
    
    # Setup environment
    setup_environment
    
    # Create temporary inventory and apply fixes
    local temp_inventory="temp_inventory_$(date +%s).yml"
    cp "$inventory_file" "$temp_inventory"
    
    # Fix Python interpreter to use Python 3.11 (where kubernetes library is installed)
    if grep -q "ansible_python_interpreter.*ansible_playbook_python" "$temp_inventory"; then
        print_status "Fixing Python interpreter to use Python 3.11..."
        sed -i 's/ansible_python_interpreter: "{{ ansible_playbook_python }}"/ansible_python_interpreter: "\/usr\/bin\/python3.11"/' "$temp_inventory"
    fi
    
    # Note: We no longer automatically set Python interpreter for remote hosts
    # Since we replaced community.general.nmcli with command modules, Python 3.7+ is no longer required
    # Ansible will auto-detect Python 2.7+ or 3.x on remote hosts
    # Users can optionally set ansible_python_interpreter in their inventory if needed
    # 
    # The following code block is commented out to prevent automatic Python interpreter injection:
    # (This was causing issues when Python 3.11 didn't exist on remote hosts)
    #
    # local python_interpreter="/usr/bin/python3.11"
    # local needs_python_fix=false
    # 
    # if [[ "$needs_python_fix" == "true" ]]; then
    #     print_status "Setting Python interpreter for remote hosts..."
    #     # Note: This is no longer needed since we use command modules instead of community.general.nmcli
    
    # If credentials were provided via file, inject them into the inventory
    if [[ -n "${CRED_REGISTRY_USERNAME:-}" ]]; then
        print_status "Injecting credentials from file into inventory..."
        
        # Update registry credentials (handle various formats)
        sed -i "s/registry_username: *[\"']*[^\"']*[\"']*/registry_username: \"$CRED_REGISTRY_USERNAME\"/" "$temp_inventory"
        sed -i "s/registry_password: *[\"']*[^\"']*[\"']*/registry_password: \"$CRED_REGISTRY_PASSWORD\"/" "$temp_inventory"
        
        # Update RHC credentials (handle various formats)
        sed -i "s/rhc_username: *[\"']*[^\"']*[\"']*/rhc_username: \"$CRED_RHC_USERNAME\"/" "$temp_inventory"
        sed -i "s/rhc_password: *[\"']*[^\"']*[\"']*/rhc_password: \"$CRED_RHC_PASSWORD\"/" "$temp_inventory"
        
        print_status "Credentials injected into temporary inventory"
        
        # Debug: Show what credentials were injected (without showing actual passwords)
        print_status "Registry username: ${CRED_REGISTRY_USERNAME%%|*}|***"
        print_status "RHC username: $CRED_RHC_USERNAME"
        
        # Verify injection worked
        if grep -q "registry_username: \"$CRED_REGISTRY_USERNAME\"" "$temp_inventory"; then
            print_status "✓ Registry username injection verified"
        else
            print_warning "⚠ Registry username injection may have failed"
        fi
    fi
    
    inventory_file="$temp_inventory"
    print_status "Using temporary inventory: $inventory_file"
    
    # Debug: Check if credentials are properly set in the inventory for troubleshooting
    if [[ "$verbose" == "true" ]]; then
        print_status "=== Credential Debug Information ==="
        if grep -q "registry_username:" "$inventory_file"; then
            local reg_user=$(grep "registry_username:" "$inventory_file" | sed 's/.*registry_username: *["\x27]\?\([^"\x27]*\)["\x27]\?.*/\1/')
            if [[ -n "$reg_user" && "$reg_user" != "" ]]; then
                print_status "✓ Registry username is set: ${reg_user%%|*}|***"
            else
                print_warning "⚠ Registry username is empty or not set"
            fi
        fi
        
        if grep -q "registry_password:" "$inventory_file"; then
            local reg_pass=$(grep "registry_password:" "$inventory_file" | sed 's/.*registry_password: *["\x27]\?\([^"\x27]*\)["\x27]\?.*/\1/')
            if [[ -n "$reg_pass" && "$reg_pass" != "" ]]; then
                print_status "✓ Registry password is set (length: ${#reg_pass})"
            else
                print_warning "⚠ Registry password is empty or not set"
            fi
        fi
        print_status "=== End Credential Debug ==="
    fi
    
    # Prepare ansible options
    local ansible_opts=""
    if [[ "$dry_run" == "true" ]]; then
        ansible_opts="--check --diff"
        print_warning "Running in DRY RUN mode - no changes will be made"
    fi
    
    if [[ "$verbose" == "true" ]]; then
        ansible_opts="$ansible_opts -vv"
    fi
    
    # Add inventory file to ansible options
    ansible_opts="$ansible_opts -i $inventory_file"
    
    # Execute deployment phase
    print_header "Running $phase phase directly on bastion..."
    local exit_code=0
    
    case "$phase" in
        'prerequisites')
            print_status 'Running prerequisites phase...'
            ansible-playbook site.yml --tags prerequisites $ansible_opts
            exit_code=$?
            ;;
        'install-operators')
            print_status 'Installing OpenStack operators...'
            ansible-playbook site.yml --tags install-operators $ansible_opts
            exit_code=$?
            ;;
        'security')
            print_status 'Configuring security...'
            ansible-playbook site.yml --tags security $ansible_opts
            exit_code=$?
            ;;
        'nfs-server')
            print_status 'Configuring NFS server...'
            ansible-playbook site.yml --tags nfs-server $ansible_opts
            exit_code=$?
            ;;
        'network-isolation')
            print_status 'Setting up network isolation...'
            ansible-playbook site.yml --tags network-isolation $ansible_opts
            exit_code=$?
            ;;
        'control-plane')
            print_status 'Deploying control plane...'
            ansible-playbook site.yml --tags control-plane $ansible_opts
            exit_code=$?
            ;;
        'data-plane')
            print_status 'Configuring data plane...'
            ansible-playbook site.yml --tags data-plane $ansible_opts
            exit_code=$?
            ;;
        'validation')
            print_status 'Running validation...'
            ansible-playbook site.yml --tags validation $ansible_opts
            exit_code=$?
            ;;
        'showroom')
            print_status 'Configuring Showroom...'
            ansible-playbook site.yml --tags showroom $ansible_opts
            exit_code=$?
            ;;
        'full')
            print_status 'Running complete deployment...'
            ansible-playbook site.yml $ansible_opts
            exit_code=$?
            ;;
        'optional')
            print_status 'Enabling optional services (Heat, Swift)...'
            ansible-playbook optional-services.yml $ansible_opts
            exit_code=$?
            ;;
        *)
            print_error "Unknown phase: $phase"
            exit_code=1
            ;;
    esac
    
    # Cleanup temporary inventory file if created
    if [[ -f "$inventory_file" ]] && [[ "$inventory_file" == temp_inventory_* ]]; then
        rm -f "$inventory_file"
        print_status "Cleaned up temporary inventory file"
    fi
    
    return $exit_code
}

# Main execution
main() {
    local phase="full"
    local check_only="false"
    local dry_run="false"
    local verbose="false"
    local credentials_file=""
    local inventory_file="inventory/hosts-bastion.yml"
    local lab_id="default"
    local show_status="false"
    local stop_pid=""
    local debug_credentials="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -c|--check-inventory)
                check_only="true"
                shift
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -v|--verbose)
                verbose="true"
                shift
                ;;
            --debug-credentials)
                debug_credentials="true"
                verbose="true"  # Enable verbose mode for credential debugging
                shift
                ;;
            -b|--background)
                BACKGROUND_MODE=true
                shift
                ;;
            --follow-logs)
                FOLLOW_LOGS=true
                BACKGROUND_MODE=true
                shift
                ;;
            --status)
                show_status="true"
                shift
                ;;
            --stop)
                if [[ -n "${2:-}" ]]; then
                    stop_pid="$2"
                    shift 2
                else
                    print_error "--stop requires a PID"
                    show_usage
                    exit 1
                fi
                ;;
            --credentials)
                if [[ -n "${2:-}" ]]; then
                    credentials_file="$2"
                    shift 2
                else
                    print_error "--credentials requires a file path"
                    show_usage
                    exit 1
                fi
                ;;
            --inventory)
                if [[ -n "${2:-}" ]]; then
                    inventory_file="$2"
                    shift 2
                else
                    print_error "--inventory requires a file path"
                    show_usage
                    exit 1
                fi
                ;;
            -*)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                phase="$1"
                shift
                ;;
        esac
    done
    
    # Extract lab_id from inventory file for logging
    if [[ -f "$inventory_file" ]]; then
        lab_id=$(grep "lab_guid:" "$inventory_file" | head -1 | sed 's/.*lab_guid: *"\([^"]*\)".*/\1/' 2>/dev/null || echo "default")
        [[ "$lab_id" == "changeme" || -z "$lab_id" ]] && lab_id="default"
    fi
    
    # Handle special commands first
    cleanup_old_pids
    
    if [[ "$show_status" == "true" ]]; then
        show_background_status
        exit 0
    fi
    
    if [[ -n "$stop_pid" ]]; then
        stop_background_deployment "$stop_pid"
        exit $?
    fi
    
    # Check for conflicting deployments
    check_deployment_conflicts "$lab_id" "$phase"
    
    # Initialize logging
    init_logging "$lab_id" "$@"
    
    print_header "RHOSO Deployment from Bastion - Phase: $phase"
    print_status "Timestamp: $(date)"
    print_status "Working directory: $(pwd)"
    print_status "Lab ID: $lab_id"
    print_status "Hostname: $(hostname)"
    
    if [[ "$BACKGROUND_MODE" == "true" ]]; then
        print_status "Background mode: enabled"
    fi
    
    # Parse credentials file if provided
    if [[ -n "$credentials_file" ]]; then
        parse_credentials_file "$credentials_file"
        
        # Debug credentials if requested
        if [[ "$debug_credentials" == "true" ]]; then
            print_header "=== CREDENTIAL DEBUG MODE ==="
            print_status "Credentials file: $credentials_file"
            print_status "File contents (passwords masked):"
            sed 's/password: *["\x27]\?\([^"\x27]*\)["\x27]\?/password: "***"/' "$credentials_file" | while read line; do
                print_status "  $line"
            done
            print_status "Parsed environment variables:"
            print_status "  CRED_REGISTRY_USERNAME: ${CRED_REGISTRY_USERNAME%%|*}|***"
            print_status "  CRED_REGISTRY_PASSWORD: $([ -n "$CRED_REGISTRY_PASSWORD" ] && echo "SET (${#CRED_REGISTRY_PASSWORD} chars)" || echo "EMPTY")"
            print_status "  CRED_RHC_USERNAME: $CRED_RHC_USERNAME"
            print_status "  CRED_RHC_PASSWORD: $([ -n "$CRED_RHC_PASSWORD" ] && echo "SET (${#CRED_RHC_PASSWORD} chars)" || echo "EMPTY")"
            print_header "=== END CREDENTIAL DEBUG ==="
        fi
    fi
    
    check_prerequisites
    
    # Set up error handling for logging
    set +e
    local exit_code=0
    
    if [[ "$check_only" == "true" ]]; then
        check_inventory "$inventory_file"
        exit_code=$?
        finalize_log "$exit_code" "check-inventory"
        exit $exit_code
    fi
    
    if ! check_inventory "$inventory_file"; then
        print_error "Inventory check failed. Please fix the configuration and try again."
        finalize_log 1 "$phase"
        exit 1
    fi
    
    install_collections
    exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        print_error "Failed to install Ansible collections"
        finalize_log $exit_code "$phase"
        exit $exit_code
    fi
    
    # Handle background deployment
    if [[ "$BACKGROUND_MODE" == "true" ]]; then
        # Run deployment in background
        (
            run_deployment "$phase" "$dry_run" "$verbose" "$inventory_file"
            local bg_exit_code=$?
            finalize_log "$bg_exit_code" "$phase"
            exit $bg_exit_code
        ) &
        
        local bg_pid=$!
        save_background_process "$bg_pid" "$lab_id" "$phase" "$LOG_FILE" "$DEPLOYMENT_START_TIME"
        
        if [[ "$FOLLOW_LOGS" == "true" ]]; then
            follow_deployment_logs "$LOG_FILE" "$bg_pid"
        else
            print_status "Deployment running in background with PID: $bg_pid"
            print_status "Use '$0 --status' to check progress"
            print_status "Use 'tail -f $LOG_FILE' to follow logs"
        fi
        
        exit 0
    else
        # Run deployment in foreground (original behavior)
        run_deployment "$phase" "$dry_run" "$verbose" "$inventory_file"
        exit_code=$?
        
        if [[ $exit_code -eq 0 ]]; then
            if [[ "$dry_run" == "true" ]]; then
                print_status "Dry run completed successfully!"
                print_status "Run without -d/--dry-run to perform actual deployment."
            else
                print_status "Deployment phase '$phase' completed successfully!"
                print_status "Check the README.md for verification commands and troubleshooting."
            fi
        fi
        
        finalize_log "$exit_code" "$phase"
        exit $exit_code
    fi
}

# Run main function with all arguments
main "$@"
