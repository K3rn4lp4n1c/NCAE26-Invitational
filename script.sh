#!/usr/bin/env bash
set -euo pipefail

DB_NAME="snb"
DB_USER="snbuser"
DB_PASS="snbpass"
DB_HOST="127.0.0.1"
DB_PORT="5432"
BACKEND_OVERRIDE_DIR="/etc/systemd/system/snb_backend.service.d"
BACKEND_OVERRIDE_FILE="${BACKEND_OVERRIDE_DIR}/10-local-db.conf"

echo "[*] Checking PostgreSQL..."
if ! command -v psql >/dev/null 2>&1; then
  echo "[!] psql not found."
  echo "    Install PostgreSQL first, then rerun this script."
  echo "    Example: sudo apt-get update && sudo apt-get install -y postgresql"
  exit 1
fi

sudo systemctl enable --now postgresql
sudo systemctl status postgresql --no-pager >/dev/null

echo "[*] Creating local role and database..."
sudo -u postgres psql <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${DB_USER}') THEN
    CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASS}';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE ${DB_NAME} OWNER ${DB_USER}'
WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '${DB_NAME}')\gexec
SQL

echo "[*] Generating bcrypt hash for admin123..."
if [ -x /opt/backend/venv/bin/python ]; then
  ADMIN_HASH="$(
    /opt/backend/venv/bin/python - <<'PY'
import bcrypt
print(bcrypt.hashpw(b"admin123", bcrypt.gensalt()).decode())
PY
  )"
else
  ADMIN_HASH="$(
    python3 - <<'PY'
import bcrypt
print(bcrypt.hashpw(b"admin123", bcrypt.gensalt()).decode())
PY
  )"
fi

echo "[*] Writing schema..."
cat >/tmp/schema.sql <<SQL
CREATE TABLE IF NOT EXISTS users (
    id SERIAL PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    password TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    full_name TEXT NOT NULL,
    bio TEXT NOT NULL DEFAULT '',
    is_admin BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS accounts (
    id SERIAL PRIMARY KEY,
    user_id INTEGER NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    account_number TEXT NOT NULL UNIQUE,
    balance NUMERIC(12,2) NOT NULL DEFAULT 0.00
);

CREATE TABLE IF NOT EXISTS transactions (
    id SERIAL PRIMARY KEY,
    from_account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    to_account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
    amount NUMERIC(12,2) NOT NULL CHECK (amount >= 0),
    note TEXT NOT NULL DEFAULT '',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_accounts_user_id
  ON accounts(user_id);

CREATE INDEX IF NOT EXISTS idx_transactions_from_account_id
  ON transactions(from_account_id);

CREATE INDEX IF NOT EXISTS idx_transactions_to_account_id
  ON transactions(to_account_id);

CREATE INDEX IF NOT EXISTS idx_transactions_created_at
  ON transactions(created_at DESC);
SQL

echo "[*] Writing seed data..."
cat >/tmp/seed.sql <<SQL
INSERT INTO users (username, password, email, full_name, bio, is_admin)
VALUES (
  'admin',
  '${ADMIN_HASH}',
  'admin@sentinel.local',
  'Administrator',
  '',
  TRUE
)
ON CONFLICT (username) DO UPDATE
SET password = EXCLUDED.password,
    email = EXCLUDED.email,
    full_name = EXCLUDED.full_name,
    bio = EXCLUDED.bio,
    is_admin = EXCLUDED.is_admin;

INSERT INTO accounts (user_id, account_number, balance)
SELECT id, 'ACC1000001', 1000.00
FROM users
WHERE username = 'admin'
ON CONFLICT (account_number) DO NOTHING;
SQL

echo "[*] Applying schema and seed..."
PGPASSWORD="${DB_PASS}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -f /tmp/schema.sql
PGPASSWORD="${DB_PASS}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -f /tmp/seed.sql

echo "[*] Creating systemd override for local DATABASE_URL..."
sudo mkdir -p "${BACKEND_OVERRIDE_DIR}"
sudo tee "${BACKEND_OVERRIDE_FILE}" >/dev/null <<EOF
[Service]
Environment="DATABASE_URL=postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
EOF

echo "[*] Reloading systemd and restarting backend..."
sudo systemctl daemon-reload
sudo systemctl restart snb_backend
sudo systemctl status snb_backend --no-pager

echo "[*] Verifying DB contents..."
PGPASSWORD="${DB_PASS}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "\dt"
PGPASSWORD="${DB_PASS}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT id, username, email, is_admin FROM users;"
PGPASSWORD="${DB_PASS}" psql -h "${DB_HOST}" -p "${DB_PORT}" -U "${DB_USER}" -d "${DB_NAME}" -c "SELECT id, user_id, account_number, balance FROM accounts;"

echo
echo "[+] Done."
echo "[+] DATABASE_URL now points to: postgresql://${DB_USER}:${DB_PASS}@${DB_HOST}:${DB_PORT}/${DB_NAME}"
echo "[+] Try logging in as admin / admin123 now."