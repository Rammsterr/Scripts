#!/bin/bash
set -e  # Stop the script immediately if any command fails

# ---------------------------------------------
# ✅ Variables
# ---------------------------------------------
USERNAME="deployuser"  # The user that will run the app
REPO_URL="https://github.com/Rammsterr/json-xml-converter-api.git"  # Project Git repo
PROJECT_DIR="/home/$USERNAME/json-xml-converter-api"
SSH_CONFIG_FILE="/etc/ssh/sshd_config"  # SSH config file to modify

echo "🚀 Starting automated server setup..."

# ---------------------------------------------
# 📦 Update the system
# ---------------------------------------------
echo "📦 Updating packages..."
sudo apt update && sudo apt upgrade -y  # Update and upgrade all packages

# ---------------------------------------------
# 👤 Create a new user
# ---------------------------------------------
if id "$USERNAME" &>/dev/null; then
    echo "👤 User '$USERNAME' already exists – skipping creation..."
else
    echo "👤 Creating user '$USERNAME'..."
    sudo adduser --disabled-password --gecos "" $USERNAME  # Create user without password
    sudo usermod -aG sudo $USERNAME  # Add user to sudo group
fi

# ---------------------------------------------
# 🔐 Generate SSH key for GitHub access (if needed)
# ---------------------------------------------
if [ ! -f /home/$USERNAME/.ssh/id_ed25519 ]; then
    echo "🔐 Generating new SSH key for $USERNAME..."
    sudo -u $USERNAME ssh-keygen -t ed25519 -N "" -f /home/$USERNAME/.ssh/id_ed25519
    echo "📎 Add the following public key to GitHub:"
    sudo cat /home/$USERNAME/.ssh/id_ed25519.pub
else
    echo "✅ SSH key already exists"
fi

# ---------------------------------------------
# 🔐 Secure SSH by disabling root login
# ---------------------------------------------
echo "🔐 Configuring SSH settings..."
sudo cp $SSH_CONFIG_FILE ${SSH_CONFIG_FILE}.bak  # Backup config
sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' $SSH_CONFIG_FILE  # Disable root login
sudo systemctl restart ssh || sudo systemctl restart sshd  # Restart SSH service

# ---------------------------------------------
# 🔑 Copy root's authorized_keys (optional/fallback)
# ---------------------------------------------
if [ -f /root/.ssh/authorized_keys ]; then
    echo "📄 Copying root's authorized_keys to $USERNAME..."
    sudo mkdir -p /home/$USERNAME/.ssh
    sudo cp /root/.ssh/authorized_keys /home/$USERNAME/.ssh/
    sudo chown -R $USERNAME:$USERNAME /home/$USERNAME/.ssh
    sudo chmod 700 /home/$USERNAME/.ssh
    sudo chmod 600 /home/$USERNAME/.ssh/authorized_keys
else
    echo "⚠️ No authorized_keys found for root – manual SSH key setup may be needed."
fi

# ---------------------------------------------
# 🛡️ Setup UFW firewall
# ---------------------------------------------
echo "🛡️ Enabling UFW firewall..."
sudo ufw allow OpenSSH  # Allow SSH
sudo ufw allow 8080/tcp  # Allow access to the API on port 8080
sudo ufw --force enable  # Enable firewall without prompt

# ---------------------------------------------
# 🐳 Install Docker and Docker Compose
# ---------------------------------------------
echo "🐳 Installing Docker..."

# Remove any old versions that might interfere
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
    sudo apt-get remove -y $pkg || true
done

# Install Docker dependencies
sudo apt-get install -y ca-certificates curl

# Setup Docker GPG key and repository
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

echo "➕ Adding Docker APT repository..."
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker Engine and Compose
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Add user to the docker group
sudo usermod -aG docker $USERNAME

# ---------------------------------------------
# 🔁 Clone Spring Boot project and start container
# ---------------------------------------------
echo "📥 Cloning Spring Boot repo (if not already cloned)..."

sudo -u $USERNAME bash <<EOF
cd /home/$USERNAME

# Clone only if the folder doesn't exist
if [ ! -d "json-xml-converter-api" ]; then
    git clone $REPO_URL
fi

cd json-xml-converter-api
docker compose up -d  # Start app as Docker container
EOF

# ---------------------------------------------
# 🧪 Test if API is responding
# ---------------------------------------------
if curl -s --head http://localhost:8080 | grep "200 OK" > /dev/null; then
    echo "✅ API is responding correctly on port 8080"
else
    echo "❌ API is not responding – check with: docker ps and docker logs"
fi

# ---------------------------------------------
# 🎉 Done!
# ---------------------------------------------
echo "✅ Setup complete! API should be available at: http://<SERVER-IP>:8080"
echo "🌐 Open in browser: http://<SERVER-IP>:8080/swagger-ui/index.html"
