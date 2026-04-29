#!/usr/bin/env bash
set -e

echo "=== MedUnity Phase 0 infra setup ==="

# 1. Systemd units
cp /home/drriyazq/medunity/backend/deploy/medunity-backend.service /etc/systemd/system/
cp /home/drriyazq/medunity/backend/deploy/medunity-celery.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable medunity-backend medunity-celery
echo "[OK] systemd units installed and enabled"

# 2. Nginx
cp /home/drriyazq/medunity/backend/deploy/nginx-medunity.conf /etc/nginx/sites-available/medunity
ln -sf /etc/nginx/sites-available/medunity /etc/nginx/sites-enabled/medunity
nginx -t && systemctl reload nginx
echo "[OK] Nginx vhost installed (HTTP only — run certbot next)"

# 3. Collect static
cd /home/drriyazq/medunity/backend
DJANGO_SETTINGS_MODULE=medunity.settings.dev venv/bin/python manage.py collectstatic --no-input
echo "[OK] Static files collected"

# 4. Start services
systemctl start medunity-backend medunity-celery
sleep 2
systemctl status medunity-backend --no-pager
systemctl status medunity-celery --no-pager

echo ""
echo "=== Next step: certbot ==="
echo "certbot --nginx -d medunity.areafair.in"
echo ""
echo "=== Drop firebase-credentials.json at: ==="
echo "/home/drriyazq/medunity/backend/firebase-credentials.json"
