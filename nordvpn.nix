{
  autoPatchelfHook,
  buildFHSEnvChroot,
  dpkg,
  fetchurl,
  lib,
  stdenv,
  sysctl,
  iptables,
  iproute2,
  procps,
  cacert,
  libxml2,
  libidn2,
  zlib,
  wireguard-tools,
  icu72,
}: let
  pname = "nordvpn";
  version = "3.18.3";

  # NordVPN requires an old libxml2 version (2.x with .so.2)
  # We'll use Debian's package which is compatible
  libxml2Legacy = stdenv.mkDerivation {
    name = "libxml2-legacy";
    src = fetchurl {
      url = "http://ftp.debian.org/debian/pool/main/libx/libxml2/libxml2_2.9.14+dfsg-1.3~deb12u1_amd64.deb";
      hash = "sha256-NbdstwOPwclAIEpPBfM/+3nQJzU85Gk5fZrc+Pmz4ac=";
    };
    
    nativeBuildInputs = [ dpkg ];
    
    unpackPhase = ''
      dpkg-deb -x $src .
    '';
    
    installPhase = ''
      mkdir -p $out
      cp -r usr/lib $out/
    '';
  };

  nordVPNBase = stdenv.mkDerivation {
    inherit pname version;

    src = fetchurl {
      url = "https://repo.nordvpn.com/deb/nordvpn/debian/pool/main/nordvpn_${version}_amd64.deb";
      hash = "sha256-pCveN8cEwEXdvWj2FAatzg89fTLV9eYehEZfKq5JdaY=";
    };

    buildInputs = [libidn2 icu72];
    nativeBuildInputs = [dpkg autoPatchelfHook stdenv.cc.cc.lib];

    dontConfigure = true;
    dontBuild = true;

    unpackPhase = ''
      runHook preUnpack
      dpkg --extract $src .
      runHook postUnpack
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      mv usr/* $out/
      mv var/ $out/
      mv etc/ $out/
      runHook postInstall
    '';

    # Skip autoPatchelfHook for nordvpnd since we'll patch it manually
    autoPatchelfIgnoreMissingDeps = ["libxml2.so.2"];
    
    postFixup = ''
      # Manually patch nordvpnd with the correct rpath
      patchelf --set-rpath "${libxml2Legacy}/lib/x86_64-linux-gnu:${libidn2}/lib:${icu72}/lib:${stdenv.cc.cc.lib}/lib" $out/bin/nordvpnd
    '';
  };

  nordVPNfhs = buildFHSEnvChroot {
    name = "nordvpnd";
    runScript = "${nordVPNBase}/bin/nordvpnd";

    targetPkgs = pkgs: [
      nordVPNBase
      sysctl
      iptables
      iproute2
      procps
      cacert
      libxml2Legacy
      libidn2
      zlib
      wireguard-tools
      icu72
    ];
    
    # Set up library paths for the FHS environment
    profile = ''
      export LD_LIBRARY_PATH="${libxml2Legacy}/lib/x86_64-linux-gnu:${icu72}/lib:$LD_LIBRARY_PATH"
    '';
  };
in
  stdenv.mkDerivation {
    inherit pname version;

    dontUnpack = true;
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/bin $out/share
      ln -s ${nordVPNBase}/bin/nordvpn $out/bin
      ln -s ${nordVPNfhs}/bin/nordvpnd $out/bin
      ln -s ${nordVPNBase}/share/* $out/share/
      ln -s ${nordVPNBase}/var $out/
      runHook postInstall
    '';

    meta = with lib; {
      description = "CLI client for NordVPN";
      homepage = "https://www.nordvpn.com";
      license = licenses.unfreeRedistributable;
      platforms = ["x86_64-linux" "aarch64-linux"];
    };
  }
