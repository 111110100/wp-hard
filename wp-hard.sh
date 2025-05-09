#!/bin/bash

# Harden WordPress install
# Usage: ./harden_wp.sh /path/to/wordpress

set -e

WP_PATH="$1"

if [[ -z "$WP_PATH" || ! -d "$WP_PATH" ]]; then
  echo "Usage: $0 /path/to/wordpress"
  exit 1
fi

echo "[+] Starting WordPress hardening in: $WP_PATH"

# Set ownership (assumes www-data; adjust as needed)
chown -R www-data:www-data "$WP_PATH"

# Set directory permissions to 755
find "$WP_PATH" -type d -exec chmod 755 {} \;

# Set file permissions to 644
find "$WP_PATH" -type f -exec chmod 644 {} \;

# Harden wp-config.php
chmod 600 "$WP_PATH/wp-config.php"
chown root:root "$WP_PATH/wp-config.php"

# Disable PHP execution in uploads and includes
for DIR in "$WP_PATH/wp-content/uploads" "$WP_PATH/wp-includes"; do
  if [[ -d "$DIR" ]]; then
    cat > "$DIR/.htaccess" <<EOF
<FilesMatch "\.php$">
  Order Deny,Allow
  Deny from all
</FilesMatch>
EOF
  fi
done

# Disable access to sensitive files
cat > "$WP_PATH/.htaccess" <<EOF
<FilesMatch "^(wp-config\.php|readme\.html|license\.txt|error_log|.htaccess)$">
  Order allow,deny
  Deny from all
</FilesMatch>

# Disable directory listing
Options -Indexes

# Protect .htaccess itself
<Files .htaccess>
  Order allow,deny
  Deny from all
</Files>

# Optional: disable XML-RPC
#<Files xmlrpc.php>
#  Order allow,deny
#  Deny from all
#</Files>
EOF

echo "[+] Permissions and .htaccess security rules applied."

# Optional: disable file editing from the WordPress dashboard
if ! grep -q "DISALLOW_FILE_EDIT" "$WP_PATH/wp-config.php"; then
  echo "define('DISALLOW_FILE_EDIT', true);" >> "$WP_PATH/wp-config.php"
  echo "[+] Disabled theme/plugin editing via wp-admin."
fi

echo "[✓] WordPress hardening complete."

