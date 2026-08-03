#!/usr/bin/env bash
set -u

ALFS="/opt/homebrew/bin/anylinuxfs"

pause() {
  echo
  read -r -p "按回车键关闭..."
}

ntfs_name_for() {
  diskutil info "$1" 2>/dev/null | awk -F': *' '/Volume Name:/ { print $2; exit }'
}

if [[ ! -x "$ALFS" ]]; then
  echo "没有找到 anylinuxfs: $ALFS"
  echo "请先安装: brew tap nohajc/anylinuxfs && brew install anylinuxfs"
  pause
  exit 1
fi

disks=()
while IFS= read -r disk; do
  [[ -n "$disk" ]] && disks+=("$disk")
done < <(diskutil list external physical | awk '/Windows_NTFS/ { print "/dev/" $NF }')

if [[ "${#disks[@]}" -eq 0 ]]; then
  echo "没有检测到外接 NTFS 分区。"
  echo "请确认硬盘已经插入，并且分区类型是 Windows_NTFS。"
  pause
  exit 1
fi

echo "检测到 ${#disks[@]} 个外接 NTFS 分区，将自动挂载为读写："
for disk in "${disks[@]}"; do
  name="$(ntfs_name_for "$disk")"
  echo "  $disk ${name:+($name)}"
done

echo
echo "如果提示 Password，请输入你的 Mac 登录密码。"
echo

for disk in "${disks[@]}"; do
  name="$(ntfs_name_for "$disk")"
  echo "正在挂载 $disk ${name:+($name)} ..."
  sudo "$ALFS" mount "$disk" --remount --ignore-permissions
  echo
done

echo "完成。当前 anylinuxfs 状态："
"$ALFS" status || true
pause
