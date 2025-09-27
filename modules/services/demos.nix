{ config, lib, pkgs, ... }:

{
  # =============================================================================
  # DEMO APPLICATIONS - Testing and Proof of Concept
  # =============================================================================
  # A Collection of Docker based apps for Testing and Proof of Concepting a Production Wiki Tool.
  # These are not intended for production use, but for testing.

  imports = [
    # Demo applications (Docker-based)
    ./docker/bookstack.nix # Bookstack Demo
    ./docker/wiki-js.nix # wiki.js Demo
    ./docker/docmost.nix # Docmost Demo
    ./docker/outline.nix # Outline Demo
  ];
}
