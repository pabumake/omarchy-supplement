#!/bin/sh

echo "Installing Applications:"
. ./install-nano.sh
. ./install-stow.sh
. ./install-zen.sh
. ./install-keeper.sh

# Run this before Dotfiles, otherwise directory changes
echo "Adopting Omarchy overrides:"
. ./install-omarchy-overrides.sh


echo "Setup Dotfiles:"
. ./install-dotfiles.sh


