#!/bin/bash
set -e

# ---------------------------------------------
# Variabler
# ---------------------------------------------
USERNAME="deployuser"
REPO_URL="https://github.com/Rammsterr/json-xml-converter-api.git"
PROJECT_DIR="/home/$USERNAME/json-xml-converter-api"
SSH_CONFIG_FILE="/etc/ssh/sshd_config"

echo "Startar automatiserad setup..."

# ---------------------------------------------
# Uppdatering av system
# ---------------------------------------------
echo "Uppdaterar systemet..."
sudo apt update && sudo apt upgrade -y

# ---------------------------------------------
# Skapa användare
# ---------------------------------------------
if id "$USERNAME" &>/dev/null; then
    echo "Användaren '$USERNAME' finns redan – hoppar över..."
else
    echo "Skapar användare '$USERNAME'..."
    sudo adduser --disabled-password --gecos "" $USERNAME
    sudo usermod -aG sudo $USERNAME
fi

if [ ! -f /home/$USERNAME/.ssh/id_ed25519 ]; then
    echo "Genererar ny SSH-nyckel för användaren..."
    sudo -u $USERNAME ssh-keygen -t ed25519 -N "" -f /home/$USERNAME/.ssh/id_ed25519
    echo "Lägg till följande publika nyckel till GitHub:"
    sudo cat /home/$USERNAME/.ssh/id_ed25519.pub
else
    echo "SSH-nyckel finns redan"
fi

# ---------------------------------------------
# SSH-konfiguration
# ---------------------------------------------
echo "Konfigurerar SSH..."
sudo cp $SSH_CONFIG_FILE ${SSH_CONFIG_FILE}.bak
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $SSH_CONFIG_FILE
sudo systemctl restart ssh || sudo systemctl restart sshd

# ---------------------------------------------
# Kopiera SSH-nyckel
# ---------------------------------------------
if [ -f /root/.ssh/authorized_keys ]; then
    echo "Kopierar root-användarens SSH-nyckel till '$USERNAME'..."
    sudo mkdir -p /home/$USERNAME/.ssh
    sudo cp /root/.ssh/authorized_keys /home/$USERNAME/.ssh/
    sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
    sudo chmod 700 /home/$USERNAME/.ssh
    sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
else
    echo "Ingen authorized_keys hittades – lägg till SSH-nyckel manuellt."
fi

# ---------------------------------------------
# Brandvägg
# ---------------------------------------------
echo "Aktiverar UFW..."
sudo ufw allow OpenSSH
sudo ufw allow 8080/tcp
sudo ufw --force enable

# ---------------------------------------------
# Installera Docker
# ---------------------------------------------
echo "Installerar Docker..."
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg || true
done

sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "Lägger till Docker repo..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker $USERNAME

# ---------------------------------------------
# Klona och starta Spring Boot-projekt
# ---------------------------------------------
echo "Klonar Spring Boot-repo om det inte finns..."
sudo -u $USERNAME bash <<EOF
cd /home/$USERNAME
if [ ! -d "json-xml-converter-api" ]; then
    git clone $REPO_URL
fi
cd json-xml-converter-api
docker compose up -d
EOF

echo "Allt klart! API ska nu vara tillgängligt på http://<SERVER-IP>:8080"
echo "Testa gärna: http://46.62.165.167:8080/swagger-ui/index.html"

if curl -s --head http://localhost:8080 | grep "200 OK" > /dev/null; then
    echo "API svarar korrekt på port 8080"
else
    echo "API svarar inte – kontrollera containern med: docker ps"
fi
