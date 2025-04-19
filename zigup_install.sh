#!/usr/bin/sh

echo 'Downloading zigup...'
wget --quiet https://github.com/gabrielpacheco23/zigup/releases/download/v0.1/zigup

chmod +x zigup

echo 'Installing zigup...'
sudo mv zigup /usr/bin/zigup

echo 'Installed!'
