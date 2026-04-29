{
  description = "LQXP Client Tauri development shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs =
    { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config = {
            allowUnfree = true;
            android_sdk.accept_license = true;
          };
        };
        androidComposition = pkgs.androidenv.composeAndroidPackages {
          platformVersions = [
            "35"
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
          ndkVersions = [ "latest" ];
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
        gstTools = with pkgs.gst_all_1; [
          gstreamer
          gst-plugins-base
          gst-plugins-good
          gst-plugins-bad
          gst-plugins-ugly
          gst-libav
        ];
        gstPluginPath = pkgs.lib.concatStringsSep ":" (map (pkg: "${pkg}/lib/gstreamer-1.0") gstPlugins);
      in
      {
        devShells.default = pkgs.mkShell {
          nativeBuildInputs = with pkgs; [
            androidComposition.platform-tools
            androidSdk
            bun
            cargo
            cargo-ndk
            cargo-tauri
            gobject-introspection
            gradle
            jdk
            pkg-config
            rustc
            rustup
            wrapGAppsHook4
            gst_all_1.gstreamer.dev
          ];

          buildInputs = (with pkgs; [
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
          ]) ++ gstTools ++ gstPlugins;

          shellHook = ''
            if [ -x "$HOME/.cargo/bin/cargo" ] && [ -d "$HOME/.rustup/toolchains" ]; then
              export PATH="$HOME/.cargo/bin:$PATH"
            fi

            export JAVA_HOME="${jdk.home}"
            export ANDROID_HOME="${androidSdkRoot}"
            export ANDROID_SDK_ROOT="${androidSdkRoot}"
            export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk-bundle"
            export ANDROID_NDK_ROOT="$ANDROID_SDK_ROOT/ndk-bundle"
            export NDK_HOME="$ANDROID_NDK_ROOT"
            export ANDROID_API_LEVEL="24"
            export ANDROID_PLATFORM="android-$ANDROID_API_LEVEL"
            export TAURI_ANDROID_RUST_TARGETS="aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android"
            export PATH="$ANDROID_SDK_ROOT/cmdline-tools/latest/bin:$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"

            lqxp-rustup-android-targets() {
              rustup target add $TAURI_ANDROID_RUST_TARGETS
            }

            if [ -d "$ANDROID_SDK_ROOT/cmake" ]; then
              export CMAKE_ROOT="$(find "$ANDROID_SDK_ROOT/cmake" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1)"
              export PATH="$CMAKE_ROOT/bin:$PATH"
            fi

            aapt2="$(find "$ANDROID_SDK_ROOT/build-tools" -name aapt2 -type f 2>/dev/null | sort -V | tail -n 1)"
            if [ -n "$aapt2" ]; then
              export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=$aapt2 ''${GRADLE_OPTS:-}"
            fi

            case "$(uname -s)-$(uname -m)" in
              Linux-x86_64) android_host_tag="linux-x86_64" ;;
              Darwin-x86_64|Darwin-arm64) android_host_tag="darwin-x86_64" ;;
              *) android_host_tag="" ;;
            esac

            if [ -n "$android_host_tag" ]; then
              ndk_bin="$ANDROID_NDK_ROOT/toolchains/llvm/prebuilt/$android_host_tag/bin"
              if [ -d "$ndk_bin" ]; then
                export AR_aarch64_linux_android="$ndk_bin/llvm-ar"
                export AR_armv7_linux_androideabi="$ndk_bin/llvm-ar"
                export AR_i686_linux_android="$ndk_bin/llvm-ar"
                export AR_x86_64_linux_android="$ndk_bin/llvm-ar"
                export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$ndk_bin/aarch64-linux-android$ANDROID_API_LEVEL-clang"
                export CARGO_TARGET_ARMV7_LINUX_ANDROIDEABI_LINKER="$ndk_bin/armv7a-linux-androideabi$ANDROID_API_LEVEL-clang"
                export CARGO_TARGET_I686_LINUX_ANDROID_LINKER="$ndk_bin/i686-linux-android$ANDROID_API_LEVEL-clang"
                export CARGO_TARGET_X86_64_LINUX_ANDROID_LINKER="$ndk_bin/x86_64-linux-android$ANDROID_API_LEVEL-clang"
              fi
            fi

            write_android_local_properties() {
              local file="$1"

              if [ -f "$file" ] && ! grep -q "Generated by shell.nix" "$file"; then
                echo "Android: $file exists already, leaving it untouched."
                return
              fi

              {
                echo "# Generated by shell.nix"
                echo "sdk.dir=$ANDROID_SDK_ROOT"
                echo "ndk.dir=$ANDROID_NDK_ROOT"
                if [ -n "''${CMAKE_ROOT:-}" ]; then
                  echo "cmake.dir=$CMAKE_ROOT"
                fi
              } > "$file"
            }

            if [ -d src-tauri/gen/android ]; then
              write_android_local_properties src-tauri/gen/android/local.properties
            fi

            export GIO_MODULE_DIR="${pkgs.glib-networking}/lib/gio/modules"
            export GST_PLUGIN_SYSTEM_PATH_1_0="${gstPluginPath}"
            export WEBKIT_DISABLE_DMABUF_RENDERER=1
          '';
        };
      });
}
