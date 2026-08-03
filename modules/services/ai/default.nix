{
  imports = [
    # hermes-agent.nix is NOT imported here — it references services.hermes-agent
    # from the upstream NousResearch flake, which is only imported on david.
    # It's added directly to david's module list in flake.nix alongside
    # hermes-agent.nixosModules.default.
    ./invoke-ai.nix
    ./litellm.nix
    ./ollama.nix
    ./open-webui.nix
    ./qdrant.nix
  ];
}
