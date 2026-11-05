{
  description = "Table format converter";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/9fbb54b33e91ee4ca368e35a78e0613c720600b3";
  outputs = { self, nixpkgs }: let
    systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    forAll = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAll (system: let pkgs = import nixpkgs { inherit system; }; in {
      default = pkgs.rustPlatform.buildRustPackage {
        pname = "table";
        version = "0.1.0";
        src = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./src ./tests ./build ];
        };
        cargoLock.lockFile = ./Cargo.lock;
        doCheck = true;
        nativeCheckInputs = [ pkgs.perl pkgs.file ];
        postCheck = "bash tests/build-publication.sh";
        meta = { license = pkgs.lib.licenses.mit; mainProgram = "table"; };
      };
    });
    checks = forAll (system: { package = self.packages.${system}.default; });
  };
}
