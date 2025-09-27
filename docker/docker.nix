# Auto-generated using compose2nix v0.1.9.
{ pkgs, lib, ... }:

{
  virtualisation = {
    docker = {
      enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
      };
      daemon.settings = {
        hosts = [
          "unix:///var/run/docker.sock"
          "tcp://0.0.0.0:2375"
        ];
      };
    };
    oci-containers.backend = "docker";
  };
}

