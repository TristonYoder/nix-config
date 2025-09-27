{ config, pkgs, lib, ... }:

  #Wordpress Config
let
  domain = "localhost";

  # Auxiliary functions
  fetchPackage = { name, version, hash, isTheme }:
    pkgs.stdenv.mkDerivation rec {
      inherit name version hash;
      src = let type = if isTheme then "theme" else "plugin";
      in pkgs.fetchzip {
        inherit name version hash;
        url = "https://downloads.wordpress.org/${type}/${name}.${version}.zip";
      };
      installPhase = "mkdir -p $out; cp -R * $out/";
    };

  fetchPlugin = { name, version, hash }:
    (fetchPackage {
      name = name;
      version = version;
      hash = hash;
      isTheme = false;
    });

  fetchTheme = { name, version, hash }:
    (fetchPackage {
      name = name;
      version = version;
      hash = hash;
      isTheme = true;
    });

  # Plugins
  duplicator = (fetchPlugin {
    name = "duplicator";
    version = "1.5.8";
    hash = "sha256-B1rO6NI+uWxfF98g54gqmk1uokUd3VGz5s5/nbcZDQk=";
  });

  # # Themes
  # astra = (fetchTheme {
  #   name = "astra";
  #   version = "4.1.5";
  #   hash = "sha256-X3Jv2kn0FCCOPgrID0ZU8CuSjm/Ia/d+om/ShP5IBgA=";
  # });

in {
  services = {
    # nginx.virtualHosts.${domain} = {
    #   enableACME = true;
    #   forceSSL = true;
    # };

    wordpress = {
      # webserver = "nginx";
      sites."${domain}" = {
        plugins = { inherit duplicator; };
        # themes = { inherit astra; };
        # settings = { WP_DEFAULT_THEME = "astra"; };
      };
    };
  };

# PHP Config
services.phpfpm.pools."wordpress-localhost".phpOptions = ''
  upload_max_filesize=1G
  post_max_size=1G
'';

}
