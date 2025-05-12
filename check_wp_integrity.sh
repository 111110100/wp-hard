#!/bin/bash

# WordPress Integrity Check Script
# Usage: ./check_wp_integrity.sh /path/to/wordpress

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

set -e

WP_PATH="$1"
LOG_DIR="/var/log/wp-checks"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="$LOG_DIR/wp-check-$TIMESTAMP.log"

if [[ -z "$WP_PATH" || ! -d "$WP_PATH" ]]; then
  echo "Usage: $0 /path/to/wordpress"
  exit 1
fi

if [[ ! -f "$WP_PATH/wp-config.php" && ! -d "$WP_PATH/wp-content" && ! -d "$WP_PATH/wp-includes" && ! -d "$WP_PATH/wp-admin" ]]; then
  echo "[ERROR] $WP_PATH does not appear to be a WordPress installation."
  exit 1
fi

echo "[+] Starting WordPress check in: $WP_PATH"
mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

cd "$WP_PATH"

echo "WordPress Security Check Log - $TIMESTAMP" >> "$LOG_FILE"
echo "Scanning path: $WP_PATH" >> "$LOG_FILE"

# Check if WP-CLI is installed
if ! command -v wp &> /dev/null; then
  echo "[ERROR] wp-cli not found in PATH." | tee -a "$LOG_FILE"
  exit 1
fi

echo "[+] Checking directory permissios"
# Check incorrect directory permissions
find "$WP_PATH" -type d ! -perm 755 -print | while read -r line; do
  echo "[PERM] Directory not 755: $line" >> "$LOG_FILE"
done

# Check incorrect file permissions
find "$WP_PATH" -type f ! -perm 644 ! -name 'wp-config.php' ! -name '.htaccess' -print | while read -r line; do
  echo "[PERM] File not 644: $line" >> "$LOG_FILE"
done

echo "[+] Checking permissions of wp-config.php, .htaccess"
# wp-config.php
if [[ -f wp-config.php ]]; then
  STAT=$(stat -L -c "%a" wp-config.php)
  [[ "$STAT" != "644" ]] && echo "[PERM] wp-config.php is $STAT, expected 644" >> "$LOG_FILE"
fi

# .htaccess
if [[ -f .htaccess ]]; then
  STAT=$(stat -c "%a" .htaccess)
  [[ "$STAT" -gt 644 ]] && echo "[PERM] .htaccess is $STAT, too open" >> "$LOG_FILE"
fi

echo "[+] Scanning for suspicious PHP functions"
# Scan for suspicious PHP functions
find "$WP_PATH" -type f -name "*.php" -exec awk '
/\b(base64_decode|eval|gzinflate|str_rot13|system|shell_exec|passthru)\s*\(/ {
  if ($0 ~ /^\s*(\/\/|#)/) next
  if ($0 ~ /\/\*.*\b(base64_decode|eval|gzinflate|str_rot13|system|shell_exec|passthru)\s*\(.*\*\//) next
  print "[MALWARE] " FILENAME ":" FNR ": " $0
}' {} + 2>/dev/null >> "$LOG_FILE"

echo "[+] Checking core file integrity"
# Core file integrity
if ! wp core verify-checksums --quiet --skip-plugins; then
  echo "[CORE] WordPress core integrity check FAILED" >> "$LOG_FILE"
fi

echo "[+] Checking plugin integrity"
# Plugin integrity
PLUGINS=$(wp plugin list --field=name --skip-plugins)

for plugin in $PLUGINS; do
  if ! wp plugin verify-checksums "$plugin" --quiet --skip-plugins &>/dev/null; then
    echo "[PLUGIN] Checksum FAIL: $plugin" >> "$LOG_FILE"
  fi
done

# Final note
echo "[✓] WordPress integrity check complete."
echo "Log saved: $LOG_FILE"
