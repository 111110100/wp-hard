#!/bin/bash

# Usage: ./check_wp_integrity.sh /path/to/wordpress

set -e

WP_PATH="$1"

if [[ -z "$WP_PATH" || ! -d "$WP_PATH" ]]; then
  echo "Usage: $0 /path/to/wordpress"
  exit 1
fi

cd "$WP_PATH"

echo "=== WordPress Security Check ==="

# Check if WP-CLI is installed
if ! command -v wp &> /dev/null; then
  echo "[!] wp-cli is not installed or not in PATH"
  exit 1
fi

echo "[*] Checking file and directory permissions..."

# Incorrect directory permissions
find "$WP_PATH" -type d ! -perm 755 -print

# Incorrect file permissions
find "$WP_PATH" -type f ! -perm 644 ! -name 'wp-config.php' ! -name '.htaccess' -print

# Check wp-config.php permissions
if [[ -f wp-config.php ]]; then
  STAT=$(stat -c "%a" wp-config.php)
  if [[ "$STAT" != "600" ]]; then
    echo "[!] wp-config.php permissions are not 600 (currently $STAT)"
  fi
fi

# Check .htaccess permissions
if [[ -f .htaccess ]]; then
  STAT=$(stat -c "%a" .htaccess)
  if [[ "$STAT" -gt 644 ]]; then
    echo "[!] .htaccess permissions are too open (currently $STAT)"
  fi
fi

echo "[*] Scanning for suspicious PHP code..."
find "$WP_PATH" -type f -name "*.php" -exec grep -lE "(base64_decode|eval|gzinflate|str_rot13|system|shell_exec|passthru)" {} \; 2>/dev/null || echo "[✓] No suspicious PHP functions found."

echo "[*] Verifying core WordPress files..."
if ! wp core verify-checksums --path="$WP_PATH"; then
  echo "[!] WordPress core integrity check failed!"
else
  echo "[✓] Core files OK."
fi

echo "[*] Checking plugin integrity..."
PLUGINS=$(wp plugin list --path="$WP_PATH" --field=name)

for plugin in $PLUGINS; do
  echo " - Checking: $plugin"
  if ! wp plugin verify-checksums "$plugin" --path="$WP_PATH" &>/dev/null; then
    echo "   [!] Plugin $plugin failed checksum verification."
  fi
done

echo "[✓] WordPress security check complete."

