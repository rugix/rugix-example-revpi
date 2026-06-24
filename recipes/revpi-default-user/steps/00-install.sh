#!/bin/bash

set -euo pipefail

user="${RECIPE_PARAM_USER}"

if ! id "$user" >/dev/null 2>&1; then
    useradd -m -U -s /bin/bash "$user"
fi

usermod -aG adm,audio,dialout,input,netdev,plugdev,render,sudo,users,video "$user"
printf "%s:%s\n" "$user" "${RECIPE_PARAM_PASSWORD}" | chpasswd

cat > /etc/sudoers.d/050_sudo-group-password-prompt <<'EOF'
%sudo ALL=(ALL) ALL
EOF
chmod 440 /etc/sudoers.d/050_sudo-group-password-prompt

cat > /etc/sudoers.d/051_revpi-factory-reset <<EOF
${user} ALL=(root) NOPASSWD: /usr/sbin/revpi-factory-reset *
EOF
chmod 440 /etc/sudoers.d/051_revpi-factory-reset

