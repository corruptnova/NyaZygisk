#!/system/bin/sh

export TMP_PATH=@WORK_DIRECTORY@

# The work directory may be a tmpfs the init script mounted as a fallback when it could not
# relabel the /dev directory to system_file. Drop that mount first (best effort, a no-op
# when nothing is mounted there) so the directory below it can be removed rather than left
# as an empty mountpoint until the next reboot clears /dev.
umount "$TMP_PATH" 2>/dev/null

rm -rf $TMP_PATH
