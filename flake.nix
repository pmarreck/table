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
    canonicalText = builtins.readFile ./CANONICAL_IMPL;
    canonical = if builtins.match "(rust|zig|roc|luajit)\n?" canonicalText != null
      then builtins.head (builtins.match "(rust|zig|roc|luajit)\n?" canonicalText)
      else throw "CANONICAL_IMPL must contain rust, zig, roc or luajit";
  in {
    packages = forAll (system: let
      pkgs = import nixpkgs { inherit system; };
      rocCompiler = pkgs.lib.findFirst (pkg: (pkg.pname or "") == "roc-nightly")
        (throw "the pinned predecessor must provide its Roc compiler")
        renderer.packages.${system}.default.nativeBuildInputs;
      coreDeps = pkgs.rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };
      unicodeSource = "${coreDeps}/utf8proc-sys-0.1.2/utf8proc";
      pf = { x86_64-linux = "linux-amd64"; aarch64-linux = "linux-arm64"; aarch64-darwin = "macos-arm64"; }.${system};
      about = "table 0.1.0 — Convert tabular data; PF=${pf}${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux " VARIANT=gnu"}";
      rendererBin = "${renderer.packages.${system}.rust}/bin/tsv-to-ansi-table-rust";
      commonNotices = pkgs.runCommand "table-third-party-licenses" { } ''
        {
          cat ${./LICENSE}
          for vendor in ${coreDeps} ${renderer.packages.${system}.rust.cargoDeps}; do
            for crate in "$vendor"/*; do
              [ -d "$crate" ] || continue
              for license in "$crate"/LICENSE* "$crate"/COPYING*; do
                [ -f "$license" ] || continue
                printf '\n\n===== %s / %s =====\n\n' "''${crate##*/}" "''${license##*/}"
                cat "$license"
              done
            done
          done
          cat ${unicodeSource}/LICENSE.md
          cat ${renderer.inputs.random}/LICENSE
          cat ${renderer.packages.${system}.default.ROC_PLATFORM}/THIRD_PARTY_LICENSES.md
          ${rocCompiler}/bin/roc licenses
          cat ${pkgs.luajit.src}/COPYRIGHT
        } > "$out"
      '';
      nativeIo = pkgs.stdenv.mkDerivation {
        pname = "table-native-io"; version = "0.1.0";
        src = ./native;
        buildPhase = ''
          $CC -O2 -fPIC ${if pkgs.stdenv.hostPlatform.isDarwin then "-dynamiclib" else "-shared"} io.c ${unicodeSource}/utf8proc.c -I${unicodeSource} -DUTF8PROC_STATIC -DTABLE_ABOUT='"${about}"' -DTABLE_RENDERER='"${rendererBin}"' -o libtable-native.so
        '';
        installPhase = ''mkdir -p "$out/lib"; cp libtable-native.so "$out/lib/"'';
      };
      luaPackage = pkgs.stdenvNoCC.mkDerivation {
        pname = "table-luajit"; version = "0.1.0";
        src = ./luajit;
        dontBuild = true;
        installPhase = ''
          mkdir -p "$out/bin" "$out/libexec"
          {
            printf '#!${pkgs.luajit}/bin/luajit\n'
            printf '%s\n' 'package.preload.table_config=function() return {native="${nativeIo}/lib/libtable-native.so",renderer="${rendererBin}"} end'
            cat table.lua
          } > "$out/bin/table-luajit"
          chmod +x "$out/bin/table-luajit"
          cp ${rendererBin} "$out/libexec/tsv-to-ansi-table"
          mkdir -p "$out/share/licenses/table"
          cp ${commonNotices} "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
        '';
      };
      rocPackage = pkgs.stdenvNoCC.mkDerivation {
        pname = "table-roc"; version = "0.1.0";
        src = pkgs.lib.fileset.toSource { root = ./.; fileset = ./roc; };
        nativeBuildInputs = [ rocCompiler ];
        buildPhase = ''
          export HOME="$TMPDIR/roc-home" XDG_CACHE_HOME="$TMPDIR/roc-cache"
          mkdir -p "$HOME" "$XDG_CACHE_HOME" "$out/bin" "$out/libexec"
          printf '%s\n' 'BuildInfo :: [].{' 'about = "table 0.1.0 — Convert tabular data; PF=${pf}${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux " VARIANT=musl"}"' 'renderer = "${rendererBin}"' '}' > roc/BuildInfo.roc
          flags=(
            --replace-dep https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst ${renderer.packages.${system}.default.ROC_PLATFORM}/main.roc
            --replace-dep https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst ${renderer.packages.${system}.default.ROC_HTTP}/main.roc
            --replace-dep https://github.com/roc-lang/unicode/releases/download/4.2.0/4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w.tar.zst ${renderer.packages.${system}.default.ROC_UNICODE}/main.roc
          )
          roc check roc/main.roc "''${flags[@]}"
          roc test roc/main.roc --no-cache "''${flags[@]}"
          roc build roc/main.roc --opt=speed --target=${{ x86_64-linux = "x64musl"; aarch64-linux = "arm64musl"; aarch64-darwin = "arm64mac"; }.${system}} --output="$out/bin/table-roc" "''${flags[@]}"
        '';
        installPhase = ''
          cp ${rendererBin} "$out/libexec/tsv-to-ansi-table"
          mkdir -p "$out/share/licenses/table"
          cp ${commonNotices} "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
        '';
      };
      zigPackage = pkgs.stdenvNoCC.mkDerivation {
        pname = "table-zig"; version = "0.1.0";
        src = pkgs.lib.fileset.toSource { root = ./.; fileset = pkgs.lib.fileset.unions [ ./zig ./native ]; };
        nativeBuildInputs = [ pkgs.zig_0_16 ];
        buildPhase = ''
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global" ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local"
          unset NIX_CFLAGS_COMPILE NIX_LDFLAGS
          target=${{ x86_64-linux = "x86_64-linux-musl"; aarch64-linux = "aarch64-linux-musl"; aarch64-darwin = "aarch64-macos"; }.${system}}
          zig build-obj zig/main.zig -lc -OReleaseFast -target "$target" -fcompiler-rt -femit-bin=core.o
          mkdir -p "$out/bin" "$out/libexec"
          zig cc -O3 -target "$target" native/entry.c native/io.c ${unicodeSource}/utf8proc.c core.o -I${unicodeSource} -DUTF8PROC_STATIC -DTABLE_RENDERER='"${rendererBin}"' -DTABLE_ABOUT='"table 0.1.0 — Convert tabular data; PF=${pf}${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux " VARIANT=musl"}"' -o "$out/bin/table-zig"
        '';
        installPhase = ''
          cp ${rendererBin} "$out/libexec/tsv-to-ansi-table"
          mkdir -p "$out/share/licenses/table"
          cp ${commonNotices} "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
        '';
      };
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
          cat ${commonNotices}
        } > "$notice"
      '';
      package = targetPkgs: rendererBin: runChecks: targetPkgs.rustPlatform.buildRustPackage {
        pname = "table";
        version = "0.1.0";
        src = pkgs.lib.fileset.toSource {
          root = ./.;
          fileset = pkgs.lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./LICENSE ./src ./tests ./scripts ./build ./profiling.json ./zig ./roc ];
        };
        cargoLock.lockFile = ./Cargo.lock;
        TEST_PUBLICATION_FIXTURE = "${publicationFixture}";
        TABLE_RENDERER = rendererBin;
        postInstall = ''
          mkdir -p "$out/libexec"
          for probe in table-perf table-memory table-startup; do
            mv "$out/bin/$probe${targetPkgs.stdenv.hostPlatform.extensions.executable}" "$out/libexec/$probe${targetPkgs.stdenv.hostPlatform.extensions.executable}"
          done
          ${pkgs.lib.optionalString runChecks ''
            mv "$out/bin/table" "$out/bin/table-rust"
            ln -s table-rust "$out/bin/table"
            ln -s ${zigPackage}/bin/table-zig "$out/bin/table-zig"
            ln -s ${rocPackage}/bin/table-roc "$out/bin/table-roc"
            ln -s ${luaPackage}/bin/table-luajit "$out/bin/table-luajit"
            install -m755 scripts/table-benchmark.py "$out/libexec/table-benchmark"
            substituteInPlace "$out/libexec/table-benchmark" --replace-fail '#!/usr/bin/env python3' '#!${pkgs.python3}/bin/python3'
          ''}
          cp "$TABLE_RENDERER" "$out/libexec/tsv-to-ansi-table${targetPkgs.stdenv.hostPlatform.extensions.executable}"
          ${if targetPkgs.stdenv.hostPlatform.isWindows then ''
            cp "$TABLE_RENDERER" "$out/bin/tsv-to-ansi-table.exe"
          '' else ''
            ln -s ../libexec/tsv-to-ansi-table "$out/bin/tsv-to-ansi-table"
          ''}
          ${notices}
        '';
        doCheck = runChecks;
        nativeCheckInputs = [ pkgs.perl pkgs.file pkgs.python3 pkgs.cmark-gfm pkgs.zig_0_16 rocCompiler pkgs.nix ];
        postCheck = ''
          bash tests/build-publication.sh
          bash tests/nix-roots.sh
          zig test zig/intermediate.zig -O ReleaseSafe --cache-dir "$TMPDIR/zig-cache" --global-cache-dir "$TMPDIR/zig-global-cache"
          export HOME="$TMPDIR/roc-home" XDG_CACHE_HOME="$TMPDIR/roc-cache"
          mkdir -p "$HOME" "$XDG_CACHE_HOME"
          roc check roc/test.roc
          roc test roc/test.roc --no-cache
          "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table-memory" --self-test
          python3 tests/profiling-declarations.py "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table-perf"
          python3 tests/cli-conformance.py "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table" "$TABLE_RENDERER"
          python3 tests/autodetect.py "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table"
          python3 tests/benchmark-contract.py "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table"
          python3 tests/csv-oracle.py "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table"
          python3 tests/markdown-oracle.py "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table"
          ${pkgs.lib.optionalString runChecks ''
            rust_binary="$PWD/target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table"
            cli_test=""
            for candidate in target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/deps/cli-*; do
              if [[ -f "$candidate" && -x "$candidate" && "$candidate" != *.d ]]; then cli_test="$PWD/$candidate"; fi
            done
            [[ -n "$cli_test" ]] || { echo 'missing compiled CLI acceptance harness' >&2; exit 1; }
            for binary in "$rust_binary" ${zigPackage}/bin/table-zig ${rocPackage}/bin/table-roc ${luaPackage}/bin/table-luajit; do
              TABLE_TEST_BINARY="$binary" "$cli_test" --test-threads=1
              python3 tests/cli-conformance.py "$binary" "$TABLE_RENDERER"
              python3 tests/autodetect.py "$binary"
              python3 tests/csv-oracle.py "$binary"
              python3 tests/markdown-oracle.py "$binary"
              python3 tests/benchmark-contract.py "$binary"
            done
            python3 tests/parity.py "$rust_binary" ${zigPackage}/bin/table-zig ${rocPackage}/bin/table-roc ${luaPackage}/bin/table-luajit
          ''}
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
          "$out/libexec/table-startup" startup-1 1 check > "$TMPDIR/startup-check.out"
          grep -q '^performance-ready/v1$' "$TMPDIR/startup-check.out"
        '';
        meta = {
          license = pkgs.lib.licenses.mit;
          mainProgram = "table";
          platforms = if targetPkgs.stdenv.hostPlatform.system == "aarch64-windows" then [ "aarch64-windows" ] else pkgs.lib.platforms.all;
        };
      };
      rustPackage = package (if pkgs.stdenv.hostPlatform.isLinux then pkgs.pkgsStatic else pkgs) "${renderer.packages.${system}.rust}/bin/tsv-to-ansi-table-rust" true;
      bundle = implementation: pkgs.symlinkJoin {
        name = "table-${implementation}-default";
        paths = [ rustPackage ];
        postBuild = ''
          unlink "$out/bin/table"
          ln -s table-${implementation} "$out/bin/table"
          "$out/bin/table" --about | grep -Fq 'PF=${pf}'
        '';
        meta = { license = pkgs.lib.licenses.mit; mainProgram = "table"; };
      };
    in {
      luajit = luaPackage;
      roc = rocPackage;
      zig = zigPackage;
      rust = rustPackage;
      profiling-tool = renderer.inputs.performance-profiling.packages.${system}.default;
      default = bundle canonical;
    } // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
      linux-arm64-cross = package pkgs.pkgsCross.aarch64-multiplatform-musl "${renderer.packages.${system}.linux-arm64}/bin/tsv-to-ansi-table-zig" false;
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
          cp target/aarch64-pc-windows-gnullvm/release/table-startup.exe "$out/libexec/table-startup.exe"
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
