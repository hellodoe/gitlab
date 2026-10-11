# Test server runbook

One-time manual setup for the **Test server**, plus the CI/CD variables the pipeline needs.
The pipeline never provisions the server; it assumes everything below exists.
Replace `myapp` and `/var/www/myapp` with your values (`APP_NAME`, `DEPLOY_ROOT`).

## 1. Runner prerequisites (shared shell runner)

`ssh`, `rsync`, `python3` (+ `venv`), `node` and `npm`. Pin the versions your project needs
(record them here once known: Python __, Node __). Jobs fail fast if a tool is missing.

## 2. Test server setup

```bash
# deploy user + layout
sudo useradd -m -s /bin/bash deploy
sudo mkdir -p /var/www/myapp/{releases,venvs,shared}
sudo chown -R deploy:deploy /var/www/myapp

# app config and secrets: lives here, never in git or the pipeline
sudo -u deploy install -m 600 /dev/null /var/www/myapp/shared/app.env
sudo -u deploy editor /var/www/myapp/shared/app.env   # KEY=value lines (no `export`)

# the deploy key's public half
sudo -u deploy mkdir -m 700 ~deploy/.ssh
echo '<public key>' | sudo -u deploy tee -a ~deploy/.ssh/authorized_keys
sudo chmod 600 ~deploy/.ssh/authorized_keys
```

Needs `python3-venv` and `curl` installed.

### sudoers (`/etc/sudoers.d/deploy`, edit with `visudo -f`)

```
deploy ALL=(root) NOPASSWD: /bin/systemctl restart myapp, /bin/systemctl reload apache2
```

Check the `systemctl` path with `command -v systemctl`; on RHEL the service is `httpd`
(then set `APACHE_SERVICE=httpd`).

### systemd unit (`/etc/systemd/system/myapp.service`)

```ini
[Unit]
Description=myapp backend
After=network.target

[Service]
User=deploy
WorkingDirectory=/var/www/myapp/current/backend
EnvironmentFile=/var/www/myapp/shared/app.env
ExecStart=/var/www/myapp/current/venv/bin/gunicorn --bind 127.0.0.1:8000 myapp.wsgi:application
Restart=on-failure

[Install]
WantedBy=multi-user.target
```

`myapp.wsgi:application` is a placeholder; for FastAPI use uvicorn instead. Then
`sudo systemctl daemon-reload && sudo systemctl enable myapp`.

### Apache vhost

Enable `proxy`, `proxy_http`, `rewrite`; add TLS as your environment requires.

```apache
<VirtualHost *:80>
    ServerName test.example.com
    DocumentRoot /var/www/myapp/current/frontend

    <Directory /var/www/myapp/current/frontend>
        Options FollowSymLinks
        Require all granted
        FallbackResource /index.html
    </Directory>

    ProxyPass        /api http://127.0.0.1:8000/api
    ProxyPassReverse /api http://127.0.0.1:8000/api
</VirtualHost>
```

Adjust `/api` to your backend's real URL prefix. The first deploy creates `current`,
so Apache may only start serving cleanly after it.

## 3. GitLab CI/CD variables

Settings > CI/CD > Variables. The SSH ones must NOT be "Protected" (manual deploys from other branches need them).

| Variable | Type | Value |
|---|---|---|
| `TEST_HOST` | Variable | Test server hostname/IP |
| `TEST_USER` | Variable | `deploy` |
| `DEPLOY_ROOT` | Variable | `/var/www/myapp` |
| `APP_NAME` | Variable | systemd service name, `myapp` |
| `SSH_PRIVATE_KEY` | **File** | private key matching `authorized_keys` (`ssh-keygen -t ed25519`) |
| `SSH_KNOWN_HOSTS` | **File** | output of `ssh-keyscan -t ed25519 <host>`, verified against the server's real fingerprint |
| `HEALTH_URL` | Variable (optional) | default `http://127.0.0.1/`; checked from the server itself |
| `MIGRATE_CMD` | Variable (optional) | e.g. `python manage.py migrate --noinput`; empty = skip |
| `KEEP_RELEASES` | Variable (optional) | default `5` |
| `APACHE_SERVICE` | Variable (optional) | default `apache2` |

## 4. Operating it

- `main`: test, build, then deploy automatically.
- Other branches: test and build run; click **deploy:test** to deploy (last deploy wins, one at a time).
- Failed health check: the job re-points `current` to the previous Release and fails.
- Manual rollback: click **rollback:test** (goes one Release back each time, until the kept ones run out).
- **Database migrations are never reverted** by either rollback. Write backwards-compatible migrations.
- Old virtualenvs in `venvs/` are not pruned; delete unused ones by hand occasionally.
