#!/bin/bash
# Deploy VM Migration Setup with Ansible Automation Platform
# This script automates the setup of AAP and VM migration toolkit

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
INVENTORY=""
CREDENTIALS=""
TAGS=""
SKIP_TAGS=""
VERBOSE=""
PLAYBOOK="migration-setup.yml"  # Default playbook

# Function to display usage
usage() {
    cat << EOF
Usage: $0 --inventory <inventory_file> --credentials <credentials_file> [OPTIONS]

Deploy VM Migration Setup with Ansible Automation Platform

Required Arguments:
  --inventory <file>       Path to inventory file (e.g., inventory/hosts-guid.yml)
  --credentials <file>     Path to credentials file (e.g., credentials.yml)

Deployment Modes (default: --full):
  --prereqs               Deploy conversion host ONLY
                          Creates OpenStack networks, security groups, and conversion host VM
                          Use this if you only want to deploy prerequisites
  
  --full                  Deploy prerequisites + AAP + execution environment (DEFAULT)
                          NOTE: Stops BEFORE configuring AAP for migration
                          You must upload AAP license manually, then run --configure-aap
  
  --skip-prereqs          Deploy AAP and EE ONLY (skip conversion host)
                          Use this if conversion host is already deployed
  
  --configure-aap         Configure AAP for migration (run AFTER uploading license)
                          Creates credentials, inventory, hosts, project, and job template

Optional Arguments:
  --tags <tags>           Run only tasks with specific tags (comma-separated)
                          Available tags: install-aap, ansible-builder, configure-migration, configure-aap-for-migration
  --skip-tags <tags>      Skip tasks with specific tags (comma-separated)
  -v, --verbose           Enable verbose output
  -h, --help              Display this help message

Examples:
  # Full deployment (DEFAULT - deploys prereqs + AAP + EE, stops before AAP config)
  $0 --inventory inventory/hosts-abc123.yml --credentials credentials.yml
  
  # Deploy conversion host ONLY
  $0 --inventory inventory/hosts-abc123.yml --credentials credentials.yml --prereqs

  # Deploy AAP and EE ONLY (skip prereqs if already deployed)
  $0 --inventory inventory/hosts-abc123.yml --credentials credentials.yml --skip-prereqs

  # Configure AAP for migration (AFTER uploading license via AAP UI)
  $0 --inventory inventory/hosts-abc123.yml --credentials credentials.yml --configure-aap

  # Install only AAP (conversion host must exist)
  $0 --inventory inventory/hosts-abc123.yml --credentials credentials.yml --tags install-aap --skip-prereqs

  # Build execution environment only
  $0 --inventory inventory/hosts-abc123.yml --credentials credentials.yml --tags ansible-builder --skip-prereqs

Workflow:
  1. Deploy prerequisites + AAP + EE:
     $0 --inventory <inv> --credentials <cred>
  
  2. Upload AAP license via AAP Web UI (manual step)
  
  3. Configure AAP for migration:
     $0 --inventory <inv> --credentials <cred> --configure-aap
  
  4. Launch migration from AAP UI

Related Playbooks:
  # Launch migration after setup
  ansible-playbook -i inventory/hosts-abc123.yml launch-migration.yml

  # Complete end-to-end (setup + launch)
  ansible-playbook -i inventory/hosts-abc123.yml migration-complete.yml

EOF
    exit 1
}

# Deployment mode flags (default: full deployment)
DEPLOY_PREREQS=true
DEPLOY_MIGRATION=true
SKIP_PREREQS=false
CONFIGURE_AAP=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --inventory)
            INVENTORY="$2"
            shift 2
            ;;
        --credentials)
            CREDENTIALS="$2"
            shift 2
            ;;
        --prereqs)
            DEPLOY_PREREQS=true
            DEPLOY_MIGRATION=false
            CONFIGURE_AAP=false
            shift
            ;;
        --full)
            DEPLOY_PREREQS=true
            DEPLOY_MIGRATION=true
            CONFIGURE_AAP=false
            shift
            ;;
        --skip-prereqs)
            SKIP_PREREQS=true
            shift
            ;;
        --configure-aap)
            DEPLOY_PREREQS=false
            DEPLOY_MIGRATION=false
            CONFIGURE_AAP=true
            shift
            ;;
        --tags)
            TAGS="$2"
            shift 2
            ;;
        --skip-tags)
            SKIP_TAGS="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE="-vvv"
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option $1${NC}"
            usage
            ;;
    esac
done

# Validate required arguments
if [[ -z "$INVENTORY" ]]; then
    echo -e "${RED}Error: --inventory is required${NC}"
    usage
fi

if [[ -z "$CREDENTIALS" ]]; then
    echo -e "${RED}Error: --credentials is required${NC}"
    usage
fi

# Validate files exist
if [[ ! -f "$INVENTORY" ]]; then
    echo -e "${RED}Error: Inventory file not found: $INVENTORY${NC}"
    exit 1
fi

if [[ ! -f "$CREDENTIALS" ]]; then
    echo -e "${RED}Error: Credentials file not found: $CREDENTIALS${NC}"
    exit 1
fi

# Determine deployment mode
if [[ "$SKIP_PREREQS" == "true" ]]; then
    DEPLOY_PREREQS=false
fi

# Display configuration
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}VM Migration Setup Deployment${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "Inventory:    $INVENTORY"
echo -e "Credentials:  $CREDENTIALS"
if [[ "$CONFIGURE_AAP" == "true" ]]; then
    echo -e "Mode:         Configure AAP for Migration (post-license)"
elif [[ "$DEPLOY_PREREQS" == "true" ]] && [[ "$DEPLOY_MIGRATION" == "true" ]]; then
    echo -e "Mode:         Full (Prerequisites + AAP + EE)"
    echo -e "              NOTE: Will stop before AAP configuration"
    echo -e "              Upload license via AAP UI, then run --configure-aap"
elif [[ "$DEPLOY_PREREQS" == "true" ]]; then
    echo -e "Mode:         Prerequisites Only (Conversion Host)"
else
    echo -e "Mode:         Migration Setup (AAP + EE)"
fi
[[ -n "$TAGS" ]] && echo -e "Tags:         $TAGS"
[[ -n "$SKIP_TAGS" ]] && echo -e "Skip Tags:    $SKIP_TAGS"
[[ -n "$VERBOSE" ]] && echo -e "Verbose:      Enabled"
echo -e "${GREEN}========================================${NC}"
echo ""

# Install required Ansible collections
echo -e "${YELLOW}Installing required Ansible collections...${NC}"
if [[ -f "requirements.yml" ]]; then
    ansible-galaxy collection install -r requirements.yml
    if [[ $? -ne 0 ]]; then
        echo -e "${RED}Error: Failed to install Ansible collections${NC}"
        exit 1
    fi
    echo -e "${GREEN}✓ Ansible collections installed successfully${NC}"
    echo ""
else
    echo -e "${YELLOW}Warning: requirements.yml not found, skipping collection installation${NC}"
    echo ""
fi

# Function to run a playbook
run_playbook() {
    local playbook=$1
    local description=$2
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}$description${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # Build ansible-playbook command
    local ANSIBLE_CMD="ansible-playbook -i $INVENTORY $playbook -e @$CREDENTIALS"
    
    # Add optional parameters
    [[ -n "$TAGS" ]] && ANSIBLE_CMD="$ANSIBLE_CMD --tags $TAGS"
    [[ -n "$SKIP_TAGS" ]] && ANSIBLE_CMD="$ANSIBLE_CMD --skip-tags $SKIP_TAGS"
    [[ -n "$VERBOSE" ]] && ANSIBLE_CMD="$ANSIBLE_CMD $VERBOSE"
    
    # Display command
    echo -e "${YELLOW}Executing:${NC} $ANSIBLE_CMD"
    echo ""
    
    # Execute playbook
    eval $ANSIBLE_CMD
    return $?
}

# Execute deployment based on mode
OVERALL_STATUS=0

# Step 1: Deploy prerequisites if requested
if [[ "$DEPLOY_PREREQS" == "true" ]]; then
    run_playbook "migration-prereqs.yml" "Step 1: Deploying Conversion Host (Prerequisites)"
    if [[ $? -ne 0 ]]; then
        echo ""
        echo -e "${RED}========================================${NC}"
        echo -e "${RED}Prerequisites deployment failed!${NC}"
        echo -e "${RED}========================================${NC}"
        exit 1
    fi
    
    if [[ "$DEPLOY_MIGRATION" == "true" ]]; then
        echo ""
        echo -e "${GREEN}✓ Prerequisites completed successfully${NC}"
        echo -e "${YELLOW}Proceeding to AAP installation...${NC}"
        sleep 2
    fi
fi

# Step 2: Deploy AAP and EE (migration-setup.yml without configure-aap-for-migration)
if [[ "$DEPLOY_MIGRATION" == "true" ]]; then
    if [[ "$DEPLOY_PREREQS" == "true" ]]; then
        run_playbook "migration-setup.yml" "Step 2: Deploying AAP and Execution Environment"
    else
        run_playbook "migration-setup.yml" "Deploying AAP and Execution Environment"
    fi
    
    if [[ $? -ne 0 ]]; then
        OVERALL_STATUS=1
    fi
fi

# Step 3: Configure AAP for migration (only if --configure-aap flag is set)
if [[ "$CONFIGURE_AAP" == "true" ]]; then
    # Override TAGS to run only configure-aap-for-migration
    TAGS="configure-aap-for-migration"
    run_playbook "migration-setup.yml" "Configuring AAP for VM Migration"
    
    if [[ $? -ne 0 ]]; then
        OVERALL_STATUS=1
    fi
fi

# Display final status
echo ""
if [[ $OVERALL_STATUS -eq 0 ]]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Deployment completed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    
    # Display next steps based on what was deployed
    if [[ "$DEPLOY_PREREQS" == "true" ]] && [[ "$DEPLOY_MIGRATION" == "false" ]]; then
        echo ""
        echo -e "${YELLOW}Next Steps:${NC}"
        echo "1. Verify conversion host access:"
        echo "   ssh -i ~/.ssh/<guid>key.pem cloud-user@<conversion_host_ip>"
        echo ""
        echo "2. Proceed with AAP installation:"
        echo "   $0 --inventory $INVENTORY --credentials $CREDENTIALS --skip-prereqs"
        echo ""
    elif [[ "$CONFIGURE_AAP" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}Next Steps:${NC}"
        echo "1. Access AAP Dashboard (URL shown in output above)"
        echo "2. Navigate to: Resources → Templates → 'HAproxy VM Migration'"
        echo "3. Click: Launch 🚀"
        echo ""
    elif [[ "$DEPLOY_MIGRATION" == "true" ]]; then
        echo ""
        echo -e "${YELLOW}⚠️  IMPORTANT - Next Steps:${NC}"
        echo ""
        echo "1. Upload AAP License (REQUIRED):"
        echo "   - Access AAP Dashboard (URL shown in output above)"
        echo "   - Login as admin"
        echo "   - Upload your subscription manifest when prompted"
        echo ""
        echo "2. After uploading license, configure AAP for migration:"
        echo "   $0 --inventory $INVENTORY --credentials $CREDENTIALS --configure-aap"
        echo ""
        echo "3. Launch migration from AAP UI"
        echo ""
    else
        echo ""
        echo -e "${YELLOW}Next Steps:${NC}"
        echo "1. Access AAP Dashboard (URL shown in output above)"
        echo "2. Upload license if not already done"
        echo "3. Run: $0 --inventory $INVENTORY --credentials $CREDENTIALS --configure-aap"
        echo ""
    fi
    
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}Deployment failed!${NC}"
    echo -e "${RED}========================================${NC}"
    exit 1
fi

