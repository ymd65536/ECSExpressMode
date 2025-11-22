# !bin/bash
sudo apt update -y
sudo apt upgrade -y
sudo apt install -y python3 python3-pip
pip install --index-url https://pypi.org/simple --user boto3 --break-system-packages
npm install -g aws-cdk@2.153.0

# CodeArtifactにある独自Python packageをインストールする場合はbuildとtwineもインストールします。
# pip install --index-url https://pypi.org/simple --user build twine --break-system-packages
