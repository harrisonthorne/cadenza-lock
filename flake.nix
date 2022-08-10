{
  inputs = {
    naersk.url = "github:nmattia/naersk/master";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    naersk,
  }: let
    appName = "cadenza-lock";
    out =
      utils.lib.eachDefaultSystem
      (system: let
        pkgs = import nixpkgs {inherit system;};
        naersk-lib = naersk.lib."${system}";
        nativeBuildInputs = builtins.attrValues {inherit (pkgs) cargo cargo-watch rustc rustfmt clippy pkg-config;};
        buildInputs = with pkgs; [libxkbcommon linux-pam];
      in {
        defaultPackage = naersk-lib.buildPackage {
          pname = appName;
          root = builtins.path {
            path = ./.;
            name = "${appName}-src";
          };
          inherit nativeBuildInputs buildInputs;
        };

        defaultApp = utils.lib.mkApp {
          drv = self.defaultPackage."${system}";
        };

        devShell = pkgs.mkShell {
          packages = nativeBuildInputs ++ buildInputs;
          LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath buildInputs;
        };
      });
  in
    out
    // {
      overlay = final: prev: {
        ${appName} = self.defaultPackage.${prev.system};
      };
    };
}
