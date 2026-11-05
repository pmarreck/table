{
  description = "Table format converter";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/9fbb54b33e91ee4ca368e35a78e0613c720600b3";
  inputs.renderer = {
    url = "github:pmarreck/tsv_to_ansi_table/aa7cdef0cad4dab6c33a3188ed723faba5436ff1";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.rust-overlay = {
    url = "github:oxalica/rust-overlay/19e0e6c951a7a8a7d3232c64e58d26b89df44c60";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, renderer, rust-overlay }: let
    systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    forAll = nixpkgs.lib.genAttrs systems;
  in {
    packages = forAll (system: let
      pkgs = import nixpkgs { inherit system; };
      publicationFixture = pkgs.runCommand "table-publication-fixture" { } ''
        mkdir -p "$out/bin" "$out/libexec" "$out/share/licenses/table"
        cat > "$out/bin/table" <<'EOF'
#!${pkgs.runtimeShell}
printf 'table 0.1.0; PF=linux-amd64 VARIANT=gnu\n'
EOF
        chmod +x "$out/bin/table"
        cp "$out/bin/table" "$out/bin/table.exe"
        cp "$out/bin/table" "$out/bin/tsv-to-ansi-table"
        cp "$out/bin/table" "$out/bin/tsv-to-ansi-table.exe"
        cp "$out/bin/table" "$out/libexec/tsv-to-ansi-table.exe"
        printf 'fixture notices\n' > "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
      '';
      notices = ''
        mkdir -p "$out/share/licenses/table"
        notice="$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
        {
          printf 'table and predecessor renderer license\n\n'
          cat LICENSE
          for vendor in "$cargoDeps" "${renderer.packages.${system}.rust.cargoDeps}"; do
            for crate in "$vendor"/*; do
              [ -d "$crate" ] || continue
              for license in "$crate"/LICENSE* "$crate"/COPYING*; do
                [ -f "$license" ] || continue
                printf '\n\n===== %s / %s =====\n\n' "''${crate##*/}" "''${license##*/}"
                cat "$license"
              done
            done
          done
          printf '\n\n===== utf8proc and Unicode data =====\n\n'
          cat "$cargoDeps/utf8proc-sys-0.1.2/utf8proc/LICENSE.md"
          printf '\n\n===== random renderer dependency =====\n\n'
          cat "${renderer.inputs.random}/LICENSE"
        } > "$notice"
      '';
      package = targetPkgs: rendererBin: runChecks: targetPkgs.rustPlatform.buildRustPackage {
        pname = "table";
        version = "0.1.0";
        src = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./LICENSE ./src ./tests ./build ];
        };
        cargoLock.lockFile = ./Cargo.lock;
        TEST_PUBLICATION_FIXTURE = "${publicationFixture}";
        TABLE_RENDERER = rendererBin;
        postInstall = ''
          mkdir -p "$out/libexec"
          for probe in table-perf table-memory; do
            mv "$out/bin/$probe${targetPkgs.stdenv.hostPlatform.extensions.executable}" "$out/libexec/$probe${targetPkgs.stdenv.hostPlatform.extensions.executable}"
          done
          cp "$TABLE_RENDERER" "$out/libexec/tsv-to-ansi-table${targetPkgs.stdenv.hostPlatform.extensions.executable}"
          ${if targetPkgs.stdenv.hostPlatform.isWindows then ''
            cp "$TABLE_RENDERER" "$out/bin/tsv-to-ansi-table.exe"
          '' else ''
            ln -s ../libexec/tsv-to-ansi-table "$out/bin/tsv-to-ansi-table"
          ''}
          ${notices}
        '';
        doCheck = runChecks;
        nativeCheckInputs = [ pkgs.perl pkgs.file pkgs.python3 ];
        postCheck = ''
          bash tests/build-publication.sh
          "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table-memory" --self-test
          python3 tests/csv-oracle.py "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table"
          (
            cd ${renderer}
            for suite in check semantics errors equals color glyphs streaming; do
              bash "tests/cli/$suite" "$TABLE_RENDERER"
            done
          )
        '';
        doInstallCheck = runChecks;
        installCheckPhase = ''
          test -s "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
          grep -q 'Unicode data license' "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
        '';
        meta = {
          license = pkgs.lib.licenses.mit;
          mainProgram = "table";
          platforms = if targetPkgs.stdenv.hostPlatform.system == "aarch64-windows" then [ "aarch64-windows" ] else pkgs.lib.platforms.all;
        };
      };
    in {
      profiling-tool = renderer.inputs.performance-profiling.packages.${system}.default;
      default = package pkgs "${renderer.packages.${system}.rust}/bin/tsv-to-ansi-table-rust" true;
    } // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
      linux-arm64-cross = package pkgs.pkgsCross.aarch64-multiplatform "${renderer.packages.${system}.linux-arm64}/bin/tsv-to-ansi-table-zig" false;
      windows-amd64-cross = package pkgs.pkgsCross.mingwW64 "${renderer.packages.${system}.windows-x86_64}/bin/tsv-to-ansi-table-zig.exe" false;
      windows-arm64-cross = let
        rust-bin = rust-overlay.lib.mkRustBin { } pkgs;
        toolchain = rust-bin.stable."1.97.1".minimal.override { targets = [ "aarch64-pc-windows-gnullvm" ]; };
        rustPlatform = pkgs.makeRustPlatform { cargo = toolchain; rustc = toolchain; };
        # cc-rs emits an LLVM-style vendor triple which Zig does not parse.
        # Translate only this known target and preserve all other arguments.
        zigCc = pkgs.writeShellScript "table-windows-arm64-cc" ''
          args=()
          for arg in "$@"; do
            case "$arg" in
              --target=aarch64-pc-windows-gnu|--target=aarch64-pc-windows-gnullvm) ;;
              # Zig's ARM64 Windows runtime targets UCRT; it does not provide
              # an ARM64 msvcrt import library. Remove this mapping when the
              # target toolchain supplies that library. Native runtime tests
              # are still required to qualify the ABI mapping.
              -lmsvcrt) args+=("-lucrtbase") ;;
              *) args+=("$arg") ;;
            esac
          done
          exec ${pkgs.zig_0_16}/bin/zig cc -target aarch64-windows-gnu "''${args[@]}"
        '';
        zigAr = pkgs.writeShellScript "table-windows-arm64-ar" ''exec ${pkgs.zig_0_16}/bin/zig ar "$@"'';
      in rustPlatform.buildRustPackage {
        pname = "table-windows-arm64";
        version = "0.1.0";
        src = pkgs.lib.fileset.toSource { root = ./.; fileset = pkgs.lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./LICENSE ./src ]; };
        cargoLock.lockFile = ./Cargo.lock;
        TABLE_RENDERER = "${renderer.packages.${system}.windows-arm64}/bin/tsv-to-ansi-table-zig.exe";
        CC_aarch64_pc_windows_gnullvm = zigCc;
        AR_aarch64_pc_windows_gnullvm = zigAr;
        CARGO_TARGET_AARCH64_PC_WINDOWS_GNULLVM_LINKER = zigCc;
        buildPhase = ''
          runHook preBuild
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
          cargo build --frozen --offline --release --target aarch64-pc-windows-gnullvm
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin" "$out/libexec"
          cp target/aarch64-pc-windows-gnullvm/release/table.exe "$out/bin/table.exe"
          cp "$TABLE_RENDERER" "$out/bin/tsv-to-ansi-table.exe"
          cp "$TABLE_RENDERER" "$out/libexec/tsv-to-ansi-table.exe"
          cp target/aarch64-pc-windows-gnullvm/release/table-perf.exe "$out/libexec/table-perf.exe"
          cp target/aarch64-pc-windows-gnullvm/release/table-memory.exe "$out/libexec/table-memory.exe"
          ${notices}
          runHook postInstall
        '';
        doCheck = false;
        meta = { license = pkgs.lib.licenses.mit; mainProgram = "table"; };
      };
    });
    checks = forAll (system: { package = self.packages.${system}.default; });
  };
}
