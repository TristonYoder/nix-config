# Auto-generated using compose2nix v0.1.9.
{ pkgs, lib, ... }:

{
  #Enable Docker
  virtualisation = {
    docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
    };
  };
  virtualisation.oci-containers.backend = "docker";
}
