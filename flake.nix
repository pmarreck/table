{
  description = "Table format converter";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/9fbb54b33e91ee4ca368e35a78e0613c720600b3";
  inputs.renderer = {
    url = "github:pmarreck/tsv_to_ansi_table/aa7cdef0cad4dab6c33a3188ed723faba5436ff1";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, renderer }: let
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
        TABLE_RENDERER = "${renderer.packages.${system}.rust}/bin/tsv-to-ansi-table-rust";
        postInstall = ''ln -s "$TABLE_RENDERER" "$out/bin/tsv-to-ansi-table"'';
        doCheck = true;
        nativeCheckInputs = [ pkgs.perl pkgs.file ];
        postCheck = ''
          bash tests/build-publication.sh
          (
            cd ${renderer}
            for suite in check semantics errors equals color glyphs streaming; do
              bash "tests/cli/$suite" "$TABLE_RENDERER"
            done
          )
        '';
        meta = { license = pkgs.lib.licenses.mit; mainProgram = "table"; };
      };
    });
    checks = forAll (system: { package = self.packages.${system}.default; });
  };
}
