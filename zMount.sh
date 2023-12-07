#!/bin/bash
#Steam Deck Mount External Drive by scawp
#License: DBAD: https://github.com/scawp/Steam-Deck.Mount-External-Drive/blob/main/LICENSE.md
#Source: https://github.com/scawp/Steam-Deck.Mount-External-Drive
# Use at own Risk!

script_dir="$(dirname $(realpath "$0"))"
tmp_dir="/tmp/scawp.SDMED.zMount"

mkdir -p "$tmp_dir"

external_drive_list="$tmp_dir/external_drive_list.txt"

#TODO this is to force kdesu dialog to use sudo, maybe theres a better way?
if [ ! -f ~/.config/kdesurc ];then
  touch ~/.config/kdesurc
  echo "[super-user-command]" > ~/.config/kdesurc
  echo "super-user-command=sudo" >> ~/.config/kdesurc
fi

function list_gui () {
  IFS=$'[\t|\n]';
  selected_device=$(zenity --list --title="Select Drive to (un)Mount" \
    --width=1000 --height=360 --print-column=1 --separator="\t" \
    --ok-label "(Un)Mount" --extra-button "Refresh" \
    --column="Path" --column="Size" --column="UUID" \
    --column="Mount Point" --column="Label" --column="File System" \
    $(cat "$external_drive_list"))
  ret_value="$?"
  unset IFS;
}

function confirm_gui () {
  zenity --question --width=400 \
    --text="Do you want to $1 device $2 with uuid of $3?"

  if [ "$?" = 1 ]; then
    exit 1;
  fi
}

function get_drive_list () {
  #Overkill? Perhaps, but Zenity (or I) was struggling with Splitting
  lsblk -PoHOTPLUG,PATH,SIZE,UUID,MOUNTPOINT,LABEL,FSTYPE | grep '^HOTPLUG="1"' | grep -v 'UUID=\"\"' | sed -e 's/^HOTPLUG=\"1\"\sPATH=\"//' -e 's/\"\"/\" \"/g' -e 's/\"\s[A-Z]*=\"/\t/g' -e 's/\"$//' | tee "$external_drive_list"
}

function sudo_mount_drive () {
  if [ "$1" = "mount" ]; then
    kdesu -c "udisksctl mount -b \"/dev/disk/by-uuid/$2\" 2> $tmp_dir/last_error.log 1> $tmp_dir/last_msg.log"
  else
    kdesu -c "udisksctl unmount -b \"/dev/disk/by-uuid/$2\" 2> $tmp_dir/last_error.log 1> $tmp_dir/last_msg.log"
  fi

  if [ "$?" != 0 ]; then
    ret_value="$(sed -n '1p' $tmp_dir/last_error.log)"
    ret_success=0
  else
    ret_value="$(sed -n '1p' $tmp_dir/last_msg.log)"
    ret_success=1
  fi
}

function mount_drive () {
  if [ "$1" = "mount" ]; then
    udisksctl mount --no-user-interaction -b "/dev/disk/by-uuid/$2" 2> $tmp_dir/last_error.log 1> $tmp_dir/last_msg.log
  else
    udisksctl unmount --no-user-interaction -b "/dev/disk/by-uuid/$2" 2> $tmp_dir/last_error.log 1> $tmp_dir/last_msg.log
  fi

  if [ "$?" != 0 ]; then
    ret_value="$(sed -n '1p' $tmp_dir/last_error.log)"
    sudo_mount_drive $1 $2
  else
    ret_value="$(sed -n '1p' $tmp_dir/last_msg.log)"
    ret_success=1
  fi
}

function addlibraryfolder() {

  # From https://gist.github.com/HazCod/da9ec610c3d50ebff7dd5e7cac76de05
urlencode()
{
    [ -z "$1" ] || echo -n "$@" | hexdump -v -e '/1 "%02x"' | sed 's/\(..\)/%\1/g'
}

  mount_point="$(lsblk -noMOUNTPOINT $1)"
  if [ -z "$mount_point" ];then
    zenity --error --width=400 \
    --text="Failed to mount "$1" at /run/media/deck/$label"
  else
    echo "Mounted "$1" at $mount_point"
    mount_point="$mount_point/SteamLibrary"
    zenity --info --width=400 \
    --text="Steam to add $mount_point"
    #Below Stolen from /usr/lib/hwsupport/sdcard-mount.sh
    url=$(urlencode "${mount_point}")

    # If Steam is running, notify it
    if pgrep -x "steam" > /dev/null; then
        # TODO use -ifrunning and check return value - if there was a steam process and it returns -1, the message wasn't sent
        # need to retry until either steam process is gone or -ifrunning returns 0, or timeout i guess
        systemd-run -M 1000@ --user --collect --wait sh -c "steam steam://addlibraryfolder/${url@Q}"
    fi
  fi
}

function main () {
  get_drive_list
  list_gui
  mount_point="$(lsblk -noMOUNTPOINT $selected_device)"
  uuid="$(lsblk -noUUID $selected_device)"

  if [ "$ret_value" = 1 ]; then
    if [ "$selected_device" = "Refresh" ]; then
      main
    else
      if [ "$selected_device" = "Auto Mount" ]; then
        continue
      else
        exit 1;
      fi
    fi
  fi

  if [ "$selected_device" = "" ]; then
    zenity --error --width=400 \
    --text="No Device Selected, Quitting!"
    exit 1;
  fi

  if [ "$mount_point" = "" ]; then
    confirm_gui "mount" "$selected_device" "$uuid"
    mount_drive "mount" "$uuid"
    if [ "$ret_success" = 1 ]; then
      # notify steam to add library folder
      addlibraryfolder "$selected_device"
    fi
  else
    confirm_gui "unmount" "$selected_device" "$uuid"
    mount_drive "unmount" "$uuid"
  fi

  zenity --info --width=400 \
    --text="$ret_value"

  exit 0;
}

main
