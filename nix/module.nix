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

    portalPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.xdg-desktop-portal-gtk;
      defaultText = lib.literalExpression "pkgs.xdg-desktop-portal-gtk";
      description = "This package is required for screen capture.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    xdg.portal = {
      enable = true;
      extraPortals = [ cfg.portalPackage ];
    };
  };
}
