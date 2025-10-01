#!/bin/bash
set -euo pipefail

# Automated cleanup script for expired ephemeral environments
# Run this via cron to automatically destroy expired environments

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${SCRIPT_DIR}/cleanup.log"
DRY_RUN=false
FORCE=false

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}" | tee -a "$LOG_FILE"
}

print_error() {
    echo -e "${RED}✗ $1${NC}" | tee -a "$LOG_FILE"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}" | tee -a "$LOG_FILE"
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Automatically cleanup expired ephemeral environments.

Options:
  --dry-run    Show what would be deleted without actually deleting
  --force      Skip confirmation prompts
  --help       Show this help message

Examples:
  # Check what would be deleted
  $0 --dry-run

  # Cleanup with confirmation
  $0

  # Cleanup without prompts (for cron)
  $0 --force

Cron Example (run every hour):
  0 * * * * /path/to/cleanup-expired.sh --force >> /path/to/cleanup.log 2>&1

EOF
    exit 1
}

check_prerequisites() {
    if ! command -v terraform &> /dev/null; then
        print_error "Terraform is not installed"
        exit 1
    fi
    
    if ! command -v az &> /dev/null; then
        print_error "Azure CLI is not installed"
        exit 1
    fi
    
    if ! az account show &> /dev/null; then
        print_error "Not logged into Azure"
        exit 1
    fi
}

get_expired_environments() {
    local now=$(date -u +%s)
    local expired=()
    
    # Check Azure Resource Groups with AutoDestroy tag
    log "Checking Azure for expired environments..."
    
    local resource_groups=$(az group list --query "[?tags.AutoDestroy=='true'].{name:name, destroyAfter:tags.DestroyAfter}" -o json)
    
    if [ -z "$resource_groups" ] || [ "$resource_groups" = "[]" ]; then
        log "No environments with AutoDestroy tag found"
        return
    fi
    
    echo "$resource_groups" | jq -c '.[]' | while read -r rg; do
        local name=$(echo "$rg" | jq -r '.name')
        local destroy_after=$(echo "$rg" | jq -r '.destroyAfter')
        
        if [ -z "$destroy_after" ] || [ "$destroy_after" = "null" ]; then
            print_warning "Resource group $name has no DestroyAfter tag, skipping"
            continue
        fi
        
        # Parse destroy time
        local destroy_epoch=$(date -d "$destroy_after" +%s 2>/dev/null || echo "0")
        
        if [ "$destroy_epoch" -lt "$now" ]; then
            local hours_expired=$(( (now - destroy_epoch) / 3600 ))
            print_warning "Environment '$name' expired $hours_expired hours ago"
            
            if [ "$DRY_RUN" = true ]; then
                print_info "[DRY RUN] Would delete: $name"
            else
                if [ "$FORCE" = false ]; then
                    read -p "Delete resource group $name? (yes/no): " confirm
                    if [ "$confirm" != "yes" ]; then
                        print_info "Skipped: $name"
                        continue
                    fi
                fi
                
                print_info "Deleting resource group: $name"
                if az group delete --name "$name" --yes --no-wait; then
                    print_success "Deletion initiated for: $name"
                    log "SUCCESS: Deleted $name (expired $hours_expired hours ago)"
                else
                    print_error "Failed to delete: $name"
                    log "ERROR: Failed to delete $name"
                fi
            fi
        fi
    done
}

generate_report() {
    local report_file="${SCRIPT_DIR}/cleanup-report-$(date +%Y%m%d-%H%M%S).txt"
    
    log "Generating cleanup report..."
    
    {
        echo "Ephemeral Environment Cleanup Report"
        echo "====================================="
        echo "Generated: $(date)"
        echo ""
        echo "Active Environments:"
        echo "-------------------"
        
        az group list --query "[?tags.AutoDestroy=='true'].{Name:name, Owner:tags.Owner, TTL:tags.TTL, DestroyAfter:tags.DestroyAfter}" -o table
        
        echo ""
        echo "Recent Cleanup Activity:"
        echo "----------------------"
        tail -n 50 "$LOG_FILE" 2>/dev/null || echo "No recent activity"
        
    } > "$report_file"
    
    print_success "Report saved to: $report_file"
}

send_notification() {
    local message="$1"
    
    # Add your notification method here (email, Slack, Teams, etc.)
    # Example with webhook:
    # curl -X POST -H 'Content-type: application/json' \
    #   --data "{\"text\":\"$message\"}" \
    #   YOUR_WEBHOOK_URL
    
    log "NOTIFICATION: $message"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help)
            show_usage
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            ;;
    esac
done

# Main execution
main() {
    log "=================================="
    log "Starting cleanup process"
    log "=================================="
    
    if [ "$DRY_RUN" = true ]; then
        print_info "Running in DRY RUN mode - no changes will be made"
    fi
    
    check_prerequisites
    get_expired_environments
    
    log "=================================="
    log "Cleanup process completed"
    log "=================================="
    
    if [ "$DRY_RUN" = false ]; then
        generate_report
    fi
}

main