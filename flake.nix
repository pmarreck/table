{
  description = "Table format converter";
  # Wrappers override this raw input with captured Git metadata. By default it
  # follows the project source, keeping local paths out of the lock file.
  inputs.build-info = { follows = ""; flake = false; };
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/9fbb54b33e91ee4ca368e35a78e0613c720600b3";
  inputs.renderer = {
    url = "github:pmarreck/tsv_to_ansi_table/aa7cdef0cad4dab6c33a3188ed723faba5436ff1";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  inputs.rust-overlay = {
    url = "github:oxalica/rust-overlay/8bbfc858c7b85f5e6ed6d6cc201ffcee1bb08a9b";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  outputs = { self, nixpkgs, renderer, rust-overlay, build-info }: let
    provenanceFile = if builtins.pathExists "${build-info}/build.json"
      then "${build-info}/build.json" else ./nix/build-info/build.json;
    provenance = builtins.fromJSON (builtins.readFile provenanceFile);
    sourceCommit = self.rev or (if self ? dirtyRev then builtins.substring 0 40 self.dirtyRev else null);
    revision = if provenance.available then
      assert builtins.match "[0-9a-f]{40}" provenance.commit != null;
      assert builtins.match "[0-9a-f]{40}" provenance.primary_base != null;
      assert builtins.isInt provenance.count && provenance.count > 0;
      assert builtins.isBool provenance.dirty;
      assert sourceCommit == null || sourceCommit == provenance.commit;
      assert sourceCommit == null || provenance.dirty == (self ? dirtyRev);
      "r${toString provenance.count}-${builtins.substring 0 6 provenance.commit}"
      else "provenance-unavailable";
    buildLabel = "BUILD=${revision}${if provenance.available && provenance.dirty then " DIRTY=1" else ""}";
    systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" ];
    forAll = nixpkgs.lib.genAttrs systems;
    canonicalText = builtins.readFile ./CANONICAL_IMPL;
    canonical = if builtins.match "(rust|zig|roc|luajit)\n?" canonicalText != null
      then builtins.head (builtins.match "(rust|zig|roc|luajit)\n?" canonicalText)
      else throw "CANONICAL_IMPL must contain rust, zig, roc or luajit";
  in {
    packages = forAll (system: let
      pkgs = import nixpkgs { inherit system; };
      buildInfo = pkgs.writeText "table-build-info.json" (builtins.toJSON (provenance // { inherit revision; }));
      stamp = ''
        mkdir -p "$out/share/table"
        cp ${buildInfo} "$out/share/table/BUILD-INFO.json"
      '';
      rust-bin = rust-overlay.lib.mkRustBin { } pkgs;
      toolchainFor = targets: rust-bin.stable."1.100.0".minimal.override { inherit targets; };
      platformFor = targetPkgs: targetPkgs.makeRustPlatform {
        cargo = toolchainFor [ targetPkgs.stdenv.hostPlatform.rust.rustcTarget ];
        rustc = toolchainFor [ targetPkgs.stdenv.hostPlatform.rust.rustcTarget ];
      };
      profilingTool = renderer.inputs.performance-profiling.packages.${system}.default;
      luaTools = pkgs.luajit.withPackages (p: [ p.lua-cjson p.luv ]);
      armPkgs = import nixpkgs { system = "aarch64-linux"; };
      armLuaTools = pkgs.buildEnv {
        name = "table-arm64-lua-test-tools";
        paths = [ armPkgs.luajit armPkgs.luajit.pkgs.lua-cjson armPkgs.luajit.pkgs.luv ];
        pathsToLink = [ "/bin" "/lib/lua" "/share/lua" ];
      };
      csvOracle = (platformFor pkgs).buildRustPackage {
        pname = "table-csv-oracle"; version = "0.1.0";
        src = ./tests/csv-oracle;
        cargoLock.lockFile = ./tests/csv-oracle/Cargo.lock;
      };
      markdownCells = pkgs.runCommand "table-markdown-cells" {
        nativeBuildInputs = [ pkgs.stdenv.cc pkgs.pkg-config ];
        buildInputs = [ pkgs.libxml2 ];
      } ''
        mkdir -p "$out/bin"
        $CC ${./tests/markdown-cells.c} $(pkg-config --cflags --libs libxml-2.0) -o "$out/bin/table-markdown-cells"
      '';
      rocCompiler = pkgs.lib.findFirst (pkg: (pkg.pname or "") == "roc-nightly")
        (throw "the pinned predecessor must provide its Roc compiler")
        renderer.packages.${system}.default.nativeBuildInputs;
      coreDeps = pkgs.rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };
      unicodeSource = "${coreDeps}/utf8proc-sys-0.1.2/utf8proc";
      wasm = import ./wasm { inherit pkgs renderer toolchainFor unicodeSource buildInfo; nativeCli = bundle canonical; };
      web = import ./web { inherit pkgs renderer wasm unicodeSource coreDeps buildInfo buildLabel; nativeCli = bundle canonical; };
      pf = { x86_64-linux = "linux-amd64"; aarch64-linux = "linux-arm64"; aarch64-darwin = "macos-arm64"; }.${system};
      about = "table 0.1.0 — Convert tabular data; PF=${pf}${pkgs.lib.optionalString pkgs.stdenv.hostPlatform.isLinux " VARIANT=gnu"} ${buildLabel}";
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
      nativeIoFor = targetPkgs: platform: rendererExe: targetPkgs.stdenv.mkDerivation {
        pname = "table-native-io"; version = "0.1.0";
        src = ./native;
        buildPhase = ''
          $CC -O2 -fPIC ${if targetPkgs.stdenv.hostPlatform.isDarwin then "-dynamiclib" else "-shared"} io.c ${unicodeSource}/utf8proc.c -I${unicodeSource} -DUTF8PROC_STATIC -DTABLE_ABOUT='"table 0.1.0 — Convert tabular data; PF=${platform}${pkgs.lib.optionalString targetPkgs.stdenv.hostPlatform.isLinux " VARIANT=gnu"} ${buildLabel}"' -DTABLE_RENDERER='"${rendererExe}"' -o libtable-native.so
        '';
        installPhase = ''mkdir -p "$out/lib"; cp libtable-native.so "$out/lib/"'';
      };
      luaPackageFor = targetPkgs: platform: rendererExe: let
        nativeIo = nativeIoFor targetPkgs platform rendererExe;
      in pkgs.stdenvNoCC.mkDerivation {
        pname = "table-luajit"; version = "0.1.0";
        src = ./luajit;
        dontBuild = true;
        installPhase = ''
          mkdir -p "$out/bin" "$out/libexec"
          {
            printf '#!${targetPkgs.luajit}/bin/luajit\n'
            printf '%s\n' 'package.preload.table_config=function() return {native="${nativeIo}/lib/libtable-native.so",renderer="${rendererExe}"} end'
            cat table.lua
          } > "$out/bin/table-luajit"
          chmod +x "$out/bin/table-luajit"
          cp ${rendererExe} "$out/libexec/tsv-to-ansi-table"
          mkdir -p "$out/share/licenses/table"
          cp ${commonNotices} "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
          ${stamp}
        '';
      };
      luaPackage = luaPackageFor pkgs pf rendererBin;
      windowsLuaPackage = let
        targetPkgs = pkgs.pkgsCross.mingwW64;
        lua = targetPkgs.luajit.overrideAttrs (old: {
          # Upstream's Unix install rule does not install the Windows DLL.
          postInstall = (old.postInstall or "") + ''
            cp src/lua51.dll "$out/bin/lua51.dll"
          '';
        });
        windowsRenderer = "${renderer.packages.${system}.windows-x86_64}/bin/tsv-to-ansi-table-zig.exe";
      in targetPkgs.stdenv.mkDerivation {
        pname = "table-luajit-windows-amd64"; version = "0.1.0";
        src = pkgs.lib.fileset.toSource { root = ./.; fileset = pkgs.lib.fileset.unions [ ./native ./luajit ]; };
        nativeBuildInputs = [ pkgs.xxd ];
        buildPhase = ''
          mkdir -p "$out/bin" "$out/libexec"
          printf '%s\n' 'package.preload.table_config=function() return {native="table-native.dll",renderer="tsv-to-ansi-table.exe"} end' > table-script.lua
          cat luajit/table.lua >> table-script.lua
          xxd -i table-script.lua > table-script.h
          $CC -O2 native/luajit-main.c -I. -I${lua}/include/luajit-2.1 ${lua}/bin/lua51.dll -o "$out/bin/table-luajit.exe"
          $CC -O2 -shared native/io.c ${unicodeSource}/utf8proc.c -I${unicodeSource} -DUTF8PROC_STATIC -Wl,--export-all-symbols -DTABLE_ABOUT='"table 0.1.0 — Convert tabular data; PF=mswin-amd64 ${buildLabel}"' -DTABLE_RENDERER='"tsv-to-ansi-table.exe"' -o "$out/bin/table-native.dll"
        '';
        installPhase = ''
          cp ${lua}/bin/lua51.dll "$out/bin/"
          cp ${windowsRenderer} "$out/libexec/tsv-to-ansi-table.exe"
          cp ${windowsRenderer} "$out/bin/tsv-to-ansi-table.exe"
          mkdir -p "$out/share/licenses/table"
          cp ${commonNotices} "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
          ${stamp}
        '';
      };
      rocPackageFor = target: platform: rendererExe: pkgs.stdenvNoCC.mkDerivation {
        pname = "table-roc"; version = "0.1.0";
        src = pkgs.lib.fileset.toSource { root = ./.; fileset = ./roc; };
        nativeBuildInputs = [ rocCompiler ];
        buildPhase = ''
          export HOME="$TMPDIR/roc-home" XDG_CACHE_HOME="$TMPDIR/roc-cache"
          mkdir -p "$HOME" "$XDG_CACHE_HOME" "$out/bin" "$out/libexec"
          printf '%s\n' 'BuildInfo :: [].{' 'about = "table 0.1.0 — Convert tabular data; PF=${platform}${pkgs.lib.optionalString (pkgs.lib.hasSuffix "musl" target) " VARIANT=musl"} ${buildLabel}"' 'renderer = "${rendererExe}"' '}' > roc/BuildInfo.roc
          flags=(
            --replace-dep https://github.com/roc-lang/basic-cli/releases/download/0.25.0/CZsY7tYZwR3rj9kYbpaCfxki2yVAaRL8bBwMLvB2xkbA.tar.zst ${renderer.packages.${system}.default.ROC_PLATFORM}/main.roc
            --replace-dep https://github.com/roc-lang/http/releases/download/1.0.0/6ZUwqYhCS8PU9Mo6MF7oV82ET2o7KYb57CLKDq4cq4sS.tar.zst ${renderer.packages.${system}.default.ROC_HTTP}/main.roc
            --replace-dep https://github.com/roc-lang/unicode/releases/download/4.2.0/4W8SHzvwet9hH9qZewJ1J1CVQoH7YKA6zyijWFTB3y1w.tar.zst ${renderer.packages.${system}.default.ROC_UNICODE}/main.roc
          )
          roc check roc/main.roc "''${flags[@]}"
          roc test roc/main.roc --no-cache "''${flags[@]}"
          roc build roc/main.roc --opt=speed --target=${target} --output="$out/bin/table-roc${pkgs.lib.optionalString (pkgs.lib.hasSuffix "win" target) ".exe"}" "''${flags[@]}"
        '';
        installPhase = ''
          cp ${rendererExe} "$out/libexec/tsv-to-ansi-table${pkgs.lib.optionalString (pkgs.lib.hasSuffix "win" target) ".exe"}"
          mkdir -p "$out/share/licenses/table"
          cp ${commonNotices} "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
          ${stamp}
        '';
      };
      rocPackage = rocPackageFor { x86_64-linux = "x64musl"; aarch64-linux = "arm64musl"; aarch64-darwin = "arm64mac"; }.${system} pf rendererBin;
      zigPackageFor = target: platform: rendererExe: pkgs.stdenvNoCC.mkDerivation {
        pname = "table-zig"; version = "0.1.0";
        src = pkgs.lib.fileset.toSource { root = ./.; fileset = pkgs.lib.fileset.unions [ ./zig ./native ]; };
        nativeBuildInputs = [ pkgs.zig_0_16 ];
        buildPhase = ''
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global" ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local"
          unset NIX_CFLAGS_COMPILE NIX_LDFLAGS
          target=${target}
          zig build-obj zig/main.zig -lc -OReleaseFast -target "$target" -fcompiler-rt -femit-bin=core.o
          mkdir -p "$out/bin" "$out/libexec"
          zig cc -O3 -target "$target" native/entry.c native/io.c ${unicodeSource}/utf8proc.c core.o -I${unicodeSource} -DUTF8PROC_STATIC -DTABLE_RENDERER='"${rendererExe}"' -DTABLE_ABOUT='"table 0.1.0 — Convert tabular data; PF=${platform}${pkgs.lib.optionalString (pkgs.lib.hasSuffix "musl" target) " VARIANT=musl"} ${buildLabel}"' -o "$out/bin/table-zig${pkgs.lib.optionalString (pkgs.lib.hasInfix "windows" target) ".exe"}"
        '';
        installPhase = ''
          cp ${rendererExe} "$out/libexec/tsv-to-ansi-table${pkgs.lib.optionalString (pkgs.lib.hasInfix "windows" target) ".exe"}"
          mkdir -p "$out/share/licenses/table"
          cp ${commonNotices} "$out/share/licenses/table/THIRD_PARTY_LICENSES.txt"
          ${stamp}
        '';
      };
      zigPackage = zigPackageFor { x86_64-linux = "x86_64-linux-musl"; aarch64-linux = "aarch64-linux-musl"; aarch64-darwin = "aarch64-macos"; }.${system} pf rendererBin;
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
        ${stamp}
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
      package = targetPkgs: rendererBin: runChecks: (platformFor targetPkgs).buildRustPackage {
        pname = "table";
        version = "0.1.0";
        src = pkgs.lib.fileset.toSource {
          root = ./.;
          # Browser/WASM harnesses have their own required checks. Their edits
          # must not recompile every native CLI and cross target.
          fileset = pkgs.lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./LICENSE ./src
            (pkgs.lib.fileset.difference ./tests (pkgs.lib.fileset.unions [ ./tests/web.mjs ./tests/wasm.mjs ]))
            (pkgs.lib.fileset.difference ./scripts ./scripts/wasm-benchmark.mjs)
            ./build ./profiling.json ./zig ./roc ];
        };
        cargoLock.lockFile = ./Cargo.lock;
        TEST_PUBLICATION_FIXTURE = "${publicationFixture}";
        TABLE_RENDERER = rendererBin;
        TABLE_BUILD_LABEL = buildLabel;
        # pkgsStatic adds an unqualified -static to C link flags. Upstream
        # rustc uses GNU-host build scripts, so that flag must not reach them.
        # The target's explicit +crt-static Rust flag still controls products.
        preBuild = pkgs.lib.optionalString targetPkgs.stdenv.hostPlatform.isStatic ''
          unset NIX_CFLAGS_LINK
        '';
        # The downloaded compiler executes GNU-host build scripts even for
        # static musl products. Their ELF interpreter must be the host loader.
        env = pkgs.lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
          "NIX_DYNAMIC_LINKER_${builtins.replaceStrings [ "-" ] [ "_" ] pkgs.stdenv.hostPlatform.rust.rustcTarget}" = pkgs.stdenv.cc.bintools.dynamicLinker;
        };
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
            mkdir -p "$out/libexec/table-support"
            cp scripts/harness.lua scripts/benchmark.lua scripts/table-benchmark.lua "$out/libexec/table-support/"
            substituteInPlace "$out/libexec/table-support/harness.lua" \
              --replace-fail '@TABLE_PROFILING_SRC@' '${profilingTool}/share/performance-profile/src' \
              --replace-fail '@TABLE_SHA256@' '${pkgs.coreutils}/bin/sha256sum'
            makeWrapper ${luaTools}/bin/luajit "$out/libexec/table-benchmark" \
              --add-flags "$out/libexec/table-support/table-benchmark.lua"
          ''}
          cp "$TABLE_RENDERER" "$out/libexec/tsv-to-ansi-table${targetPkgs.stdenv.hostPlatform.extensions.executable}"
          ${if targetPkgs.stdenv.hostPlatform.isWindows then ''
            cp "$TABLE_RENDERER" "$out/bin/tsv-to-ansi-table.exe"
          '' else ''
            ln -s ../libexec/tsv-to-ansi-table "$out/bin/tsv-to-ansi-table"
          ''}
          ${notices}
          ${pkgs.lib.optionalString runChecks ''
            {
              printf '\n\n===== LuaJIT benchmark adapter dependencies =====\n\n'
              cat ${pkgs.luajit.pkgs.lua-cjson.src}/LICENSE
              cat ${pkgs.luajit.pkgs.luv.src}/LICENSE.txt
              cat ${pkgs.luajit.pkgs.luv.src}/deps/lua-compat-5.3/LICENSE
              cat ${pkgs.luajit.pkgs.luv.src}/deps/libuv/LICENSE
              cat ${pkgs.luajit.pkgs.luv.src}/deps/libuv/LICENSE-extra
              cat ${renderer.inputs.performance-profiling}/LICENSE
            } >> "$notice"
          ''}
        '';
        doCheck = runChecks;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        nativeCheckInputs = [ pkgs.perl pkgs.file luaTools pkgs.cmark-gfm pkgs.zig_0_16 rocCompiler pkgs.nix pkgs.jq pkgs.git ]
          ++ pkgs.lib.optionals (system == "x86_64-linux") [ pkgs.proot ];
        checkPhase = ''
          runHook preCheck
          cargo test --no-run --frozen --offline --release --target ${targetPkgs.stdenv.hostPlatform.rust.rustcTarget} --message-format=json-render-diagnostics > cargo-tests.json
          cargo test --frozen --offline --release --target ${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}
          runHook postCheck
        '';
        postCheck = ''
          bash tests/build-publication.sh
          bash tests/build-provenance.sh
          bash tests/nix-roots.sh
          zig test zig/intermediate.zig -O ReleaseSafe --cache-dir "$TMPDIR/zig-cache" --global-cache-dir "$TMPDIR/zig-global-cache"
          export HOME="$TMPDIR/roc-home" XDG_CACHE_HOME="$TMPDIR/roc-cache"
          mkdir -p "$HOME" "$XDG_CACHE_HOME"
          roc check roc/test.roc
          roc test roc/test.roc --no-cache
          "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table-memory" --self-test
          export TABLE_PROFILING_SRC=${profilingTool}/share/performance-profile/src
          export TABLE_SHA256=${pkgs.coreutils}/bin/sha256sum
          export TABLE_TEST_SHELL=${pkgs.runtimeShell}
          luajit tests/profiling-declarations.lua "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table-perf" "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table-memory"
          luajit tests/performance-gates.lua "target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table-memory"
          ${pkgs.lib.optionalString runChecks ''
            rust_binary="$PWD/target/${targetPkgs.stdenv.hostPlatform.rust.rustcTarget}/release/table"
            cli_test=$(jq -ser '[.[] | select(.reason == "compiler-artifact" and .target.name == "cli" and .profile.test and .executable != null) | .executable] | unique | if length == 1 then .[0] else error("expected exactly one CLI acceptance harness") end' cargo-tests.json)
            [[ -f "$cli_test" && -x "$cli_test" ]] || { echo 'missing compiled CLI acceptance harness' >&2; exit 1; }
            for binary in "$rust_binary" ${zigPackage}/bin/table-zig ${rocPackage}/bin/table-roc ${luaPackage}/bin/table-luajit; do
              TABLE_TEST_BINARY="$binary" "$cli_test" --test-threads=1
              luajit tests/shared.lua "$binary" "$TABLE_RENDERER" ${csvOracle}/bin/table-csv-oracle ${markdownCells}/bin/table-markdown-cells
            done
            luajit tests/parity.lua "$rust_binary" ${zigPackage}/bin/table-zig ${rocPackage}/bin/table-roc ${luaPackage}/bin/table-luajit
            ${pkgs.lib.optionalString (system == "x86_64-linux") ''
              export TABLE_EMULATION_READONLY=${pkgs.writeText "table-emulation-readonly" "table-emulation-readonly\n"}
              export TABLE_EMULATION_LUA_CPATH='${armLuaTools}/lib/lua/5.1/?.so'
              export TABLE_EMULATION_QEMU=${pkgs.pkgsStatic.qemu-user}/bin/qemu-aarch64
              bash tests/emulated-arm64.sh ${self.packages.${system}.linux-arm64-cli-tests}/bin/table-cli-tests \
                ${self.packages.${system}.linux-arm64-cross}/bin/table \
                ${self.packages.${system}.linux-arm64-zig-cross}/bin/table-zig \
                ${self.packages.${system}.linux-arm64-roc-cross}/bin/table-roc \
                ${self.packages.${system}.linux-arm64-luajit-cross}/bin/table-luajit \
                ${renderer.packages.${system}.linux-arm64}/bin/tsv-to-ansi-table-zig \
                ${csvOracle}/bin/table-csv-oracle ${markdownCells}/bin/table-markdown-cells \
                ${armLuaTools}/bin/luajit
            ''}
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
          ${pkgs.lib.optionalString targetPkgs.stdenv.hostPlatform.isLinux ''
            ${pkgs.lib.getExe pkgs.file} -Lb "$out/bin/table-rust" | grep -Eq 'static(-pie)? linked'
          ''}
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
      csv-oracle = csvOracle;
      wasm-zig = wasm.zig;
      wasm-rust = wasm.rust;
      wasm-renderer = wasm.renderObject;
      wasm-check = wasm.rust;
      web = web.site;
      web-check = web.check;
      web-formatter = pkgs.elmPackages.elm-format;
      wasm-benchmark = web.benchmark;
      default = bundle canonical;
    } // pkgs.lib.optionalAttrs (system == "x86_64-linux") {
      emulation-tools = pkgs.buildEnv {
        name = "table-emulation-tools";
        paths = [ pkgs.proot pkgs.pkgsStatic.qemu-user pkgs.bubblewrap pkgs.bash pkgs.coreutils luaTools pkgs.cmark-gfm ];
      };
      linux-arm64-luajit-cross = luaPackageFor pkgs.pkgsCross.aarch64-multiplatform "linux-arm64" "${renderer.packages.${system}.linux-arm64}/bin/tsv-to-ansi-table-zig";
      linux-arm64-cross = package pkgs.pkgsCross.aarch64-multiplatform-musl "${renderer.packages.${system}.linux-arm64}/bin/tsv-to-ansi-table-zig" false;
      linux-arm64-cli-tests = self.packages.${system}.linux-arm64-cross.overrideAttrs (old: {
        pname = "table-cli-acceptance-arm64";
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.jq ];
        postBuild = (old.postBuild or "") + ''
          cargo test --no-run --test cli --frozen --offline --release --target aarch64-unknown-linux-musl --message-format=json-render-diagnostics > cargo-cli-tests.json
        '';
        installPhase = ''
          mkdir -p "$out/bin"
          harness=$(jq -ser '[.[] | select(.reason == "compiler-artifact" and .target.name == "cli" and .profile.test and .executable != null) | .executable] | unique | if length == 1 then .[0] else error("expected one ARM64 CLI acceptance harness") end' cargo-cli-tests.json)
          test -x "$harness"
          cp "$harness" "$out/bin/table-cli-tests"
        '';
        postInstall = "";
      });
      linux-arm64-zig-cross = zigPackageFor "aarch64-linux-musl" "linux-arm64" "${renderer.packages.${system}.linux-arm64}/bin/tsv-to-ansi-table-zig";
      linux-arm64-roc-cross = rocPackageFor "arm64musl" "linux-arm64" "${renderer.packages.${system}.linux-arm64}/bin/tsv-to-ansi-table-zig";
      windows-amd64-zig-cross = zigPackageFor "x86_64-windows-gnu" "mswin-amd64" "${renderer.packages.${system}.windows-x86_64}/bin/tsv-to-ansi-table-zig.exe";
      windows-arm64-zig-cross = zigPackageFor "aarch64-windows-gnu" "mswin-arm64" "${renderer.packages.${system}.windows-arm64}/bin/tsv-to-ansi-table-zig.exe";
      windows-amd64-luajit-cross = windowsLuaPackage;
      windows-amd64-cross = package pkgs.pkgsCross.mingwW64 "${renderer.packages.${system}.windows-x86_64}/bin/tsv-to-ansi-table-zig.exe" false;
      windows-arm64-cross = let
        toolchain = toolchainFor [ "aarch64-pc-windows-gnullvm" ];
        rustPlatform = pkgs.makeRustPlatform { cargo = toolchain; rustc = toolchain; };
        synchronization = pkgs.runCommand "table-windows-arm64-synchronization" {
          nativeBuildInputs = [ pkgs.zig_0_16 ];
        } ''
          mkdir -p "$out/lib"
          zig dlltool -m arm64 -d ${pkgs.zig_0_16}/lib/zig/libc/mingw/lib-common/api-ms-win-core-synch-l1-2-0.def -l "$out/lib/libsynchronization.a"
        '';
        unwind = pkgs.stdenvNoCC.mkDerivation {
          pname = "table-windows-arm64-unwind"; version = "0.16.0";
          src = "${pkgs.zig_0_16}/lib/zig/libunwind";
          nativeBuildInputs = [ pkgs.zig_0_16 ];
          buildPhase = ''
            export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
            flags=(-target aarch64-windows-gnu -O2 -D_LIBUNWIND_IS_NATIVE_ONLY -D_LIBUNWIND_USE_COMPILER_RT -D_LIBUNWIND_DISABLE_VISIBILITY_ANNOTATIONS -Iinclude -Isrc)
            for file in libunwind Unwind-seh; do
              zig c++ "''${flags[@]}" -std=c++17 -fno-exceptions -fno-rtti -c "src/$file.cpp" -o "$file.o"
            done
            for file in UnwindRegistersRestore UnwindRegistersSave; do
              zig cc "''${flags[@]}" -c "src/$file.S" -o "$file.o"
            done
            for file in UnwindLevel1 UnwindLevel1-gcc-ext; do
              zig cc "''${flags[@]}" -c "src/$file.c" -o "$file.o"
            done
            mkdir -p "$out/lib" "$out/share/licenses"
            zig ar crs "$out/lib/libunwind.a" libunwind.o Unwind-seh.o UnwindRegistersRestore.o UnwindRegistersSave.o UnwindLevel1.o UnwindLevel1-gcc-ext.o
            cp LICENSE.TXT "$out/share/licenses/LLVM-libunwind.txt"
          '';
          dontInstall = true;
        };
        # cc-rs emits an LLVM-style vendor triple which Zig does not parse.
        # Translate only this known target and preserve all other arguments.
        zigCc = pkgs.writeShellScript "table-windows-arm64-cc" ''
          args=()
          needs_unwind=0
          for arg in "$@"; do
            case "$arg" in
              --target=aarch64-pc-windows-gnu|--target=aarch64-pc-windows-gnullvm) ;;
              # Zig's ARM64 Windows runtime targets UCRT; it does not provide
              # an ARM64 msvcrt import library. Remove this mapping when the
              # target toolchain supplies that library. Native runtime tests
              # are still required to qualify the ABI mapping.
              -lmsvcrt) args+=("-lucrtbase") ;;
              # Rust 1.100 links this Windows synchronization API contract.
              # Zig carries its import definition but not this library alias.
              -lsynchronization) args+=("${synchronization}/lib/libsynchronization.a") ;;
              --unwindlib=libunwind) needs_unwind=1; args+=("$arg") ;;
              *) args+=("$arg") ;;
            esac
          done
          if (( needs_unwind )); then args+=("${unwind}/lib/libunwind.a"); fi
          exec ${pkgs.zig_0_16}/bin/zig cc -target aarch64-windows-gnu "''${args[@]}"
        '';
        zigAr = pkgs.writeShellScript "table-windows-arm64-ar" ''exec ${pkgs.zig_0_16}/bin/zig ar "$@"'';
      in rustPlatform.buildRustPackage {
        pname = "table-windows-arm64";
        version = "0.1.0";
        src = pkgs.lib.fileset.toSource { root = ./.; fileset = pkgs.lib.fileset.unions [ ./Cargo.toml ./Cargo.lock ./LICENSE ./src ]; };
        cargoLock.lockFile = ./Cargo.lock;
        TABLE_RENDERER = "${renderer.packages.${system}.windows-arm64}/bin/tsv-to-ansi-table-zig.exe";
        TABLE_BUILD_LABEL = buildLabel;
        nativeBuildInputs = [ pkgs.jq ];
        CC_aarch64_pc_windows_gnullvm = zigCc;
        AR_aarch64_pc_windows_gnullvm = zigAr;
        CARGO_TARGET_AARCH64_PC_WINDOWS_GNULLVM_LINKER = zigCc;
        buildPhase = ''
          runHook preBuild
          export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-cache"
          cargo build --frozen --offline --release --target aarch64-pc-windows-gnullvm --message-format=json-render-diagnostics > cargo-artifacts.json
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p "$out/bin" "$out/libexec"
          artifact() {
            jq -ser --arg name "$1" '[.[] | select(.reason == "compiler-artifact" and .target.name == $name and .executable != null) | .executable] | unique | if length == 1 then .[0] else error("expected exactly one executable artifact") end' cargo-artifacts.json
          }
          cp "$(artifact table)" "$out/bin/table.exe"
          cp "$TABLE_RENDERER" "$out/bin/tsv-to-ansi-table.exe"
          cp "$TABLE_RENDERER" "$out/libexec/tsv-to-ansi-table.exe"
          for probe in table-perf table-memory table-startup; do
            cp "$(artifact "$probe")" "$out/libexec/$probe.exe"
          done
          ${notices}
          cat ${unwind}/share/licenses/LLVM-libunwind.txt >> "$notice"
          runHook postInstall
        '';
        doCheck = false;
        meta = { license = pkgs.lib.licenses.mit; mainProgram = "table"; };
      };
    });
    checks = forAll (system: {
      package = self.packages.${system}.default;
      wasm = self.packages.${system}.wasm-check;
      web = self.packages.${system}.web-check;
    });
  };
}
