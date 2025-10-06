# Nav
cd /home/tristonyoder/Projects/david-nixos/docker/dockercompose

# Planning Poker
compose2nix -runtime docker -inputs docker-compose_planning-poker.yml -output ../planning-poker.nix

# Wiki.JS
compose2nix -runtime docker -inputs docker-compose_wiki-js.yml -output ../wiki-js.nix

# Bookstack
compose2nix -runtime docker -inputs docker-compose_bookstack.yml -output ../bookstack.nix

# Docmost
compose2nix -runtime docker -inputs docker-compose_docmost.yml -output ../docmost.nix

# Damselfly
compose2nix -runtime docker -inputs docker-compose_damselfly.yml -output ../damselfly.nix

# Outline
cd /etc/nixos/docker/dockercompose/outline;compose2nix -runtime docker -inputs docker-compose_outline.yml -output ../../outline.nix --env_files=.env