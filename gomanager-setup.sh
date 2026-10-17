#!/bin/bash
# Instala a nuvem, no mesmo estilo do ConnectGestor.
# O script público está em cge-docker-acme. Na VPS, com credentials.env
# na pasta atual:
#   curl -sSL https://raw.githubusercontent.com/ConnectGestor/cge-docker-acme/master/gomanager-setup.sh | bash -s app.connectgestor.com email@empresa.com
set -euo pipefail

DOMINIO="${1:-}"
EMAIL="${2:-}"
if [ -z "$DOMINIO" ] || [ -z "$EMAIL" ]; then
  echo "Uso: setup.sh app.connectgestor.com email@empresa.com"
  exit 1
fi

carregar_credenciais() {
  local f
  for f in ./credentials.env "$HOME/credentials.env" /root/credentials.env; do
    if [ -f "$f" ]; then
      set -a
      # shellcheck disable=SC1090
      . "$f"
      set +a
      return 0
    fi
  done
  return 1
}

clonar_privado() {
  local destino="$1"
  carregar_credenciais || true
  if [ -z "${DOCKER_PASSWORD:-}" ]; then
    echo "Não achei credentials.env. Coloque o arquivo na pasta atual, como no ConnectGestor."
    exit 1
  fi
  if [ -n "${DOCKER_REGISTRY:-}" ] && [ -n "${DOCKER_USER:-}" ]; then
    echo "$DOCKER_PASSWORD" | docker login "$DOCKER_REGISTRY" --username "$DOCKER_USER" --password-stdin
  fi
  local auth
  auth="$(printf 'x-access-token:%s' "$DOCKER_PASSWORD" | base64 | tr -d '\n')"
  git -c "http.extraHeader=AUTHORIZATION: Basic ${auth}" clone --depth 1 https://github.com/ConnectGestor/GoManager.git "$destino"
}

if ! command -v docker >/dev/null 2>&1; then
  echo "Instalando o Docker..."
  curl -fsSL https://get.docker.com | sh
fi
if ! command -v git >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y git ca-certificates
fi

DIR="${APP_DIR:-$HOME/appmobile-nuvem}"
mkdir -p "$DIR"

if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ] && [ -f "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/server.js" ]; then
  ORIGEM="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
else
  ORIGEM="$DIR/src"
  if [ ! -f "$ORIGEM/server.js" ]; then
    clonar_privado "$ORIGEM"
  fi
fi

if [ ! -f "$DIR/.env" ]; then
  SENHA="$(openssl rand -base64 18 | tr -d '/+=' | head -c 20)"
  cat > "$DIR/.env" <<EOF
DOMAIN=$DOMINIO
EMAIL=$EMAIL
POSTGRES_PASSWORD=$(openssl rand -hex 24)
SEGREDO=$(openssl rand -hex 32)
ADMIN_USUARIO=$EMAIL
ADMIN_SENHA=$SENHA
TOKEN_EMPRESA=$(openssl rand -hex 32)
EMPRESA_NOME=$DOMINIO
EOF
  chmod 600 "$DIR/.env"
  echo "Senha inicial: $SENHA"
  echo "Guarde o token do computador que será impresso depois do start."
fi

cp "$ORIGEM/docker/docker-compose.yml" "$DIR/docker-compose.yml"
cp "$ORIGEM/docker/Caddyfile" "$DIR/Caddyfile"
cp "$ORIGEM/docker/update.sh" "$DIR/update.sh"
printf '%s\n' "$ORIGEM" > "$DIR/fonte"
# O compose do repositório aponta o build para a pasta pai.
# Aqui a pasta de instalação contém a cópia do fonte em src, ou usa o próprio repositório.
if [ "$ORIGEM" = "$DIR/src" ]; then
  sed -i 's#context: \.\.#context: ./src#' "$DIR/docker-compose.yml"
else
  sed -i "s#context: \.\.#context: $ORIGEM#" "$DIR/docker-compose.yml"
fi

cd "$DIR"
docker compose up -d --build
TOKEN="$(grep '^TOKEN_EMPRESA=' .env | cut -d= -f2-)"
echo
echo "Nuvem no ar: https://$DOMINIO"
echo "Login: $(grep '^ADMIN_USUARIO=' .env | cut -d= -f2-)"
echo "Token do computador (config.json nuvem.token): $TOKEN"
echo "No computador: nuvem.url = https://$DOMINIO"
