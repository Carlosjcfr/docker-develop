#!/bin/bash

# MAPPING HOST IP (Corregido para usar la misma variable en todo el script)
HOST_IP=$(hostname -I | awk '{print $1}')

echo "Host IP found: $HOST_IP. -> Checking credentials..."

# AUTOMATIC PASSWORD AND KEYS GENERATION
# Comprobamos si el .env ya existe para no sobrescribir claves antiguas y romper la BD
if [ -f .env ] && grep -q "POSTGRES_PASSWORD" .env; then
    echo "Existing .env found. Extracting current secrets..."
    POSTGRES_PASSWORD=$(grep "^POSTGRES_PASSWORD=" .env | cut -d '=' -f2)
    ENCRYPTION_KEY=$(grep "^ENCRYPTION_KEY=" .env | cut -d '=' -f2)
    JWT_SECRET=$(grep "^JWT_SECRET=" .env | cut -d '=' -f2)
else
    echo "First run detected. Generating secure passwords and encryption keys..."
    # Genera una contraseña alfanumérica de 24 caracteres para Postgres
    POSTGRES_PASSWORD=$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 24)
    # Genera claves hexadecimales de 64 caracteres para Arcane
    ENCRYPTION_KEY=$(tr -dc 'a-f0-9' </dev/urandom | head -c 64)
    JWT_SECRET=$(tr -dc 'a-f0-9' </dev/urandom | head -c 64)
fi

echo "Generating .env file..."

# Creating .env file
cat <<EOF > .env
HOST_IP=$HOST_IP
PUID=1001
PGID=1001
APP_URL=http://$HOST_IP:3552

# Database Credentials
POSTGRES_DB=arcane
POSTGRES_USER=arcane
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# Security
ENCRYPTION_KEY=$ENCRYPTION_KEY
JWT_SECRET=$JWT_SECRET
EOF

echo "ENVIRONMENT FILE READY! COMPOSING ARCANE..."

podman-compose up -d

echo "---------------------------------------------------------"
echo "READY! You will find ARCANE in: http://$HOST_IP:3552"
echo "---------------------------------------------------------"

