#!/usr/bin/env bash
#
# Push the static site to the production VM.
#
#   ./deploy/deploy.sh            # upload public/ and reload nothing
#   ./deploy/deploy.sh --nginx    # also install the vhost and reload nginx
#
# Deliberately not clever. It rsyncs a directory and, optionally, replaces one
# nginx file. Everything it does is reversible and it never touches WordPress,
# its database, or its container.
#
# Prerequisites:
#   * the SSH key at ~/.ssh/ws.pem, mode 600 (OpenSSH rejects the 644 original
#     at "C:\dev\Webshield Cert\PKI\Webshield_Online_PK.pem" — copy it first)
#   * the jeremyl account, which has passwordless sudo. The `claude` account can
#     SSH but cannot sudo, and every path here is root-owned.
set -euo pipefail

HOST="${WEBSHIELD_HOST:-jeremyl@20.164.230.236}"
KEY="${WEBSHIELD_KEY:-$HOME/.ssh/ws.pem}"
REMOTE_ROOT="/opt/webshield-site"
LOCAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

WITH_NGINX=0
[[ "${1:-}" == "--nginx" ]] && WITH_NGINX=1

ssh_run() { ssh -i "$KEY" -o StrictHostKeyChecking=no "$HOST" "$@"; }

echo "==> checking the bundle is built"
for required in public/index.html public/privacy.html public/assets/css/site.css \
                public/assets/js/site.js public/assets/img/family-band.webp; do
  [[ -f "$LOCAL_ROOT/$required" ]] || { echo "missing $required — run tools/build-images.py?"; exit 1; }
done

echo "==> preparing $REMOTE_ROOT"
ssh_run "sudo mkdir -p $REMOTE_ROOT/public && sudo chown -R \$(id -u):\$(id -g) $REMOTE_ROOT"

echo "==> uploading public/"
# --delete so a file removed locally goes away on the server too; the whole
# directory is generated from this repo and nothing else writes into it.
rsync -az --delete -e "ssh -i $KEY -o StrictHostKeyChecking=no" \
  "$LOCAL_ROOT/public/" "$HOST:$REMOTE_ROOT/public/"

echo "==> handing it to nginx's user"
ssh_run "sudo chown -R www-data:www-data $REMOTE_ROOT && sudo chmod -R a+rX $REMOTE_ROOT"

if [[ $WITH_NGINX -eq 1 ]]; then
  echo "==> installing the vhost"
  # Keep a dated copy of whatever is there now. `nginx -t` is the gate: a bad
  # config is never reloaded, so the worst case is that the old one keeps serving.
  STAMP="$(date +%Y%m%d-%H%M%S)"
  scp -i "$KEY" -o StrictHostKeyChecking=no \
    "$LOCAL_ROOT/deploy/webshield.online.conf" "$HOST:/tmp/webshield.online.conf"
  ssh_run "sudo cp /etc/nginx/sites-available/webshield.online /etc/nginx/sites-available/webshield.online.bak-$STAMP"
  ssh_run "sudo cp /tmp/webshield.online.conf /etc/nginx/sites-available/webshield.online"
  ssh_run "sudo nginx -t"
  ssh_run "sudo systemctl reload nginx"
  echo "    previous vhost kept at /etc/nginx/sites-available/webshield.online.bak-$STAMP"
fi

echo "==> verifying"
for path in / /privacy /assets/css/site.css; do
  code="$(ssh_run "curl -s -o /dev/null -w '%{http_code}' https://webshield.online$path")"
  echo "    $path -> $code"
done
# The one that proves WordPress is still alive behind the static site.
code="$(ssh_run "curl -s -o /dev/null -w '%{http_code}' https://webshield.online/wp-login.php")"
echo "    /wp-login.php -> $code  (WordPress should still answer)"

echo "==> done"
