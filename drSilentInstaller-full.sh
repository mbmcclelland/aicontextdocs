#!/usr/bin/bash
set -x

# Create log file with timestamp (hhmmss)
LOG_FILE="/tmp/DRInstaller-Silent-$(date +%Y%m%d-%H%M%S).log"
touch "$LOG_FILE"

# Function to log output to both file and stdout
log_output() {
    echo "$@" | tee -a "$LOG_FILE"
}

# Redirect all output to log file and stdout
exec 1> >(tee -a "$LOG_FILE")
exec 2>&1

# Start timer for installation duration
START_TIME=$(date +%s)

# Initial banner
echo "Digital Reef Silent Installer Started
Log file: $LOG_FILE" | boxes -d ansi-double

pushd /tmp 2>/dev/null || { echo "Cannot cd to /tmp"; exit 1; }

# Try multiple ways to get IPv4
IPV4=$(hostname -I 2>/dev/null | awk '{print $1}')

# If that fails, try another method
if [ -z "$IPV4" ]; then
    IPV4=$(ip -4 addr show 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v 127.0.0.1 | head -1)
fi

# If still empty, use a placeholder
if [ -z "$IPV4" ]; then
    IPV4="(waiting for network)"
fi

log_output "Detected IPv4: $IPV4" | boxes -d ansi-double

# Ensure qrencode is installed
QRENCODE_AVAILABLE=true
if ! command -v qrencode &> /dev/null; then
    log_output "WARNING: qrencode not found. Attempting to install..." | boxes -d ansi-double
    if ! sudo dnf install -y qrencode &> /dev/null; then
        log_output "WARNING: qrencode installation failed. QR code will not be generated." | boxes -d ansi-double
        QRENCODE_AVAILABLE=false
    else
        log_output "qrencode installed successfully" | boxes -d ansi-double
    fi
else
    log_output "qrencode found" | boxes -d ansi-double
fi

log_output "Stopping Digital Reef services..." | boxes -d ansi-double
SYSTEMD_LOG_LEVEL=debug systemctl stop drd drd-wildfly 2>/dev/null || log_output "Services already stopped or not running" | boxes -d ansi-double

log_output "Copying license file..." | boxes -d ansi-double
if [ -f license.lic ]; then
    \cp -v license.lic /tmp/license.lic 2>/dev/null || log_output "Warning: license.lic copy failed" | boxes -d ansi-double
else
    log_output "Warning: license.lic not found in current directory" | boxes -d ansi-double
fi

log_output "Cleaning up previous installations..." | boxes -d ansi-double
rm -rfv /home/auraria/AHS* 2>/dev/null || true
rm -rfv /var/.com.zerog.registry.xml 2>/dev/null || true
rm -rfv /tmp/cbe* 2>/dev/null || true

export LAX_DEBUG=true
export _JAVA_OPTIONS="-Dlax.debug.level=3 -Dlax.debug.all=true"

# Find the highest version 5.5.3.0 binary
BINARY=$(ls -1 /tmp/5.5.3.0-*.bin 2>/dev/null | sort -V | tail -1)

if [ -z "$BINARY" ]; then
    log_output "Error: No installer binary found matching pattern 5.5.3.0-*.bin" | boxes -d ansi-double
    exit 1
fi

echo "Using installer: $BINARY" | boxes -d ansi-double

# Get the IP address for installation
INSTALL_IP=$(ip route get 1 2>/dev/null | awk '{print $7; exit}')

if [ -z "$INSTALL_IP" ]; then
    INSTALL_IP="$IPV4"
fi

echo "Starting installation with IP: $INSTALL_IP" | boxes -d ansi-double
echo "Running: $BINARY -i silent -DNODETYPE=full -DREALMNAME=TheReef -DIPADDRESS=$INSTALL_IP -DDATABASE_IP=$INSTALL_IP -DEXPFS=1" | boxes -d ansi-double

# Run the installer
"$BINARY" \
    -i silent -DNODETYPE=full \
    -DREALMNAME=TheReef \
    -DIPADDRESS="$INSTALL_IP" \
    -DDATABASE_IP="$INSTALL_IP" \
    -DEXPFS=1

INSTALL_EXIT_CODE=$?
echo "Installer exit code: $INSTALL_EXIT_CODE" | boxes -d ansi-double

# Get Host ID if hostid.sh exists
if [ -f /home/auraria/AHS/bin/hostid.sh ]; then
    export HOST_ID=$(/home/auraria/AHS/bin/hostid.sh -g 2>/dev/null | tail -n 1 | awk '{print $5}')
    echo "Host ID retrieved: $HOST_ID" | boxes -d ansi-double
    
    # Ask user if they want to run cleandr.sh
    if [ -f /root/scripts/cleandr.sh ]; then
        read -p "Would you like to run /root/scripts/cleandr.sh? (y/n): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Running cleandr.sh..." | boxes -d ansi-double
            /root/scripts/cleandr.sh
        fi
    fi
else
    echo "Warning: /home/auraria/AHS/bin/hostid.sh not found" | boxes -d ansi-double
    HOST_ID="UNKNOWN"
fi

# Calculate installation time
END_TIME=$(date +%s)
INSTALL_DURATION=$((END_TIME - START_TIME))
INSTALL_HOURS=$((INSTALL_DURATION / 3600))
INSTALL_MINUTES=$(((INSTALL_DURATION % 3600) / 60))
INSTALL_SECONDS=$((INSTALL_DURATION % 60))

# Prepare output
OUTPUT=""
OUTPUT+="Installation Time: ${INSTALL_HOURS}h ${INSTALL_MINUTES}m ${INSTALL_SECONDS}s\n"
OUTPUT+="Host ID: $HOST_ID\n"

# Add system info if script exists
if [ -f /root/scripts/drsysinfo.sh ]; then
    echo "Retrieving system information..." | boxes -d ansi-double
    OUTPUT+="System Information:\n"
    OUTPUT+=$(/root/scripts/drsysinfo.sh 2>/dev/null | sed 's/^/  /')
    OUTPUT+="\n"
fi

# Generate QR code if qrencode is available
if [ "$QRENCODE_AVAILABLE" = true ]; then
    QR_BODY="$(hostname) $HOST_ID $IPV4"
    QR_CODE=$(qrencode -t ANSIUTF8 "mailto:DRLicense@digitalreefinc.com?subject=Automated_License_Request&body=$QR_BODY" 2>/dev/null)
    
    OUTPUT+="License Request QR Code:\n"
    OUTPUT+="$QR_CODE\n\n"
    OUTPUT+="Scan the above QR code to easily obtain your license id on a mobile device.\n\n"
else
    OUTPUT+="License Request:\n"
    OUTPUT+="\033[1;34mEmail: DRLicense@digitalreefinc.com\033[0m\n"
    OUTPUT+="\033[1;34mSubject: Automated_License_Request\033[0m\n"
    OUTPUT+="\033[1;34mBody: $(hostname) $HOST_ID $IPV4\033[0m\n\n"
fi

OUTPUT+="Digital Reef URL: https://${INSTALL_IP}:8443\n"

# Display final results with boxes
echo ""
echo -e "$OUTPUT" | boxes -d ansi-double
echo ""

# Completion banner
echo "Installation Complete
Log file saved to: $LOG_FILE" | boxes -d ansi-double

popd