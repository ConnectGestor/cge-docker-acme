#!/bin/bash
# Atualiza a nuvem, no mesmo estilo do ConnectGestor.
#   curl -sSL https://raw.githubusercontent.com/ConnectGestor/cge-docker-acme/master/gomanager-update.sh | bash
set -euo pipefail

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

DIR="${APP_DIR:-$HOME/appmobile-nuvem}"
if [ ! -f "$DIR/docker-compose.yml" ]; then
  echo "Instalação não encontrada em $DIR. Rode o setup.sh antes."
  exit 1
fi

if [ -f "$DIR/fonte" ]; then
  ORIGEM="$(cat "$DIR/fonte")"
elif [ -d "$DIR/src/.git" ]; then
  ORIGEM="$DIR/src"
else
  echo "Não achei o fonte da nuvem em $DIR."
  exit 1
fi
if [ -d "$ORIGEM/.git" ]; then
  if carregar_credenciais && [ -n "${DOCKER_PASSWORD:-}" ]; then
    auth="$(printf 'x-access-token:%s' "$DOCKER_PASSWORD" | base64 | tr -d '\n')"
    git -C "$ORIGEM" -c "http.extraHeader=AUTHORIZATION: Basic ${auth}" pull --ff-only
  else
    git -C "$ORIGEM" pull --ff-only
  fi
fi

cp "$ORIGEM/docker/Caddyfile" "$DIR/Caddyfile"
cd "$DIR"
docker compose up -d --build
echo "Atualização concluída."
