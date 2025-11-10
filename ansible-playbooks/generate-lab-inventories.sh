#!/bin/bash

# Lab Inventory Generator Script
# This script parses the lab configuration file and generates individual hosts-{guid}.yml files

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print functions
print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_status() {
    echo -e "${GREEN}[STATUS]${NC} $1"
}

# Usage function
usage() {
    cat << EOF
Usage: $0 <labs_config_file> [OPTIONS]

Generate individual hosts-{guid}.yml inventory files from lab configuration.

Arguments:
  <labs_config_file>    Path to the labs configuration file (e.g., my_labs_to_be_deployed)

Options:
  -o, --output-dir DIR  Output directory for inventory files (default: inventory)
  -f, --force          Overwrite existing inventory files
  -d, --dry-run        Show what would be generated without creating files
  -h, --help           Show this help message

Examples:
  $0 my_labs_to_be_deployed
  $0 my_labs_to_be_deployed --output-dir /tmp/inventories
  $0 my_labs_to_be_deployed --dry-run
  $0 my_labs_to_be_deployed --force

Output:
  Creates hosts-{guid}.yml files in the inventory directory for each lab found.
EOF
}

# Parse lab configuration file (reuse logic from deploy-multiple-labs.sh)
parse_lab_config() {
    local config_file="$1"
    local temp_dir="$2"
    local lab_count=0
    local current_lab=""
    local lab_config_file=""
    local in_data_section=false
    local skip_next_line=false

    mkdir -p "$temp_dir/lab_configs"

    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "$line" ]] && continue

        # Skip if we're supposed to skip this line (for multi-line YAML)
        if [[ "$skip_next_line" == "true" ]]; then
            skip_next_line=false
            continue
        fi

        # Check for "Data" section header
        if [[ "$line" =~ ^Data ]]; then
            in_data_section=true
            continue
        fi

        # Check for service name (lab identifier)
        if [[ "$line" =~ ^openshift-cnv\.osp-on-ocp-cnv\.([^[:space:]]+) ]]; then
            local service_suffix="${BASH_REMATCH[1]}"
            service_suffix=$(echo "$service_suffix" | sed 's/[[:space:]]*$//' | sed 's/[^a-zA-Z0-9-]//g')

            # Handle the special case where "prod:" appears in the YAML data section
            # This indicates we're in the data section for the current lab
            if [[ "$service_suffix" == "prod" ]]; then
                in_data_section=true
                continue
            fi

            # Save previous lab if exists and it's valid
            if [[ -n "$current_lab" && -n "$lab_config_file" ]]; then
                echo ")" >> "$lab_config_file"
                ((lab_count++))
                print_info "Completed parsing lab: $current_lab" >&2
            fi

            # Start new lab
            current_lab="$service_suffix"
            lab_config_file="$temp_dir/lab_configs/lab_${current_lab}.conf"
            in_data_section=false

            print_status "Found lab: $current_lab" >&2
            echo "LAB_ID=\"$current_lab\"" > "$lab_config_file"
            echo "declare -A LAB_CONFIG=(" >> "$lab_config_file"
            continue
        fi

        # Parse SSH connection info from text
        if [[ "$line" =~ ssh\ lab-user@([^[:space:]]+)\ -p\ ([0-9]+) ]]; then
            local bastion_host="${BASH_REMATCH[1]}"
            local bastion_port="${BASH_REMATCH[2]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"bastion_hostname\"]=\"$bastion_host\"" >> "$lab_config_file"
                echo "  [\"bastion_port\"]=\"$bastion_port\"" >> "$lab_config_file"
                echo "  [\"bastion_user\"]=\"lab-user\"" >> "$lab_config_file"
                print_info "  SSH: lab-user@$bastion_host:$bastion_port" >&2
            fi
            continue
        fi

        # Parse SSH password
        if [[ "$line" =~ Enter\ ssh\ password\ when\ prompted:\ ([^[:space:]]+) ]]; then
            local bastion_password="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"bastion_password\"]=\"$bastion_password\"" >> "$lab_config_file"
                print_info "  Password: ***" >&2
            fi
            continue
        fi

        # Skip admin password and console URL extraction as they're not used in playbooks
        if [[ "$line" =~ User\ admin\ with\ password\ ([^[:space:]]+)\ is\ cluster\ admin ]]; then
            print_info "  Admin Password: *** (not used in playbooks)" >&2
            continue
        fi

        if [[ "$line" =~ OpenShift\ Console:\ (https://[^[:space:]]+) ]]; then
            print_info "  Console URL: ${BASH_REMATCH[1]} (not used in playbooks)" >&2
            continue
        fi

        # Parse data section (YAML-like format)
        if [[ "$in_data_section" == "true" && "$line" =~ ^[[:space:]]*([^:]+):[[:space:]]*(.*)$ ]]; then
            local key="${BASH_REMATCH[1]// /_}"
            local value="${BASH_REMATCH[2]}"

            # Handle multi-line YAML values (>- syntax)
            if [[ "$value" == ">-" ]]; then
                skip_next_line=true
                continue
            fi

            # Clean up value
            value=$(echo "$value" | sed 's/^["\x27]\|["\x27]$//g' | sed 's/^[[:space:]]*\|[[:space:]]*$//g')

            if [[ -n "$lab_config_file" && -n "$value" && "$value" != ">" && "$current_lab" != "prod" ]]; then
                echo "  [\"$key\"]=\"$value\"" >> "$lab_config_file"
                print_info "  Data: $key = $value" >&2
            fi
            continue
        fi

        # Parse external IP variables (only from export lines to avoid duplicates)
        if [[ "$line" =~ ^export\ EXTERNAL_IP_([^=]+)=(.+) ]]; then
            local ip_type="${BASH_REMATCH[1],,}"
            local ip_value="${BASH_REMATCH[2]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"rhoso_external_ip_${ip_type}\"]=\"$ip_value\"" >> "$lab_config_file"
                print_info "  External IP ${ip_type}: $ip_value" >&2
            fi
            continue
        fi

    done < "$config_file"

    # Save the last lab if it's valid
    if [[ -n "$current_lab" && -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
        echo ")" >> "$lab_config_file"
        ((lab_count++))
        print_info "Completed parsing lab: $current_lab" >&2
    fi

    echo "$lab_count"
}

# Generate inventory file for a lab
generate_inventory_file() {
    local lab_config_file="$1"
    local output_dir="$2"
    local dry_run="$3"
    local force="$4"

    # Parse the lab configuration file directly instead of sourcing it
    local lab_id=$(grep "LAB_ID=" "$lab_config_file" | cut -d'"' -f2)
    
    # Extract values from the config file using grep and sed (take first match only to avoid duplicates)
    local bastion_hostname=$(grep '\["bastion_hostname"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    local bastion_port=$(grep '\["bastion_port"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    local bastion_user=$(grep '\["bastion_user"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    local bastion_password=$(grep '\["bastion_password"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    local guid=$(grep '\["guid"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    # If guid is empty, use lab_id as fallback
    if [[ -z "$guid" ]]; then
        guid="$lab_id"
    fi
    # Try to extract external IPs from the parsed config, with correct field names (take first match only)
    local rhoso_external_ip_worker_1=$(grep '\["rhoso_external_ip_worker_1"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    local rhoso_external_ip_worker_2=$(grep '\["rhoso_external_ip_worker_2"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    local rhoso_external_ip_worker_3=$(grep '\["rhoso_external_ip_worker_3"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    local rhoso_external_ip_bastion=$(grep '\["rhoso_external_ip_bastion"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    
    # If not found, try alternative field names (the parsing might use different case)
    [[ -z "$rhoso_external_ip_worker_1" ]] && rhoso_external_ip_worker_1=$(grep '\["rhoso_external_ip_WORKER_1"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    [[ -z "$rhoso_external_ip_worker_2" ]] && rhoso_external_ip_worker_2=$(grep '\["rhoso_external_ip_WORKER_2"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    [[ -z "$rhoso_external_ip_worker_3" ]] && rhoso_external_ip_worker_3=$(grep '\["rhoso_external_ip_WORKER_3"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    [[ -z "$rhoso_external_ip_bastion" ]] && rhoso_external_ip_bastion=$(grep '\["rhoso_external_ip_BASTION"\]' "$lab_config_file" | head -1 | sed 's/.*="\([^"]*\)".*/\1/')
    
    # Use defaults if values are empty
    [[ -z "$guid" ]] && guid="$lab_id"
    [[ -z "$bastion_user" ]] && bastion_user="lab-user"
    [[ -z "$rhoso_external_ip_worker_1" ]] && rhoso_external_ip_worker_1="172.21.0.21"
    [[ -z "$rhoso_external_ip_worker_2" ]] && rhoso_external_ip_worker_2="172.21.0.22"
    [[ -z "$rhoso_external_ip_worker_3" ]] && rhoso_external_ip_worker_3="172.21.0.23"
    [[ -z "$rhoso_external_ip_bastion" ]] && rhoso_external_ip_bastion="172.21.0.50"
    
    # Create output filename
    local output_file="$output_dir/hosts-${guid}.yml"
    
    # Check if file exists and force is not set
    if [[ -f "$output_file" && "$force" != "true" ]]; then
        print_warning "File $output_file already exists. Use --force to overwrite."
        return 2  # Use exit code 2 to distinguish from other errors
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "Would create: $output_file"
        print_info "  Lab ID: $lab_id"
        print_info "  GUID: $guid"
        print_info "  Bastion: ${bastion_hostname:-unknown}:${bastion_port:-unknown}"
        return 0
    fi
    
    print_status "Generating inventory for lab: $lab_id (GUID: $guid)"
    
    # Generate the inventory file
    cat > "$output_file" << EOF
---
# Ansible inventory for RHOSO deployment via SSH jump host (bastion)
# Generated for Lab: $lab_id (GUID: $guid)
# Generated on: $(date)

all:
  vars:
    # Lab-specific variables
    lab_guid: "$guid"
    bastion_user: "$bastion_user"
    bastion_hostname: "$bastion_hostname"
    bastion_port: "$bastion_port"
    bastion_password: "$bastion_password"
    
    # Red Hat Registry credentials (required)
    registry_username: ""  # Add your Red Hat registry service account username
    registry_password: ""  # Add your Red Hat registry service account password/token
    
    # Subscription Manager credentials (required)
    rhc_username: ""  # Add your Red Hat Customer Portal username
    rhc_password: ""  # Add your Red Hat Customer Portal password
    
    # Internal lab hostnames (accessed from bastion)
    nfs_server_hostname: "nfsserver"  # Internal hostname for NFS server
    compute_hostname: "compute01"     # Internal hostname for compute node
    
    # External IP configuration for OpenShift worker nodes
    rhoso_external_ip_worker_1: "$rhoso_external_ip_worker_1"
    rhoso_external_ip_worker_2: "$rhoso_external_ip_worker_2"
    rhoso_external_ip_worker_3: "$rhoso_external_ip_worker_3"
    
    # Bastion external IP for final network configuration
    rhoso_external_ip_bastion: "$rhoso_external_ip_bastion"

# All operations run on the bastion host
bastion:
  hosts:
    bastion-jumphost:
      ansible_host: "$bastion_hostname"
      ansible_user: "$bastion_user"
      ansible_port: "$bastion_port"
      ansible_ssh_pass: "$bastion_password"
      ansible_python_interpreter: /usr/bin/python3.11

# NFS server operations via SSH jump host (bastion)
nfsserver:
  hosts:
    nfs-server:
      ansible_host: "nfsserver"
      ansible_user: "cloud-user"
      # ansible_python_interpreter: /usr/bin/python3  # Optional: Let Ansible auto-detect Python (works with Python 2.7+ or 3.x)
      ansible_ssh_private_key_file: "/home/$bastion_user/.ssh/${guid}key.pem"
      # SSH through bastion host
      ansible_ssh_common_args: '-o ProxyCommand="sshpass -p $bastion_password ssh -W %h:%p -p $bastion_port $bastion_user@$bastion_hostname"'

# Compute node operations via SSH jump host (bastion)
compute_nodes:
  hosts:
    compute01:
      ansible_host: "compute01"
      ansible_user: "cloud-user"
      # ansible_python_interpreter: /usr/bin/python3  # Optional: Let Ansible auto-detect Python (works with Python 2.7+ or 3.x)
      ansible_ssh_private_key_file: "/home/$bastion_user/.ssh/${guid}key.pem"
      # SSH through bastion host
      ansible_ssh_common_args: '-o ProxyCommand="sshpass -p $bastion_password ssh -W %h:%p -p $bastion_port $bastion_user@$bastion_hostname"'
EOF
    
    print_success "Created inventory file: $output_file"
    return 0
}

# Main function
main() {
    local labs_config_file=""
    local output_dir="inventory"
    local force="false"
    local dry_run="false"
    
    # Parse command line arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -o|--output-dir)
                output_dir="$2"
                shift 2
                ;;
            -f|--force)
                force="true"
                shift
                ;;
            -d|--dry-run)
                dry_run="true"
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                exit 1
                ;;
            *)
                if [[ -z "$labs_config_file" ]]; then
                    labs_config_file="$1"
                else
                    print_error "Multiple config files specified. Only one is allowed."
                    usage
                    exit 1
                fi
                shift
                ;;
        esac
    done
    
    # Validate required arguments
    if [[ -z "$labs_config_file" ]]; then
        print_error "Labs configuration file is required"
        usage
        exit 1
    fi
    
    if [[ ! -f "$labs_config_file" ]]; then
        print_error "Labs configuration file not found: $labs_config_file"
        exit 1
    fi
    
    # Create output directory if it doesn't exist
    if [[ "$dry_run" != "true" ]]; then
        mkdir -p "$output_dir"
    fi
    
    print_status "Lab Inventory Generator"
    print_status "======================"
    print_info "Input file: $labs_config_file"
    print_info "Output directory: $output_dir"
    print_info "Force overwrite: $force"
    print_info "Dry run: $dry_run"
    
    # Create temporary directory for parsing
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT
    
    print_status "Parsing lab configuration..."
    local lab_count=$(parse_lab_config "$labs_config_file" "$temp_dir")
    
    if [[ "$lab_count" -eq 0 ]]; then
        print_error "No valid labs found in configuration file"
        exit 1
    fi
    
    print_success "Found $lab_count labs to process"
    
    # Generate inventory files for each lab
    local success_count=0
    local skip_count=0
    
    print_info "DEBUG: Looking for config files in: $temp_dir/lab_configs/"
    print_info "DEBUG: Config files found: $(ls -1 "$temp_dir"/lab_configs/lab_*.conf 2>/dev/null | wc -l)"
    
    for config_file in "$temp_dir"/lab_configs/lab_*.conf; do
        if [[ -f "$config_file" ]]; then
            print_info "DEBUG: Processing config file: $config_file"
            # Temporarily disable exit on error for this function call
            set +e
            generate_inventory_file "$config_file" "$output_dir" "$dry_run" "$force"
            local exit_code=$?
            set -e
            
            print_info "DEBUG: generate_inventory_file returned exit code: $exit_code"
            
            if [[ $exit_code -eq 0 ]]; then
                ((success_count++))
                print_info "DEBUG: Success count incremented to: $success_count"
            elif [[ $exit_code -eq 2 ]]; then
                ((skip_count++))
                print_info "DEBUG: Skip count incremented to: $skip_count (file already exists)"
            else
                ((skip_count++))
                print_error "DEBUG: Error processing $config_file (exit code: $exit_code)"
            fi
        else
            print_info "DEBUG: Config file not found or not readable: $config_file"
        fi
    done
    
    print_info "DEBUG: Final counts - Success: $success_count, Skip: $skip_count"
    
    # Summary
    print_status "Generation Summary"
    print_status "=================="
    print_success "Successfully generated: $success_count"
    if [[ "$skip_count" -gt 0 ]]; then
        print_warning "Skipped (already exists): $skip_count"
    fi
    
    if [[ "$dry_run" == "true" ]]; then
        print_info "Dry run completed. No files were created."
    else
        print_info "Generated inventory files in: $output_dir"
        print_info "Use these files with: ./deploy-via-jumphost.sh --inventory $output_dir/hosts-{guid}.yml"
    fi
}

# Run main function with all arguments
main "$@"
