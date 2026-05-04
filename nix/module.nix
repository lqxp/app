{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.programs.qxchat;
in
{
  options.programs.qxchat = {
    enable = lib.mkEnableOption "QxChat desktop client";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.qxchat;
      defaultText = lib.literalExpression "pkgs.qxchat";
      description = "Le paquet QxChat à installer.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
