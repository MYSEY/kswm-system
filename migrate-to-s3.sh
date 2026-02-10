#!/bin/bash

# ===================================================================
# Migration Script: Local Storage to DigitalOcean Spaces (S3)
# Loads configuration from Laravel .env file
# Usage: ./migrate-to-s3.sh [options]
# ===================================================================

# Configuration
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
STORAGE_PATH="$PROJECT_ROOT/storage/app"
PUBLIC_STORAGE_PATH="$PROJECT_ROOT/storage/app/public"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script options
DRY_RUN=false
DELETE_LOCAL=false
SPECIFIC_PATH=""
VERBOSE=false
EXCLUDE_PATTERNS=""

# AWS/S3 Configuration variables (loaded from .env)
AWS_ACCESS_KEY_ID=""
AWS_SECRET_ACCESS_KEY=""
AWS_DEFAULT_REGION=""
AWS_BUCKET=""
AWS_ENDPOINT=""
AWS_URL=""

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_header() {
    echo -e "${BLUE}"
    echo "====================================================================="
    echo "🚀 Storage Migration: Local to DigitalOcean Spaces"
    echo "📁 Loading configuration from Laravel .env file"
    echo "====================================================================="
    echo -e "${NC}"
}

# Function to load environment variables from .env file
load_env_config() {
    print_info "Loading configuration from .env file..."
    
    if [ ! -f "$ENV_FILE" ]; then
        print_error ".env file not found at: $ENV_FILE"
        exit 1
    fi
    
    # Load variables from .env file
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ $key =~ ^[[:space:]]*# ]] && continue
        [[ -z $key ]] && continue
        
        # Remove quotes from value
        value=$(echo "$value" | sed 's/^["'"'"']//' | sed 's/["'"'"']$//')
        
        case $key in
            AWS_ACCESS_KEY_ID)
                AWS_ACCESS_KEY_ID="$value"
                ;;
            AWS_SECRET_ACCESS_KEY)
                AWS_SECRET_ACCESS_KEY="$value"
                ;;
            AWS_DEFAULT_REGION)
                AWS_DEFAULT_REGION="$value"
                ;;
            AWS_BUCKET)
                AWS_BUCKET="$value"
                ;;
            AWS_ENDPOINT)
                AWS_ENDPOINT="$value"
                ;;
            AWS_URL)
                AWS_URL="$value"
                ;;
        esac
    done < "$ENV_FILE"
    
    # Validate required configuration
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$AWS_BUCKET" ] || [ -z "$AWS_ENDPOINT" ]; then
        print_error "Missing required AWS configuration in .env file"
        echo "Required variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_BUCKET, AWS_ENDPOINT"
        exit 1
    fi
    
    # Build S3 bucket URL
    S3_BUCKET="s3://$AWS_BUCKET"
    
    print_success "Configuration loaded successfully"
    
    if [ "$VERBOSE" = true ]; then
        echo "  Access Key: ${AWS_ACCESS_KEY_ID:0:8}..."
        echo "  Region: $AWS_DEFAULT_REGION"
        echo "  Bucket: $AWS_BUCKET"
        echo "  Endpoint: $AWS_ENDPOINT"
        echo "  S3 URL: $S3_BUCKET"
    fi
}

# Function to create temporary s3cmd config
create_s3cmd_config() {
    local temp_config="/tmp/s3cfg_$$"
    
    cat > "$temp_config" << EOF
[default]
access_key = $AWS_ACCESS_KEY_ID
secret_key = $AWS_SECRET_ACCESS_KEY
host_base = $(echo "$AWS_ENDPOINT" | sed 's|https://||')
host_bucket = %(bucket)s.$(echo "$AWS_ENDPOINT" | sed 's|https://||')
bucket_location = $AWS_DEFAULT_REGION
use_https = True
signature_v2 = False
check_ssl_certificate = True
check_ssl_hostname = True
EOF

    echo "$temp_config"
}

# Function to test S3 connection
test_s3_connection() {
    print_info "Testing DigitalOcean Spaces connection..."
    
    local temp_config=$(create_s3cmd_config)
    
    if s3cmd -c "$temp_config" ls "$S3_BUCKET" > /dev/null 2>&1; then
        print_success "Connection to DigitalOcean Spaces successful"
        rm -f "$temp_config"
        return 0
    else
        print_error "Failed to connect to DigitalOcean Spaces"
        print_info "Please verify your .env configuration"
        rm -f "$temp_config"
        return 1
    fi
}

# Function to build s3cmd sync command
build_sync_command() {
    local source_path="$1"
    local s3_path="$2"
    local temp_config=$(create_s3cmd_config)
    local cmd="s3cmd -c '$temp_config' sync"
    
    # Add options based on script flags
    if [ "$DRY_RUN" = true ]; then
        cmd="$cmd --dry-run"
    fi
    
    if [ "$DELETE_LOCAL" = true ] && [ "$DRY_RUN" = false ]; then
        cmd="$cmd --delete-removed"
    fi
    
    if [ "$VERBOSE" = true ]; then
        cmd="$cmd --verbose"
    fi
    
    # Add exclude patterns
    if [ -n "$EXCLUDE_PATTERNS" ]; then
        cmd="$cmd $EXCLUDE_PATTERNS"
    fi
    
    # Add default excludes
    cmd="$cmd --exclude '.git/*'"
    cmd="$cmd --exclude '.DS_Store'"
    cmd="$cmd --exclude 'Thumbs.db'"
    cmd="$cmd --exclude '*.tmp'"
    cmd="$cmd --exclude '.env'"
    cmd="$cmd --exclude '.env.*'"
    
    # Set file permissions and metadata
    cmd="$cmd --acl-public"
    cmd="$cmd --guess-mime-type"
    
    # Add source and destination
    cmd="$cmd '$source_path' '$s3_path'"
    
    echo "$cmd"
}

# Function to migrate files
migrate_files() {
    local source_dir="$STORAGE_PATH"
    local s3_destination="$S3_BUCKET"
    
    # If specific path is provided, adjust source
    if [ -n "$SPECIFIC_PATH" ]; then
        source_dir="$STORAGE_PATH/$SPECIFIC_PATH"
        s3_destination="$S3_BUCKET/$SPECIFIC_PATH"
        
        if [ ! -d "$source_dir" ] && [ ! -f "$source_dir" ]; then
            print_error "Specified path does not exist: $source_dir"
            exit 1
        fi
    fi
    
    print_info "Migration details:"
    echo "  Source: $source_dir"
    echo "  Destination: $s3_destination"
    echo "  Dry run: $DRY_RUN"
    echo "  Delete local: $DELETE_LOCAL"
    echo ""
    
    # Build and execute sync command
    local sync_cmd=$(build_sync_command "$source_dir/" "$s3_destination/")
    
    if [ "$VERBOSE" = true ]; then
        print_info "Executing command:"
        echo "$sync_cmd"
        echo ""
    fi
    
    print_info "Starting file migration..."
    
    # Execute the command
    eval "$sync_cmd"
    local exit_code=$?
    
    # Clean up temp config file
    local temp_config_pattern="/tmp/s3cfg_$$"
    rm -f $temp_config_pattern 2>/dev/null
    
    if [ $exit_code -eq 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            print_success "Dry run completed successfully"
        else
            print_success "Migration completed successfully"
        fi
    else
        print_error "Migration failed with exit code: $exit_code"
        exit $exit_code
    fi
}

# Function to migrate specific Laravel storage folders
migrate_laravel_storage() {
    print_info "Migrating Laravel storage folders..."
    
    # Define Laravel storage folders to migrate
    declare -a folders=(
        "public"
        "exports"
        "users"
        "invoices"
        "documents"
        "presurvey"
        "photoidcard"
        "customer"
    )
    
    for folder in "${folders[@]}"; do
        local source_path="$STORAGE_PATH/$folder"
        
        if [ -d "$source_path" ]; then
            print_info "Migrating folder: $folder"
            
            local sync_cmd=$(build_sync_command "$source_path/" "$S3_BUCKET/storage/$folder/")
            
            if [ "$VERBOSE" = true ]; then
                echo "Command: $sync_cmd"
            fi
            
            eval "$sync_cmd"
            
            if [ $? -eq 0 ]; then
                print_success "Migrated: $folder"
            else
                print_error "Failed to migrate: $folder"
            fi
            
            # Clean up temp config
            rm -f /tmp/s3cfg_$$ 2>/dev/null
        else
            print_warning "Folder not found: $folder"
        fi
    done
}

# Function to show migration summary
show_summary() {
    print_info "Getting migration summary..."
    
    local temp_config=$(create_s3cmd_config)
    
    # Get total number of files in S3
    local s3_files=$(s3cmd -c "$temp_config" ls -r "$S3_BUCKET" 2>/dev/null | wc -l)
    
    # Get total size in S3
    local s3_size=$(s3cmd -c "$temp_config" du -H "$S3_BUCKET" 2>/dev/null | awk '{print $1}' || echo "Unknown")
    
    rm -f "$temp_config"
    
    echo ""
    print_info "Migration Summary:"
    echo "  Total files in S3: $s3_files"
    echo "  Total size in S3: $s3_size"
    echo "  Bucket: $AWS_BUCKET"
    echo "  Endpoint: $AWS_ENDPOINT"
}

# Function to verify migration
verify_migration() {
    print_info "Verifying migration..."
    
    local temp_config=$(create_s3cmd_config)
    
    if [ -n "$SPECIFIC_PATH" ]; then
        local verify_path="$S3_BUCKET/$SPECIFIC_PATH"
    else
        local verify_path="$S3_BUCKET"
    fi
    
    # List files in S3 to verify
    print_info "Recent files in S3:"
    s3cmd -c "$temp_config" ls -r "$verify_path" 2>/dev/null | head -10
    
    if [ $(s3cmd -c "$temp_config" ls -r "$verify_path" 2>/dev/null | wc -l) -gt 10 ]; then
        echo "... and more files"
    fi
    
    rm -f "$temp_config"
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run           Show what would be synced without actually doing it"
    echo "  -r, --delete-local      Delete local files after successful upload"
    echo "  -p, --path PATH         Specific path to migrate (relative to storage/app)"
    echo "  -v, --verbose           Verbose output"
    echo "  -e, --exclude PATTERN   Exclude files matching pattern (can be used multiple times)"
    echo "  -l, --laravel           Migrate Laravel-specific storage folders"
    echo "  -h, --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --dry-run                          # Show what would be migrated"
    echo "  $0 --path public/exports              # Migrate only exports folder"
    echo "  $0 --delete-local --verbose           # Migrate all and delete local files"
    echo "  $0 --laravel                          # Migrate Laravel storage folders"
    echo "  $0 --exclude '*.log' --exclude '*.tmp' # Exclude log and temp files"
    echo ""
    echo "Configuration is loaded from: $ENV_FILE"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -r|--delete-local)
            DELETE_LOCAL=true
            shift
            ;;
        -p|--path)
            SPECIFIC_PATH="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -e|--exclude)
            EXCLUDE_PATTERNS="$EXCLUDE_PATTERNS --exclude '$2'"
            shift 2
            ;;
        -l|--laravel)
            LARAVEL_MODE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main execution
main() {
    print_header
    
    # Load configuration from .env
    load_env_config
    
    # Check if s3cmd is installed
    if ! command -v s3cmd &> /dev/null; then
        print_error "s3cmd is not installed. Please install it first:"
        echo "  Ubuntu/Debian: sudo apt-get install s3cmd"
        echo "  macOS: brew install s3cmd"
        echo "  Or: pip install s3cmd"
        exit 1
    fi
    
    # Check if storage directory exists
    if [ ! -d "$STORAGE_PATH" ]; then
        print_error "Storage directory not found: $STORAGE_PATH"
        exit 1
    fi
    
    # Test S3 connection
    if ! test_s3_connection; then
        exit 1
    fi
    
    # Show what will be done
    if [ "$DRY_RUN" = true ]; then
        print_warning "DRY RUN MODE - No files will be actually migrated"
    fi
    
    # Start migration
    local start_time=$(date +%s)
    
    if [ "$LARAVEL_MODE" = true ]; then
        migrate_laravel_storage
    else
        migrate_files
    fi
    
    # Show summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    print_success "Migration completed in ${duration} seconds"
    
    # Verify migration
    verify_migration
    
    # Show summary
    show_summary
    
    print_success "All done! 🎉"
}

# Run main function
main "$@"