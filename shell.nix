with import <nixpkgs> { };
let
  kbld = stdenv.mkDerivation {
    pname = "kbld";
    version = "0.32.0";
    src = fetchurl {
      # nix-prefetch-url this URL to find the hash value
      url =
        "https://github.com/vmware-tanzu/carvel-kbld/releases/download/v0.32.0/kbld-linux-amd64";
      sha256 = "06im2ywxv7kmdfs00pc8b0jgbc7jxpgd4k6p1b183scrcp26lm6y";
    };
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out/bin
      chmod +x $src && mv $src $out/bin/kbld
    '';
  };
  imgpkg = stdenv.mkDerivation {
    pname = "imgpkg";
    version = "0.27.0";
    src = fetchurl {
      # nix-prefetch-url this URL to find the hash value
      url =
        "https://github.com/vmware-tanzu/carvel-imgpkg/releases/download/v0.27.0/imgpkg-linux-amd64";
      sha256 = "0sqvd8id6wg92402mbyjp2l0iinp5qd2im74i3y1n4g9f3i7dmkj";
    };
    phases = [ "installPhase" ];
    installPhase = ''
      mkdir -p $out/bin
      chmod +x $src && mv $src $out/bin/imgpkg
    '';
  };

in mkShell {
  name = "env";
  buildInputs = [
    kbld
    imgpkg
    kapp
  ];
}