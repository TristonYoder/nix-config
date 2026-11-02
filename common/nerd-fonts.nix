# Nerd Fonts installed on every host with a local display (NixOS desktops and macOS).
# Shared so terminals render Powerlevel10k glyphs identically everywhere.
# Not a module: import it as a function of pkgs and add the result to fonts.packages.
#   fonts.packages = import ../common/nerd-fonts.nix pkgs;

pkgs: with pkgs.nerd-fonts; [
  meslo-lg       # Powerlevel10k's recommended font
  fira-code
  jetbrains-mono
  hack
  roboto-mono
]
