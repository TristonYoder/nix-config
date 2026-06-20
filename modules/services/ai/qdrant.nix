{ config, lib, pkgs, ... }:

with lib;
let
  cfg = config.modules.services.ai.qdrant;
in
{
  options.modules.services.ai.qdrant = {
    enable = mkEnableOption "Qdrant vector store for AI memory and RAG";

    port = mkOption {
      type = types.port;
      default = 6333;
      description = "HTTP port for Qdrant API.";
    };

    grpcPort = mkOption {
      type = types.port;
      default = 6334;
    };
  };

  config = mkIf cfg.enable {
    services.qdrant = {
      enable = true;
      settings = {
        service = {
          host = "127.0.0.1";
          http_port = cfg.port;
          grpc_port = cfg.grpcPort;
        };
        telemetry_disabled = true;
      };
    };
  };
}
