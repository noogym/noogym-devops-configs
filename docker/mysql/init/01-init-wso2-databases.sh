#!/usr/bin/env bash
set -euo pipefail

: "${MYSQL_ROOT_PASSWORD:?MYSQL_ROOT_PASSWORD is required}"
: "${SHARED_DB_NAME:?SHARED_DB_NAME is required}"
: "${SHARED_DB_USER:?SHARED_DB_USER is required}"
: "${SHARED_DB_PASSWORD:?SHARED_DB_PASSWORD is required}"
: "${APIM_DB_NAME:?APIM_DB_NAME is required}"
: "${APIM_DB_USER:?APIM_DB_USER is required}"
: "${APIM_DB_PASSWORD:?APIM_DB_PASSWORD is required}"

mysql_root=(mysql --protocol=socket -uroot -p"${MYSQL_ROOT_PASSWORD}")

echo "Creating WSO2 API Manager databases and users"
"${mysql_root[@]}" <<-EOSQL
CREATE DATABASE IF NOT EXISTS \`${SHARED_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;
CREATE DATABASE IF NOT EXISTS \`${APIM_DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_bin;

CREATE USER IF NOT EXISTS '${SHARED_DB_USER}'@'%' IDENTIFIED BY '${SHARED_DB_PASSWORD}';
CREATE USER IF NOT EXISTS '${APIM_DB_USER}'@'%' IDENTIFIED BY '${APIM_DB_PASSWORD}';

GRANT ALL ON \`${SHARED_DB_NAME}\`.* TO '${SHARED_DB_USER}'@'%';
GRANT ALL ON \`${APIM_DB_NAME}\`.* TO '${APIM_DB_USER}'@'%';
FLUSH PRIVILEGES;
EOSQL

echo "Initializing WSO2 shared database schema"
"${mysql_root[@]}" "${SHARED_DB_NAME}" < /wso2-dbscripts/shared/mysql.sql

echo "Initializing WSO2 API Manager database schema"
"${mysql_root[@]}" "${APIM_DB_NAME}" < /wso2-dbscripts/apimgt/mysql.sql
