#!/bin/sh

BROWSER=zen.desktop

echo "Installing Zen-Browser"
yay -S --noconfirm --needed zen-browser-bin

# Enable it to be the default Browser
xdg-settings set default-web-browser $BROWSER

# If the above comman fails/breaks do
# ls /usr/share/applications | grep -i zen 
# this finds the name of the package and then you need to change the BROWSER variable

# Optional, untested
xdg-mime default $BROWSER x-scheme-handler/http
xdg-mime default $BROWSER x-scheme-handler/https
xdg-mime default $BROWSER text/html
