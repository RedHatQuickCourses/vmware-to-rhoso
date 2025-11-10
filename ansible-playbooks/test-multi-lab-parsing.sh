#!/bin/bash

# Test script for the fixed parsing logic
set -euo pipefail

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_status() {
    echo -e "${GREEN}[STATUS]${NC} $1"
}

# Test the parsing function from the fixed script
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
            # Save previous lab if exists and it's valid
            if [[ -n "$current_lab" && -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo ")" >> "$lab_config_file"
                ((lab_count++))
                print_info "Completed parsing lab: $current_lab" >&2
            fi

            # Start new lab - clean up the lab ID
            current_lab="${BASH_REMATCH[1]}"
            current_lab=$(echo "$current_lab" | sed 's/[[:space:]]*$//' | sed 's/[^a-zA-Z0-9-]//g')

            # Skip if this is just "prod" (data section header) or empty
            if [[ "$current_lab" == "prod" || -z "$current_lab" ]]; then
                current_lab=""
                lab_config_file=""
                in_data_section=true
                continue
            fi

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

        # Parse admin password
        if [[ "$line" =~ User\ admin\ with\ password\ ([^[:space:]]+)\ is\ cluster\ admin ]]; then
            local admin_password="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"ocp_admin_password\"]=\"$admin_password\"" >> "$lab_config_file"
                print_info "  Admin Password: ***" >&2
            fi
            continue
        fi

        # Parse OpenShift console URL
        if [[ "$line" =~ OpenShift\ Console:\ (https://[^[:space:]]+) ]]; then
            local console_url="${BASH_REMATCH[1]}"
            if [[ -n "$lab_config_file" && "$current_lab" != "prod" ]]; then
                echo "  [\"ocp_console_url\"]=\"$console_url\"" >> "$lab_config_file"
            fi
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

# Main test function
main() {
    local config_file="$1"
    
    if [[ ! -f "$config_file" ]]; then
        print_error "Config file not found: $config_file"
        exit 1
    fi

    print_status "Testing Fixed Multi-Lab Parser"
    print_info "Config file: $config_file"

    # Create temporary directory
    local temp_dir=$(mktemp -d)
    trap "rm -rf $temp_dir" EXIT

    print_status "Testing parsing of: $config_file"
    local lab_count=$(parse_lab_config "$config_file" "$temp_dir")

    print_success "Successfully parsed $lab_count labs"

    # Show the generated configuration files
    for config_file in "$temp_dir"/lab_configs/lab_*.conf; do
        if [[ -f "$config_file" ]]; then
            local lab_id=$(basename "$config_file" .conf | sed 's/^lab_//')
            print_info "Configuration file: lab_${lab_id}.conf"
            echo "----------------------------------------"
            cat "$config_file"
            echo "----------------------------------------"
            echo
        fi
    done

    print_status "Cleaning up test files..."
}

# Check if config file is provided
if [[ $# -eq 0 ]]; then
    echo "Usage: $0 <config_file>"
    echo "Example: $0 my_labs_to_be_deployed"
    exit 1
fi

main "$1"
