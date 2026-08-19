{ lib
, stdenv
, fetchurl
, dpkg
, autoPatchelfHook
, makeWrapper
, wrapGAppsHook3
, alsa-lib
, at-spi2-atk
, at-spi2-core
, cairo
, cups
, dbus
, expat
, glib
, gtk3
, libcap_ng
, libdrm
, libgbm
, libGL
, libnotify
, libseccomp
, libsecret
, libuuid
, libx11
, libxcb
, libxcomposite
, libxdamage
, libxext
, libxfixes
, libxkbcommon
, libxrandr
, libxtst
, nspr
, nss
, pango
, systemd
, xdg-utils
}:

let
  version = "1.32885.1";

  platformMap = {
    "x86_64-linux" = {
      debArch = "amd64";
      hash = "sha256-+KXd6nyMvnaVic8ZwuGDLV1TKrGb+CAmIbqVfJNRovw=";
    };
    "aarch64-linux" = {
      debArch = "arm64";
      hash = "sha256-XaOBVpxbCcrPyDyZKSAYEgfKRf0ScOIGVN17shxdhVI=";
    };
  };

  platform = platformMap.${stdenv.hostPlatform.system} or null;
in
assert platform != null || throw "claude-desktop is not supported on ${stdenv.hostPlatform.system}";

stdenv.mkDerivation {
  pname = "claude-desktop";
  inherit version;

  src = fetchurl {
    url = "https://downloads.claude.ai/claude-desktop/apt/stable/pool/main/c/claude-desktop/claude-desktop_${version}_${platform.debArch}.deb";
    inherit (platform) hash;
  };

  nativeBuildInputs = [ dpkg autoPatchelfHook makeWrapper wrapGAppsHook3 ];

  buildInputs = [
    alsa-lib
    at-spi2-atk
    at-spi2-core
    cairo
    cups
    dbus
    expat
    glib
    gtk3
    libcap_ng # needed by the bundled virtiofsd
    libdrm
    libgbm
    libseccomp # needed by the bundled virtiofsd
    libsecret
    libuuid
    libx11
    libxcb
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxkbcommon
    libxrandr
    libxtst
    nspr
    nss
    pango
  ];

  # dlopened at runtime rather than linked, so autoPatchelfHook cannot see them.
  runtimeDependencies = [
    (lib.getLib systemd)
    libGL
    libnotify
    libsecret
  ];

  dontConfigure = true;
  dontBuild = true;

  # chrome-sandbox ships setuid, which tar cannot restore in the build sandbox.
  # It is excluded here; see the note in installPhase for why it is not needed.
  unpackPhase = ''
    runHook preUnpack
    dpkg-deb --fsys-tarfile $src \
      | tar -x --no-same-owner --no-same-permissions \
          --exclude=./usr/lib/claude-desktop/chrome-sandbox
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib $out/share
    cp -r usr/lib/claude-desktop $out/lib/claude-desktop
    cp -r usr/share/applications $out/share/applications
    cp -r usr/share/icons $out/share/icons

    # The bundled sandbox helper cannot carry its setuid bit inside the Nix
    # store, so it is dropped at unpack time. --disable-setuid-sandbox below
    # switches Chromium to the namespace sandbox, which keeps it sandboxed.

    runHook postInstall
  '';

  # wrapGAppsHook3 fills gappsWrapperArgs in preFixup, so the wrapper is built
  # there rather than in installPhase.
  dontWrapGApps = true;
  preFixup = ''
    makeWrapper $out/lib/claude-desktop/claude-desktop $out/bin/claude-desktop \
      "''${gappsWrapperArgs[@]}" \
      --add-flags "--disable-setuid-sandbox" \
      --prefix PATH : ${lib.makeBinPath [ xdg-utils ]}
  '';

  meta = {
    description = "Desktop application for Claude.ai, with Chat, Cowork and Claude Code";
    homepage = "https://claude.ai/download";
    downloadPage = "https://code.claude.com/docs/en/desktop-linux";
    license = lib.licenses.unfree;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "claude-desktop";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
}
