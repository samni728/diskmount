#!/usr/bin/env bash
set -u

ALFS="/opt/homebrew/bin/anylinuxfs"

pause() {
  echo
  read -r -p "按回车键继续..."
}

need_anylinuxfs() {
  if [[ ! -x "$ALFS" ]]; then
    echo "没有找到 anylinuxfs: $ALFS"
    echo "请先安装: brew tap nohajc/anylinuxfs && brew install anylinuxfs"
    pause
    exit 1
  fi
}

ntfs_name_for() {
  diskutil info "$1" 2>/dev/null | awk -F': *' '/Volume Name:/ { print $2; exit }'
}

list_external_ntfs() {
  diskutil list external physical | awk '/Windows_NTFS/ { print "/dev/" $NF }'
}

list_all_ntfs() {
  diskutil list | awk '/Windows_NTFS/ { print "/dev/" $NF }'
}

print_candidates() {
  local disk name mounted mount_point
  for disk in "$@"; do
    name="$(ntfs_name_for "$disk")"
    mounted="$(diskutil info "$disk" 2>/dev/null | awk -F': *' '/Mounted:/ { print $2; exit }')"
    mount_point="$(diskutil info "$disk" 2>/dev/null | awk -F': *' '/Mount Point:/ { print $2; exit }')"
    printf "  %s  %s" "$disk" "${name:-未命名NTFS}"
    if [[ "$mounted" == "Yes" && -n "$mount_point" ]]; then
      printf "  当前挂载: %s" "$mount_point"
    fi
    echo
  done
}

load_candidates() {
  local source="$1"
  candidates=()
  local disk

  if [[ "$source" == "external" ]]; then
    while IFS= read -r disk; do
      [[ -n "$disk" ]] && candidates+=("$disk")
    done < <(list_external_ntfs)
  else
    while IFS= read -r disk; do
      [[ -n "$disk" ]] && candidates+=("$disk")
    done < <(list_all_ntfs)
  fi
}

mount_one() {
  local disk="$1"
  local driver="${2:-default}"
  local name
  name="$(ntfs_name_for "$disk")"

  echo
  echo "准备挂载: $disk ${name:+($name)}"
  echo "如果提示 Password，请输入你的 Mac 登录密码。"
  echo

  if [[ "$driver" == "default" ]]; then
    sudo "$ALFS" mount "$disk" --remount --ignore-permissions
  else
    sudo "$ALFS" mount "$disk" --remount --ignore-permissions -t "$driver"
  fi
}

auto_mount_external() {
  local driver="${1:-default}"
  local candidates=()
  load_candidates external

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    echo "没有检测到外接 NTFS 分区。"
    echo
    echo "下面是所有 NTFS 分区，避免误挂内部磁盘，请手动确认："
    load_candidates all
    if [[ "${#candidates[@]}" -eq 0 ]]; then
      echo "没有检测到 NTFS 分区。"
      pause
      return
    fi
    print_candidates "${candidates[@]}"
    pause
    return
  fi

  if [[ "${#candidates[@]}" -eq 1 ]]; then
    mount_one "${candidates[0]}" "$driver"
  else
    echo "检测到多个外接 NTFS 分区，将逐个挂载："
    print_candidates "${candidates[@]}"
    echo
    read -r -p "确认全部挂载？输入 y 继续: " yes
    [[ "$yes" == "y" || "$yes" == "Y" ]] || return
    for disk in "${candidates[@]}"; do
      mount_one "$disk" "$driver"
    done
  fi

  echo
  echo "当前 anylinuxfs 状态:"
  "$ALFS" status || true
  pause
}

manual_mount() {
  local driver="${1:-default}"
  local candidates=()
  local choice disk
  load_candidates all

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    echo "没有检测到 NTFS 分区。"
    pause
    return
  fi

  echo "请选择要挂载的 NTFS 分区："
  local i=1
  for disk in "${candidates[@]}"; do
    printf "%d) " "$i"
    print_candidates "$disk"
    i=$((i + 1))
  done
  echo
  read -r -p "请输入序号: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#candidates[@]} )); then
    echo "无效选择。"
    pause
    return
  fi

  disk="${candidates[$((choice - 1))]}"
  mount_one "$disk" "$driver"
  echo
  "$ALFS" status || true
  pause
}

unmount_menu() {
  local candidates=()
  local choice disk
  load_candidates all

  if [[ "${#candidates[@]}" -eq 0 ]]; then
    echo "没有检测到 NTFS 分区。"
    pause
    return
  fi

  echo "请选择要卸载的 NTFS 分区："
  local i=1
  for disk in "${candidates[@]}"; do
    printf "%d) " "$i"
    print_candidates "$disk"
    i=$((i + 1))
  done
  echo
  read -r -p "请输入序号: " choice

  if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#candidates[@]} )); then
    echo "无效选择。"
    pause
    return
  fi

  disk="${candidates[$((choice - 1))]}"
  echo
  sudo "$ALFS" unmount "$disk"
  echo
  "$ALFS" status || true
  pause
}

open_first_volume() {
  local candidates=()
  local disk name mount_point
  load_candidates external

  for disk in "${candidates[@]}"; do
    mount_point="$(diskutil info "$disk" 2>/dev/null | awk -F': *' '/Mount Point:/ { print $2; exit }')"
    name="$(ntfs_name_for "$disk")"
    if [[ -d "$mount_point" ]]; then
      open "$mount_point"
      return
    elif [[ -n "$name" && -d "/Volumes/$name" ]]; then
      open "/Volumes/$name"
      return
    fi
  done

  echo "没有找到已挂载的外接 NTFS 卷。"
  "$ALFS" status || true
  pause
}

show_header() {
  clear
  echo "anylinuxfs NTFS 自动读写挂载菜单"
  echo
  echo "外接 NTFS 分区:"
  local candidates=()
  load_candidates external
  if [[ "${#candidates[@]}" -eq 0 ]]; then
    echo "  暂未检测到"
  else
    print_candidates "${candidates[@]}"
  fi
  echo
}

need_anylinuxfs

while true; do
  show_header
  echo "1) 自动挂载外接 NTFS 为读写，默认 ntfs-3g，兼容性更稳"
  echo "2) 自动挂载外接 NTFS 为读写，ntfs3，速度更快"
  echo "3) 手动选择 NTFS 分区挂载"
  echo "4) 卸载 NTFS"
  echo "5) 查看 anylinuxfs 状态"
  echo "6) 查看可用 Microsoft/NTFS 分区"
  echo "7) 在 Finder 打开第一个外接 NTFS 卷"
  echo "0) 退出"
  echo
  read -r -p "请选择: " choice

  case "$choice" in
    1) auto_mount_external default ;;
    2) auto_mount_external ntfs3 ;;
    3) manual_mount default ;;
    4) unmount_menu ;;
    5) "$ALFS" status; pause ;;
    6) "$ALFS" list -m; pause ;;
    7) open_first_volume ;;
    0) exit 0 ;;
    *) echo "无效选择。"; pause ;;
  esac
done
