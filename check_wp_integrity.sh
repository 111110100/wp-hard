#!/bin/bash

# Usage: ./check_wp_integrity.sh /path/to/wordpress

set -e

WP_PATH="$1"
LOG_DIR="/var/log/wp-checks"
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
LOG_FILE="$LOG_DIR/wp-check-$TIMESTAMP.log"

if [[ -z "$WP_PATH" || ! -d "$WP_PATH" ]]; then
  echo "Usage: $0 /path/to/wordpress"
  exit 1
fi

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

# Check incorrect directory permissions
find "$WP_PATH" -type d ! -perm 755 -print | while read -r line; do
  echo "[PERM] Directory not 755: $line" >> "$LOG_FILE"
done

# Check incorrect file permissions
find "$WP_PATH" -type f ! -perm 644 ! -name 'wp-config.php' ! -name '.htaccess' -print | while read -r line; do
  echo "[PERM] File not 644: $line" >> "$LOG_FILE"
done

# wp-config.php
if [[ -f wp-config.php ]]; then
  STAT=$(stat -c "%a" wp-config.php)
  [[ "$STAT" != "600" ]] && echo "[PERM] wp-config.php is $STAT, expected 600" >> "$LOG_FILE"
fi

# .htaccess
if [[ -f .htaccess ]]; then
  STAT=$(stat -c "%a" .htaccess)
  [[ "$STAT" -gt 644 ]] && echo "[PERM] .htaccess is $STAT, too open" >> "$LOG_FILE"
fi

# Scan for suspicious PHP functions
find "$WP_PATH" -type f -name "*.php" -exec grep -lE "(base64_decode|eval|gzinflate|str_rot13|system|shell_exec|passthru)" {} \; 2>/dev/null | while read -r match; do
  echo "[MALWARE] Suspicious PHP: $match" >> "$LOG_FILE"
done

# Core file integrity
if ! wp core verify-checksums --quiet --skip-plugins; then
  echo "[CORE] WordPress core integrity check FAILED" >> "$LOG_FILE"
fi

# Plugin integrity
PLUGINS=$(wp plugin list --field=name)

for plugin in $PLUGINS; do
  if ! wp plugin verify-checksums "$plugin" --quiet --skip-plugins &>/dev/null; then
    echo "[PLUGIN] Checksum FAIL: $plugin" >> "$LOG_FILE"
  fi
done

# Final note
echo "Log saved: $LOG_FILE"
