#!/bin/bash

# Harden WordPress install
# Usage: ./wp-hard.sh /path/to/wordpress

if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root"
   exit 1
fi

set -e

WP_PATH="$1"

if [[ -z "$WP_PATH" || ! -d "$WP_PATH" ]]; then
  echo "Usage: $0 /path/to/wordpress"
  exit 1
fi

if [[ ! -f "$WP_PATH/wp-config.php" && ! -d "$WP_PATH/wp-content" && ! -d "$WP_PATH/wp-includes" && ! -d "$WP_PATH/wp-admin" ]]; then
  echo "[ERROR] $WP_PATH does not appear to be a WordPress installation."
  exit 1
fi

echo "[+] Starting WordPress hardening in: $WP_PATH"

# Set ownership (assumes www-data; adjust as needed)
chown -R bitnami:daemon "$WP_PATH"
chown -R bitnami:daemon "$WP_PATH/wp-content/"
chown -R daemon:daemon "$WP_PATH/wp-content/upgrade"
chown -R daemon:daemon "$WP_PATH/wp-content/plugins"
chown -R daemon:daemon "$WP_PATH/wp-content/uploads"
chown -R daemon:daemon "$WP_PATH/wp-content/themes"
[ -d "$WP_PATH/wp-content/ai1wm-backups" ] && chown -R daemon:daemon "$WP_PATH/wp-content/ai1wm-backups"
[ -d "$WP_PATH/wp-content/upgrade-temp-backup" ] && chown -R daemon:daemon "$WP_PATH/wp-content/upgrade-temp-backup"

# Set directory permissions to 755
find "$WP_PATH" -type d -exec chmod 755 {} \;
find "$WP_PATH/wp-content/" -type d -exec chmod 755 {} \;

# Set file permissions to 644
find "$WP_PATH" -type f -exec chmod 644 {} \;
find "$WP_PATH/wp-content/" -type f -exec chmod 644 {} \;

# Harden wp-config.php
chmod 644 "$WP_PATH/wp-config.php"
chown root:root "$WP_PATH/wp-config.php"

# Disable PHP execution in uploads and includes
for DIR in "$WP_PATH/wp-content/uploads" "$WP_PATH/wp-includes" "$WP_PATH/wp-content/upgrade" "$WP_PATH/wp-content/upgrade-temp-backup"; do
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
[ -f "$WP_PATH/.htaccess" ] && mv "$WP_PATH/.htaccess" "$WP_PATH/.htaccess.bak"
cat > "$WP_PATH/.htaccess" <<EOF
# BEGIN WordPress
# The directives (lines) between "BEGIN WordPress" and "END WordPress" are
# dynamically generated, and should only be modified via WordPress filters.
# Any changes to the directives between these markers will be overwritten.
# <IfModule mod_rewrite.c>
RewriteEngine On
RewriteRule .* - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %{REQUEST_FILENAME} !-f
RewriteCond %{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress

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
