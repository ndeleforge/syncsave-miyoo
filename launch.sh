#!/bin/sh

###############################################
# Main variables (do not edit)

HOME=/mnt/SDCARD
DISMISS_FLAG="/tmp/dismiss_info_panel"
PADSP="$HOME/miyoo/lib/libpadsp.so"
INFO_PANEL="$HOME/.tmp_update/bin/infoPanel"
DEVICE="/dev/input/event0"

###############################################
# Miyoo variables (do not edit)

APP_FOLDER="$HOME/App/SyncSave"
RCLONE="$APP_FOLDER/rclone"
RCLONE_CONF="$APP_FOLDER/rclone.conf"
RCLONE_LOG="$APP_FOLDER/rclone.log"
PROFILE_FODLER="$HOME/Saves/CurrentProfile"
SCREENSHOT_FOLDER="$HOME/Screenshots"

###############################################
# Cloud settings (edit these variables to match your cloud setup)

CLOUD_HOST=""
CLOUD_PATH=""

###############################################
# Info panel functions

start_info_panel() {
    rm -f "$DISMISS_FLAG"
    LD_PRELOAD="$PADSP" "$INFO_PANEL" -t "SyncSave" -m "$1" --persistent &
    INFO_PANEL_PID=$!
    sleep 1
}

dismiss_info_panel() {
    touch "$DISMISS_FLAG"
    sleep 1
    rm -f "$DISMISS_FLAG"
    unset INFO_PANEL_PID
}

update_info_panel() {
    dismiss_info_panel
    start_info_panel "$1"
}

error_exit() {
    update_info_panel "Error : $1"
    sleep 2
    dismiss_info_panel
    exit 1
}

###############################################
# Checks functions

check_rclone() {
    update_info_panel "Library rclone checks"

    if [ ! -f "$RCLONE" ]; then
        error_exit "rclone is missing"
    elif [ ! -f "$RCLONE_CONF" ]; then
        error_exit "rclone.conf is missing"
    fi
}

check_wifi() {
    if [ -z "$CLOUD_HOST" ]; then
        return 0
    fi

    update_info_panel "Network check"

    ip_address=$(ip addr show wlan0 | awk '/inet / {print $2}' | cut -d/ -f1)
    if [ -z "$ip_address" ]; then
        error_exit "Wi-Fi is disabled"
    fi
}

check_cloud() {
    update_info_panel "Cloud connection check"

    if ! ping -c 1 -W 2 "$CLOUD_HOST" >/dev/null; then
        error_exit "remote is not reachable"
    fi
}

###############################################
# Main functions

# Read input from the device and return button name
read_input() {    
    event=$(dd if="$DEVICE" bs=16 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n')
    if [ -z "$event" ] || [ ${#event} -lt 32 ]; then
        echo ""
        return
    fi

    TYPE_HEX=${event:16:4}
    CODE_HEX=${event:20:4}
    VALUE_HEX=${event:24:8}

    TYPE_DEC=$(( 0x${TYPE_HEX:2:2}${TYPE_HEX:0:2} ))
    CODE_DEC=$(( 0x${CODE_HEX:2:2}${CODE_HEX:0:2} ))
    VALUE_DEC=$(( 0x${VALUE_HEX:6:2}${VALUE_HEX:4:2}${VALUE_HEX:2:2}${VALUE_HEX:0:2} ))

    if [ "$VALUE_DEC" -eq 1 ]; then
        case $CODE_DEC in
            103) echo "UP" ;;
            108) echo "DOWN" ;;
            105) echo "LEFT" ;;
            106) echo "RIGHT" ;;
            57) echo "A" ;;
            29) echo "B" ;;
            42) echo "X" ;;
            56) echo "Y" ;;
            18) echo "L1" ;;
            20) echo "R1" ;;
            15) echo "L2" ;;
            14) echo "R2" ;;
            28) echo "START" ;;
            97) echo "SELECT" ;; 
            114) echo "VOL_DOWN" ;;
            115) echo "VOL_UP" ;;
        esac
    else 
        echo ""
    fi
}

# Sync system time with NTP server
sync_time() {
    update_info_panel "Syncing time"

    # Get the current time from NTP server
    export TZ=UTC-0
    ntpd -N -p 162.159.200.1 &
    sleep 2
    killall ntpd 2>/dev/null

    # Set the system time
    hwclock -w
    sleep 1
}

# Do some checks and launch the sync process
launch_sync() {
    direction="$1"  # "upload" or "download"

    sleep 1
    check_rclone
    check_wifi
    check_cloud
    sync_time
    sync_data "$direction"
}

# Sync data function using rclone
sync_data() {
    direction="$1"  # "upload" or "download"
    
    if [ "$direction" = "upload" ]; then
        # Upload profile
        update_info_panel "Uploading profile..."
        "$RCLONE" copy -P -L --create-empty-src-dirs "$PROFILE_FODLER" "$CLOUD_PATH/Profile" --config "$RCLONE_CONF" 2>"$RCLONE_LOG"
        result_profile=$?

        # Upload screenshots
        update_info_panel "Uploading screenshots..."
        "$RCLONE" copy -P -L --create-empty-src-dirs "$SCREENSHOT_FOLDER" "$CLOUD_PATH/Screenshots" --config "$RCLONE_CONF" 2>>"$RCLONE_LOG"
        result_screen=$?
        
        success_msg="All uploads done successfully!"
        error_msg_profile="Profile upload failed"
        error_msg_screen="Screenshots upload failed"
    else
        # Download profile
        update_info_panel "Downloading profile..."
        "$RCLONE" copy -P -L "$CLOUD_PATH/Profile" "$PROFILE_FODLER" --config "$RCLONE_CONF" 2>"$RCLONE_LOG"
        result_profile=$?

        # Download screenshots
        update_info_panel "Downloading screenshots..."
        "$RCLONE" copy -P -L "$CLOUD_PATH/Screenshots" "$SCREENSHOT_FOLDER" --config "$RCLONE_CONF" 2>>"$RCLONE_LOG"
        result_screen=$?
        
        success_msg="All downloads done successfully!"
        error_msg_profile="Profile download failed"
        error_msg_screen="Screenshots download failed"
    fi

    # Display results
    if [ "$result_profile" -eq 0 ] && [ "$result_screen" -eq 0 ]; then
        update_info_panel "$success_msg"
        sleep 2
        dismiss_info_panel
        exit 0
    elif [ "$result_profile" -ne 0 ]; then
        error_exit "$error_msg_profile"
    elif [ "$result_screen" -ne 0 ]; then
        error_exit "$error_msg_screen"
    else
        error_exit "Unknown error during $direction"
    fi
}

###############################################
# Main script execution

start_info_panel "Starting SyncSave"
sleep 1
update_info_panel "Press a button to make your choice \n\nA : Upload to the cloud\nY : Download on the device\nB : Exit"

while true; do
    input=$(read_input)
    if [ -z "$input" ]; then
        continue
    fi

    case $input in
        B)
            update_info_panel "Exiting SyncSave"
            sleep 1
            dismiss_info_panel
            exit 0
            ;;
        A)
            update_info_panel "Initializing upload..."
            launch_sync upload
            ;;
        Y)
            update_info_panel "Initializing download..."
            launch_sync download
            ;;
    esac
done
