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
# Two paths, because Git Bash on Windows ships no rsync and this is the machine
# the site is actually built on. Both replace the directory wholesale rather than
# merging into it: everything under public/ is generated from this repo, nothing
# else writes there, and a file deleted locally must not survive on the server.
if command -v rsync >/dev/null 2>&1; then
  rsync -az --delete -e "ssh -i $KEY -o StrictHostKeyChecking=no" \
    "$LOCAL_ROOT/public/" "$HOST:$REMOTE_ROOT/public/"
else
  echo "    (no rsync — streaming a tar instead)"
  # Unpack beside the live directory and swap, so a half-finished upload never
  # becomes a half-served site. The swap is two renames and nginx follows the
  # path, not an inode, so it picks up the new tree without a reload.
  tar -cz -C "$LOCAL_ROOT/public" . \
    | ssh -i "$KEY" -o StrictHostKeyChecking=no "$HOST" \
        "sudo rm -rf $REMOTE_ROOT/.incoming && sudo mkdir -p $REMOTE_ROOT/.incoming && sudo tar -xz -C $REMOTE_ROOT/.incoming"
  ssh_run "sudo rm -rf $REMOTE_ROOT/.previous"
  ssh_run "if [ -d $REMOTE_ROOT/public ]; then sudo mv $REMOTE_ROOT/public $REMOTE_ROOT/.previous; fi"
  ssh_run "sudo mv $REMOTE_ROOT/.incoming $REMOTE_ROOT/public"
  ssh_run "sudo rm -rf $REMOTE_ROOT/.previous"
fi

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

  # ⚠️ Roll back on a failed test, do not just stop.
  #
  # `nginx -t` tests the whole configuration, so a candidate file has to be
  # installed before it can be checked — there is no way to test one vhost in
  # isolation. That means a failure leaves the BROKEN file in sites-available,
  # which sites-enabled symlinks to. The running nginx is unaffected, so the site
  # stays up and it looks harmless — but the next reload from any source fails,
  # and the likeliest source is certbot's renewal hook, weeks later, with nobody
  # watching. That is how a config typo becomes an expired certificate.
  #
  # This happened on 2026-08-13: `http2 on;` needs nginx 1.25.1+ and this box runs
  # 1.24. The test caught it and the script stopped, correctly leaving the live
  # site alone — and left the bad file behind.
  if ! ssh_run "sudo nginx -t"; then
    echo "    !! nginx -t failed — restoring the previous vhost"
    ssh_run "sudo cp /etc/nginx/sites-available/webshield.online.bak-$STAMP /etc/nginx/sites-available/webshield.online"
    ssh_run "sudo nginx -t"
    echo "    previous vhost restored; nothing was reloaded. Fix deploy/webshield.online.conf and re-run."
    exit 1
  fi

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
