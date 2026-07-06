# Watchtower - Automatic Docker container updates
# Monitors running containers and automatically updates them to the latest image versions
{ config, pkgs, ... }:

{

  # Watchtower
  # containrrr/watchtower is archived (last published 2023-11-11) and its
  # bundled Docker client can't negotiate with newer Docker daemons ("client
  # version 1.25 is too old, minimum supported API version is 1.40"). Use the
  # actively maintained fork instead.
  virtualisation.oci-containers.containers."watchtower" = {
    autoStart = true;
    image = "nickfedor/watchtower";
    volumes = [
      "/var/run/docker.sock:/var/run/docker.sock"
    ];
  };

}
