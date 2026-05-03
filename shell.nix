{
  pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
    };
  },
}:

let
  # -----------------------
  # Fenix (Rust toolchain)
  # -----------------------
  fenix = import (fetchTarball "https://github.com/nix-community/fenix/archive/master.tar.gz") {
    inherit pkgs;
  };

  rustToolchain = fenix.combine [
    fenix.stable.toolchain

    fenix.targets.aarch64-linux-android.stable.rust-std
    fenix.targets.armv7-linux-androideabi.stable.rust-std
    fenix.targets.i686-linux-android.stable.rust-std
    fenix.targets.x86_64-linux-android.stable.rust-std
  ];

  # -----------------------
  # Android SDK
  # -----------------------
  androidComposition = pkgs.androidenv.composeAndroidPackages {
    platformVersions = [
      "35"
      "36"
      "latest"
    ];
    buildToolsVersions = [
      "35.0.0"
      "latest"
    ];
    abiVersions = [
      "armeabi-v7a"
      "arm64-v8a"
      "x86"
      "x86_64"
    ];
    includeCmake = "if-supported";
    includeEmulator = "if-supported";
    includeNDK = "if-supported";
    includeSystemImages = false;
    ndkVersions = [ "27.0.12077973" ];
  };

  androidSdk = androidComposition.androidsdk;
  androidSdkRoot = "${androidSdk}/libexec/android-sdk";

  jdk = pkgs.jdk17;

  gstPlugins = [
    pkgs.gst_all_1.gstreamer.out
    pkgs.gst_all_1.gst-plugins-base
    pkgs.gst_all_1.gst-plugins-good
    pkgs.gst_all_1.gst-plugins-bad
    pkgs.gst_all_1.gst-plugins-ugly
    pkgs.gst_all_1.gst-libav
  ];

  gstPluginPath = pkgs.lib.concatStringsSep ":" (map (p: "${p}/lib/gstreamer-1.0") gstPlugins);

in
pkgs.mkShell {

  nativeBuildInputs = with pkgs; [
    rustToolchain
    cargo-tauri
    cargo-ndk

    bun

    androidComposition.platform-tools
    androidSdk
    gradle
    jdk

    pkg-config
    gobject-introspection

    wrapGAppsHook4
    gst_all_1.gstreamer.dev
  ];

  buildInputs =
    (with pkgs; [
      at-spi2-atk
      atkmm
      cairo
      gdk-pixbuf
      glib
      glib-networking
      gtk3
      harfbuzz
      librsvg
      libsoup_3
      openssl
      pango
      webkitgtk_4_1
      xdotool
      dbus
    ])
    ++ gstPlugins;

  shellHook = ''
    export JAVA_HOME="${jdk.home}"
    export ANDROID_HOME="${androidSdkRoot}"
    export ANDROID_SDK_ROOT="${androidSdkRoot}"

    # -----------------------
    # NDK setup
    # -----------------------
    android_ndk_dir="$ANDROID_SDK_ROOT/ndk-bundle"

    if [ -d "$ANDROID_SDK_ROOT/ndk" ]; then
      android_ndk_candidate="$(
        find "$ANDROID_SDK_ROOT/ndk" \
          -mindepth 1 -maxdepth 1 -type d \
          | sort -V | tail -n 1
      )"

      if [ -n "$android_ndk_candidate" ]; then
        android_ndk_dir="$android_ndk_candidate"
      fi
    fi

    export ANDROID_NDK_HOME="$android_ndk_dir"
    export ANDROID_NDK_ROOT="$android_ndk_dir"
    export NDK_HOME="$android_ndk_dir"

    export ANDROID_API_LEVEL="24"
    export ANDROID_PLATFORM="android-$ANDROID_API_LEVEL"

    # -----------------------
    # PATH setup
    # -----------------------
    export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

    # CMake
    if [ -d "$ANDROID_SDK_ROOT/cmake" ]; then
      CMAKE_ROOT="$(
        find "$ANDROID_SDK_ROOT/cmake" \
          -mindepth 1 -maxdepth 1 -type d \
          | sort -V | tail -n 1
      )"
      export PATH="$CMAKE_ROOT/bin:$PATH"
    fi

    # -----------------------
    # GStreamer / GTK
    # -----------------------
    export GST_PLUGIN_SYSTEM_PATH_1_0="${gstPluginPath}"
    export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules"
    export WEBKIT_DISABLE_DMABUF_RENDERER=1

    export LD_LIBRARY_PATH="$LD_LIBRARY_PATH:${
      pkgs.lib.makeLibraryPath (
        with pkgs;
        [
          webkitgtk_4_1
          gtk3
          glib
          gdk-pixbuf
          pango
          cairo
          atkmm
          at-spi2-atk
          glib-networking
          harfbuzz
          librsvg
          libsoup_3
          openssl
          dbus

          gst_all_1.gstreamer
          gst_all_1.gst-plugins-base
          gst_all_1.gst-plugins-good
          gst_all_1.gst-plugins-bad
          gst_all_1.gst-plugins-ugly
          gst_all_1.gst-libav
        ]
      )
    }"

    export GIO_EXTRA_MODULES="${pkgs.glib-networking}/lib/gio/modules"
    export GTK_PATH="${pkgs.gtk3}/lib/gtk-3.0"

    # -----------------------
    # NDK linker setup
    # -----------------------
    case "$(uname -s)-$(uname -m)" in
      Linux-x86_64)
        host="linux-x86_64"
        ;;
      *)
        host=""
        ;;
    esac

    if [ -n "$host" ]; then
      bin="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$host/bin"

      export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$bin/aarch64-linux-android$ANDROID_API_LEVEL-clang"
      export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$bin/armv7a-linux-androideabi$ANDROID_API_LEVEL-clang"
      export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$bin/i686-linux-android$ANDROID_API_LEVEL-clang"
      export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$bin/x86_64-linux-android$ANDROID_API_LEVEL-clang"
    fi

    echo "✔ Tauri Android + Fenix environment ready"
  '';
}
