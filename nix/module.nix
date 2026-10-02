{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.programs.qxchat;
  # Stock nixpkgs webkitgtk_4_1 builds with enableExperimental=false, and
  # upstream defaults ENABLE_WEB_RTC to ENABLE_EXPERIMENTAL_FEATURES — so the
  # stock build has no RTCPeerConnection at all and calls report
  # "WebRTC is not supported". Flipping webrtcSupport swaps in a WebKitGTK
  # built with experimental features (WebRTC included). That is a full WebKit
  # source build (~9000 TU) the first time; the GStreamer webrtc elements are
  # already in the wrapper's runtime closure, so nothing else changes.
  finalPackage =
    if cfg.webrtcSupport && cfg.package ? override
    then
      cfg.package.override {
        webkitgtk_4_1 = pkgs.webkitgtk_4_1.override { enableExperimental = true; };
      }
    else cfg.package;
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

    extraPortals = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      defaultText = lib.literalExpression "[ ]";
      description = "Additional xdg-desktop-portal backends (e.g. xdg-desktop-portal-wlr or xdg-desktop-portal-hyprland for screen sharing under wlroots/Hyprland).";
    };

    webrtcSupport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Rebuild WebKitGTK with experimental features so WebRTC calls work. Off by default to keep binary-cache substitution (switching it on triggers a full WebKit source build once).";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ finalPackage ];

    xdg.portal = {
      enable = true;
      extraPortals = [ cfg.portalPackage ] ++ cfg.extraPortals;
    };
  };
}
