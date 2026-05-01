#!/usr/bin/env bash
# MedUnity Phase-1 finalize — switches backend to gunicorn+systemd and hosts
# privacy/terms under trusmiledentist.in. Idempotent. Run with sudo.
set -euo pipefail

PROJ=/home/drriyazq/medunity
BACKEND=$PROJ/backend

echo "=== 1. Stop nohup runserver ==="
pkill -f "manage.py runserver 0.0.0.0:8009" || true
sleep 1
if pgrep -f "manage.py runserver 0.0.0.0:8009" >/dev/null; then
  pkill -9 -f "manage.py runserver 0.0.0.0:8009" || true
fi
echo "[OK] runserver stopped"

echo ""
echo "=== 2. Install systemd units ==="
cp $BACKEND/deploy/medunity-backend.service /etc/systemd/system/
cp $BACKEND/deploy/medunity-celery.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable medunity-backend medunity-celery
echo "[OK] systemd units installed"

echo ""
echo "=== 3. Collect static (prod settings) ==="
cd $BACKEND
sudo -u drriyazq DJANGO_SETTINGS_MODULE=medunity.settings.prod \
  $BACKEND/venv/bin/python manage.py collectstatic --no-input
echo "[OK] static collected"

echo ""
echo "=== 4. Run migrations ==="
sudo -u drriyazq DJANGO_SETTINGS_MODULE=medunity.settings.prod \
  $BACKEND/venv/bin/python manage.py migrate --no-input
echo "[OK] migrations applied"

echo ""
echo "=== 5. Host privacy & terms HTML ==="
mkdir -p /var/www/trusmiledentist.in/medunity/privacy
mkdir -p /var/www/trusmiledentist.in/medunity/terms
cp $PROJ/docs/publishing/hosted/privacy.html /var/www/trusmiledentist.in/medunity/privacy/index.html
cp $PROJ/docs/publishing/hosted/terms.html   /var/www/trusmiledentist.in/medunity/terms/index.html
chown -R www-data:www-data /var/www/trusmiledentist.in/medunity/
echo "[OK] privacy + terms in place"

echo ""
echo "=== 6. Patch trusmile nginx vhost (idempotent) ==="
NGINX_CONF=/etc/nginx/sites-enabled/trusmile
python3 <<PY
from pathlib import Path
p = Path("$NGINX_CONF")
src = p.read_text()
sentinel = "location /medunity/privacy/"
if sentinel in src:
    print("[skip] location blocks already present")
else:
    block = """    location /medunity/privacy/ {
        alias /var/www/trusmiledentist.in/medunity/privacy/;
        try_files \$uri \$uri/index.html =404;
        default_type text/html;
    }

    location /medunity/terms/ {
        alias /var/www/trusmiledentist.in/medunity/terms/;
        try_files \$uri \$uri/index.html =404;
        default_type text/html;
    }

"""
    # Insert right before the catch-all "location / {" inside the canonical
    # server block (the FIRST such occurrence — the canonical 443 vhost).
    needle = "    location / {\n"
    idx = src.find(needle)
    if idx == -1:
        raise SystemExit("Could not find catch-all location block — aborting")
    src = src[:idx] + block + src[idx:]
    p.write_text(src)
    print("[OK] location blocks inserted")
PY

echo ""
echo "=== 7. Validate + reload nginx ==="
nginx -t
systemctl reload nginx
echo "[OK] nginx reloaded"

echo ""
echo "=== 8. Start backend services ==="
systemctl start medunity-backend medunity-celery || true
sleep 3
systemctl --no-pager --lines=0 status medunity-backend
systemctl --no-pager --lines=0 status medunity-celery || true

echo ""
echo "=== 9. Smoke test ==="
echo -n "  health endpoint:  "
curl -sI https://trusmiledentist.in/medunity-api/health/ | head -1
echo -n "  privacy page:     "
curl -sI https://trusmiledentist.in/medunity/privacy/ | head -1
echo -n "  terms page:       "
curl -sI https://trusmiledentist.in/medunity/terms/ | head -1

echo ""
echo "=== DONE ==="
