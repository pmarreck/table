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
    packages = forAll (system: let
      pkgs = import nixpkgs { inherit system; };
      package = targetPkgs: rendererBin: runChecks: targetPkgs.rustPlatform.buildRustPackage {
        pname = "table";
        version = "0.1.0";
        src = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./src ./tests ./build ];
        };
        cargoLock.lockFile = ./Cargo.lock;
        TABLE_RENDERER = rendererBin;
        postInstall = ''
          mkdir -p "$out/libexec"
          cp "$TABLE_RENDERER" "$out/libexec/tsv-to-ansi-table${targetPkgs.stdenv.hostPlatform.extensions.executable}"
          ${if targetPkgs.stdenv.hostPlatform.isWindows then ''
            cp "$TABLE_RENDERER" "$out/bin/tsv-to-ansi-table.exe"
          '' else ''
            ln -s ../libexec/tsv-to-ansi-table "$out/bin/tsv-to-ansi-table"
          ''}
        '';
        doCheck = runChecks;
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
    in {
      default = package pkgs "${renderer.packages.${system}.rust}/bin/tsv-to-ansi-table-rust" true;
    } // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
      linux-arm64-cross = package pkgs.pkgsCross.aarch64-multiplatform "${renderer.packages.${system}.linux-arm64}/bin/tsv-to-ansi-table-zig" false;
      windows-amd64-cross = package pkgs.pkgsCross.mingwW64 "${renderer.packages.${system}.windows-x86_64}/bin/tsv-to-ansi-table-zig.exe" false;
    });
    checks = forAll (system: { package = self.packages.${system}.default; });
  };
}
