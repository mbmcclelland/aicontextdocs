#!/usr/bin/bash

# Color codes
RED='\e[1;31m'
BLUE='\033[44;33m'
NC='\e[0m'

# Configuration variables
LICENSE_FILE="license.lic"
INSTALLER_BIN="5.5.3.0-7a313ad816bdee64.bin"
AHS_HOME="/home/auraria/AHS"
REALM_NAME="TheReef"
EXPFS=1

# Script options
VERBOSE=false
OUTPUT_FILE=""
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

###############################################################################
# Display usage information
###############################################################################
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    -v, --verbose       Enable verbose output
    -o, --output FILE   Write output to timestamped file (FILE_TIMESTAMP.log)
    -h, --help          Display this help message

EXAMPLES:
    $0 --verbose
    $0 --verbose -o install
    $0 -v -o /tmp/digital_reef
EOF
    exit 0
}

###############################################################################
# Parse command line arguments
###############################################################################
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -o|--output)
                if [ -z "$2" ]; then
                    echo "Error: -o requires a file path argument"
                    usage
                fi
                OUTPUT_FILE="${2}_${TIMESTAMP}.log"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                echo "Error: Unknown option: $1"
                usage
                ;;
        esac
    done
}

###############################################################################
# Log function - outputs to console and/or file
###############################################################################
log() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local formatted_message="[$timestamp] $message"

    # Always print to console
    echo "$formatted_message"

    # Also write to file if specified
    if [ -n "$OUTPUT_FILE" ]; then
        echo "$formatted_message" >> "$OUTPUT_FILE"
    fi
}

###############################################################################
# Log with color support (removes ANSI codes from file)
###############################################################################
log_color() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Print to console with colors
    echo -e "[$timestamp] $message"

    # Write to file without ANSI codes
    if [ -n "$OUTPUT_FILE" ]; then
        echo "[$timestamp] $(echo -e "$message" | sed 's/\x1b\[[0-9;]*m//g')" >> "$OUTPUT_FILE"
    fi
}

###############################################################################
# Verbose logging - only outputs if --verbose flag is set
###############################################################################
log_verbose() {
    local message="$1"

    if [ "$VERBOSE" = true ]; then
        log "$message"
    fi
}

###############################################################################
# Validate prerequisites
###############################################################################
validate_prerequisites() {
    log "Validating prerequisites..."

    # Check for required commands
    local required_commands=("systemctl" "qrencode" "ip")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "Error: Required command not found: $cmd"
            exit 1
        fi
    done

    # Check for installer binary
    if [ ! -f "$INSTALLER_BIN" ]; then
        log "Error: Installer binary not found: $INSTALLER_BIN"
        exit 1
    fi

    if [ ! -x "$INSTALLER_BIN" ]; then
        log_verbose "Making installer binary executable..."
        chmod +x "$INSTALLER_BIN"
    fi

    # Check for license file (optional, just warn if missing)
    if [ ! -f "$LICENSE_FILE" ]; then
        log "Warning: License file not found: $LICENSE_FILE (proceeding without it)"
    fi

    log "Prerequisites validated successfully"
}

###############################################################################
# Stop Digital Reef services
###############################################################################
stop_services() {
    log "Stopping Digital Reef services..."

    if [ "$VERBOSE" = true ]; then
        SYSTEMD_LOG_LEVEL=debug systemctl stop drd drd-wildfly 2>&1 | tee -a "$OUTPUT_FILE"
    else
        SYSTEMD_LOG_LEVEL=debug systemctl stop drd drd-wildfly 2>&1 | tee -a "$OUTPUT_FILE" > /dev/null
    fi

    if [ $? -eq 0 ]; then
        log "Services stopped successfully"
    else
        log "Warning: Service stop command completed with exit code $?"
    fi
}

###############################################################################
# Backup and copy license file (if it exists)
###############################################################################
copy_license() {
    # Only copy if license file exists
    if [ ! -f "$LICENSE_FILE" ]; then
        log "Skipping license file copy (file not found)"
        return 0
    fi

    log "Copying license file..."

    if [ "$VERBOSE" = true ]; then
        \cp -v "$LICENSE_FILE" /tmp/license.lic 2>&1 | tee -a "$OUTPUT_FILE"
    else
        \cp "$LICENSE_FILE" /tmp/license.lic 2>&1 | tee -a "$OUTPUT_FILE" > /dev/null
    fi

    if [ $? -eq 0 ]; then
        log "License file copied successfully"
    else
        log "Warning: Failed to copy license file"
    fi
}

###############################################################################
# Clean up existing installation directories and cache
###############################################################################
cleanup_installation() {
    log "Cleaning up existing installation files..."

    log_verbose "Removing: ${AHS_HOME}*"
    rm -rf "${AHS_HOME}"* 2>&1 | tee -a "$OUTPUT_FILE" > /dev/null

    log_verbose "Removing: /var/.com.zerog.registry.xml"
    rm -rf /var/.com.zerog.registry.xml 2>&1 | tee -a "$OUTPUT_FILE" > /dev/null

    log_verbose "Removing: /tmp/cbe*"
    rm -rf /tmp/cbe* 2>&1 | tee -a "$OUTPUT_FILE" > /dev/null

    log "Cleanup completed"
}

###############################################################################
# Set debug environment variables
###############################################################################
set_debug_environment() {
    log "Setting debug environment variables..."
    export LAX_DEBUG=true
    export _JAVA_OPTIONS="-Dlax.debug.level=3 -Dlax.debug.all=true"
    log_verbose "LAX_DEBUG=$LAX_DEBUG"
    log_verbose "_JAVA_OPTIONS=$_JAVA_OPTIONS"
    log "Debug environment configured"
}

###############################################################################
# Get system IP address
###############################################################################
get_ip_address() {
    ip route get 1 | awk '{print $7; exit}'
}

###############################################################################
# Run the installer in silent mode
###############################################################################
run_installer() {
    local ip_address=$1

    log "Starting silent installation..."
    log "IP Address: $ip_address"
    log "Realm Name: $REALM_NAME"
    log_verbose "Installer Binary: $INSTALLER_BIN"

    if [ "$VERBOSE" = true ]; then
        ./"$INSTALLER_BIN" \
            -i silent \
            -DNODETYPE=full \
            -DREALMNAME="$REALM_NAME" \
            -DIPADDRESS="$ip_address" \
            -DDATABASE_IP="$ip_address" \
            -DEXPFS=$EXPFS 2>&1 | tee -a "$OUTPUT_FILE"
    else
        ./"$INSTALLER_BIN" \
            -i silent \
            -DNODETYPE=full \
            -DREALMNAME="$REALM_NAME" \
            -DIPADDRESS="$ip_address" \
            -DDATABASE_IP="$ip_address" \
            -DEXPFS=$EXPFS 2>&1 | tee -a "$OUTPUT_FILE" > /dev/null
    fi

    if [ $? -eq 0 ]; then
        log "Installation completed successfully"
    else
        log "Error: Installation failed with exit code $?"
        exit 1
    fi
}

###############################################################################
# Get host ID from installed application
###############################################################################
get_host_id() {
    log "Retrieving Host ID..."

    if [ ! -f "${AHS_HOME}/bin/hostid.sh" ]; then
        log "Error: hostid.sh not found at ${AHS_HOME}/bin/hostid.sh"
        exit 1
    fi

    HOST_ID=$("${AHS_HOME}"/bin/hostid.sh -g 2>&1 | tail -n 1 | awk '{print $5}')

    if [ -z "$HOST_ID" ]; then
        log "Error: Failed to retrieve Host ID"
        exit 1
    fi

    log_verbose "Host ID: $HOST_ID"
    echo "$HOST_ID"
}

###############################################################################
# Display Host ID and QR code
###############################################################################
display_host_id() {
    local host_id=$1

    log "=========================================="
    log_color "Your Host ID is: ${RED}${host_id}${NC}"
    log "=========================================="
    log "Generating QR code..."

    qrencode -t ANSIUTF8 "$host_id" 2>&1 | tee -a "$OUTPUT_FILE"

    log "Scan the above QR code to easily obtain your license id on a mobile device."
}

###############################################################################
# Display connection information
###############################################################################
display_connection_info() {
    local ip_address=$1

    log "=========================================="
    log_color "Connect to Digital Reef with the following URL: ${BLUE}https://${ip_address}:8443${NC}"
    log "=========================================="
}

###############################################################################
# Main function
###############################################################################
main() {
    log "=========================================="
    log "Digital Reef Installation Script"
    log "=========================================="

    if [ -n "$OUTPUT_FILE" ]; then
        log "Output file: $OUTPUT_FILE"
    fi

    if [ "$VERBOSE" = true ]; then
        log "Verbose mode: ENABLED"
    fi

    # Get IP address early for multiple uses
    IP_ADDRESS=$(get_ip_address)

    if [ -z "$IP_ADDRESS" ]; then
        log "Error: Could not determine system IP address"
        exit 1
    fi

    log_verbose "System IP Address: $IP_ADDRESS"

    # Execute installation steps
    validate_prerequisites
    stop_services
    copy_license
    cleanup_installation
    set_debug_environment
    run_installer "$IP_ADDRESS"

    # Get and display host information
    HOST_ID=$(get_host_id)
    display_host_id "$HOST_ID"
    display_connection_info "$IP_ADDRESS"

    log "=========================================="
    log "Installation completed successfully!"
    log "=========================================="
}

###############################################################################
# Script Entry Point
###############################################################################

# Parse command line arguments
parse_arguments "$@"

# Initialize output file if specified
if [ -n "$OUTPUT_FILE" ]; then
    touch "$OUTPUT_FILE" 2>/dev/null
    if [ ! -w "$OUTPUT_FILE" ]; then
        echo "Error: Cannot write to output file: $OUTPUT_FILE"
        exit 1
    fi
    log "Log file created: $OUTPUT_FILE"
fi

# Run main function
main
