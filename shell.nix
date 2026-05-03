{
  pkgs ? import <nixpkgs> {
    config = {
      allowUnfree = true;
      android_sdk.accept_license = true;
    };
  },
}:

let
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
    rustc
    cargo
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
    ])
    ++ gstPlugins;

  shellHook = ''
    export JAVA_HOME="${jdk.home}"
    export ANDROID_HOME="${androidSdkRoot}"
    export ANDROID_SDK_ROOT="${androidSdkRoot}"

    # NDK detection
    android_ndk_dir="$ANDROID_SDK_ROOT/ndk-bundle"
    if [ -d "$ANDROID_SDK_ROOT/ndk" ]; then
      android_ndk_candidate="$(find "$ANDROID_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
      if [ -n "$android_ndk_candidate" ]; then
        android_ndk_dir="$android_ndk_candidate"
      fi
    fi

    export ANDROID_NDK_HOME="$android_ndk_dir"
    export ANDROID_NDK_ROOT="$android_ndk_dir"
    export NDK_HOME="$android_ndk_dir"

    export ANDROID_API_LEVEL="24"
    export ANDROID_PLATFORM="android-$ANDROID_API_LEVEL"

    # Tauri targets fix
    : "''${TAURI_ANDROID_RUST_TARGETS:=aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android}"
    export TAURI_ANDROID_RUST_TARGETS

    export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

    # CMake
    if [ -d "$ANDROID_SDK_ROOT/cmake" ]; then
      CMAKE_ROOT="$(find "$ANDROID_SDK_ROOT/cmake" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
      export PATH="$CMAKE_ROOT/bin:$PATH"
    fi

    # AAPT2 fix
    aapt2="$(find "$ANDROID_SDK_ROOT/build-tools" -name aapt2 -type f 2>/dev/null | sort -V | tail -n 1)"
    if [ -n "$aapt2" ]; then
      export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=$aapt2"
    fi

    # GStreamer / GTK
    export GST_PLUGIN_SYSTEM_PATH_1_0="${gstPluginPath}"
    export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules"
    export WEBKIT_DISABLE_DMABUF_RENDERER=1

    # Android linker setup
    case "$(uname -s)-$(uname -m)" in
      Linux-x86_64) android_host_tag="linux-x86_64" ;;
      *) android_host_tag="" ;;
    esac

    if [ -n "$android_host_tag" ]; then
      ndk_bin="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$android_host_tag/bin"

      export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ndk_bin/aarch64-linux-android$ANDROID_API_LEVEL-clang"
      export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$ndk_bin/armv7a-linux-androideabi$ANDROID_API_LEVEL-clang"
      export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$ndk_bin/i686-linux-android$ANDROID_API_LEVEL-clang"
      export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$ndk_bin/x86_64-linux-android$ANDROID_API_LEVEL-clang"
    fi

    # optional .env
    if [ -f .env ]; then
      set -a
      . ./.env
      set +a
    fi

    echo "✔ nix-shell Tauri Android environment ready"
  '';
}
