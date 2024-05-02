{ config, pkgs, lib, ... }:
			
{                          
  # Audiobookshelf
  virtualisation.oci-containers.containers."audiobookshelf" = {
	autoStart = true;
	image = "ghcr.io/advplyr/audiobookshelf:latest";
	environment = {
	  AUDIOBOOKSHELF_UID = "1000";
	  AUDIOBOOKSHELF_GID = "1000";
	};
	ports = [ "13378:80" ];
	volumes = [
	  "/data/media/Audiobooks:/audiobooks"
	  "/data/media/Podcasts:/podcasts"
	  "/data/docker-appdata/audiobookshelf/config:/config"
	  "/data/docker-appdata/audiobookshelf/metadata:/metadata"
	];
  };
}