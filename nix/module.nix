{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.programs.qxchat;
  optionalPortal = name: lib.optional (lib.hasAttr name pkgs) pkgs.${name};
  defaultPortalPackages =
    [ pkgs.xdg-desktop-portal-gtk ]
    ++ optionalPortal "xdg-desktop-portal-gnome"
    ++ optionalPortal "xdg-desktop-portal-kde"
    ++ optionalPortal "xdg-desktop-portal-wlr"
    ++ optionalPortal "xdg-desktop-portal-hyprland"
    ++ optionalPortal "xdg-desktop-portal-cosmic";
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

    portalPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = defaultPortalPackages;
      defaultText = lib.literalExpression ''
        [ pkgs.xdg-desktop-portal-gtk ]
        ++ lib.optional (lib.hasAttr "xdg-desktop-portal-gnome" pkgs) pkgs.xdg-desktop-portal-gnome
        ++ lib.optional (lib.hasAttr "xdg-desktop-portal-kde" pkgs) pkgs.xdg-desktop-portal-kde
        ++ lib.optional (lib.hasAttr "xdg-desktop-portal-wlr" pkgs) pkgs.xdg-desktop-portal-wlr
        ++ lib.optional (lib.hasAttr "xdg-desktop-portal-hyprland" pkgs) pkgs.xdg-desktop-portal-hyprland
        ++ lib.optional (lib.hasAttr "xdg-desktop-portal-cosmic" pkgs) pkgs.xdg-desktop-portal-cosmic
      '';
      description = "Backends xdg-desktop-portal à utiliser pour la capture écran PipeWire.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];

    xdg.portal = {
      enable = true;
      extraPortals = cfg.portalPackages;
      config = {
        common.default = [ "gtk" ];
        cosmic.default = [ "cosmic" "gtk" ];
        gnome.default = [ "gnome" "gtk" ];
        kde.default = [ "kde" "gtk" ];
        hyprland.default = [ "hyprland" "gtk" ];
        sway.default = [ "wlr" "gtk" ];
      };
    };
  };
}
