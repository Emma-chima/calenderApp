#!/usr/bin/env bash

# Install MariaDB 10.5 client to get the mysql CLI
sudo dnf install -y mariadb105

# Import your SQL
mysql \
  -h "$RDS_HOSTNAME" \
  -P "$RDS_PORT" \
  -u "$RDS_USERNAME" \
  -p"$RDS_PASSWORD" \
  "$RDS_DB_NAME" < /var/app/current/appointments.sql || true
