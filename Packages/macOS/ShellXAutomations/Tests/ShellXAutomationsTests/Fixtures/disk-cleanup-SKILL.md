---
name: disk-cleanup
description: Check disk usage on macOS and safely free up space when the disk is full. Use when the user says the disk is full or asks what takes space. Always measures and reports first, then deletes only what the user approves.
---

# Disk cleanup

1. Measure the disk with `df -h /` and note the free space.
2. Measure the usual cache folders with `du -sh`: Xcode DerivedData, the iOS Simulator devices, the npm cache, the Homebrew cache and Docker.
3. Report what takes space, largest first. Do not delete anything yet.
4. Ask the user which of these items to delete, and wait for the answer.
5. Delete only the items the user approved. If they approved nothing, stop here.
6. Measure the disk again with `df -h /` and report how much space was freed.
