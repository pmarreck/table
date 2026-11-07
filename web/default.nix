{ pkgs, renderer, wasm, unicodeSource, coreDeps, nativeCli }:
let
  printableBinary = renderer.inputs.performance-profiling.inputs.printable-binary;
  elmDeps = import ./elm-deps.nix;
  fetchElm = pkgs.elmPackages.fetchElmDeps {
    elmPackages = elmDeps;
    registryDat = pkgs.path + "/pkgs/development/compilers/elm/registry.dat";
    elmVersion = pkgs.elmPackages.elm.version;
  };
  source = pkgs.lib.fileset.toSource {
    root = ./.;
    fileset = pkgs.lib.fileset.unions [ ./elm.json ./src ./index.html ./style.css ./favicon.svg ./engine.mjs ./worker.mjs ./bridge.mjs ./presentation.mjs ];
  };
  implementationText = builtins.readFile ./WASM_IMPL;
  implementation = if builtins.match "(zig|rust)\n?" implementationText != null
    then builtins.head (builtins.match "(zig|rust)\n?" implementationText)
    else throw "web/WASM_IMPL must contain zig or rust";
  fontConfig = pkgs.makeFontsConf { fontDirectories = [ pkgs.dejavu_fonts pkgs.noto-fonts-cjk-sans ]; };
  browsers = pkgs.playwright-driver.selectBrowsers {
    withChromium = false; withFirefox = false; withWebkit = false; withFfmpeg = false;
    withChromiumHeadlessShell = true;
  };
  site = pkgs.stdenvNoCC.mkDerivation {
    pname = "table-web"; version = "0.1.0";
    src = source;
    nativeBuildInputs = [ pkgs.elmPackages.elm ];
    buildPhase = ''
      runHook preBuild
      ${fetchElm}
      mkdir -p "$out"
      elm make src/Main.elm --optimize --output="$out/elm.js"
      runHook postBuild
    '';
    installPhase = ''
      cp index.html style.css favicon.svg engine.mjs worker.mjs bridge.mjs presentation.mjs "$out/"
      cp ${wasm.${implementation}}/table-${implementation}.wasm "$out/table.wasm"
      cp ${printableBinary}/js/printable_binary.js "$out/printable-binary.mjs"
      cp ${printableBinary}/character_map.txt "$out/"
      touch "$out/.nojekyll"
      {
        cat ${../LICENSE}
        printf '\n===== Pinned table renderer =====\n'
        cat ${renderer}/LICENSE
        printf '\n===== printable-binary =====\n'
        cat ${printableBinary}/LICENSE
        printf '\n===== utf8proc / Unicode =====\n'
        cat ${unicodeSource}/LICENSE.md
        printf '\n===== Zig standard library and WASI libc =====\n'
        cat ${pkgs.zig_0_16.src}/LICENSE
        cat ${pkgs.zig_0_16}/lib/zig/libc/wasi/LICENSE ${pkgs.zig_0_16}/lib/zig/libc/wasi/LICENSE-MIT ${pkgs.zig_0_16}/lib/zig/libc/wasi/LICENSE-APACHE ${pkgs.zig_0_16}/lib/zig/libc/wasi/LICENSE-APACHE-LLVM
        for crate in ${coreDeps}/*; do
          for license in "$crate"/LICENSE* "$crate"/COPYING*; do
            [ -f "$license" ] || continue
            printf '\n===== %s =====\n' "''${crate##*/}"
            cat "$license"
          done
        done
        ${pkgs.lib.optionalString (implementation == "rust") ''
          printf '\nRust standard-library notices are in RUST-LIBRARY-COPYRIGHT.html.\n'
          cp ${wasm.toolchain}/share/doc/rust/COPYRIGHT-library.html "$out/RUST-LIBRARY-COPYRIGHT.html"
        ''}
        ${pkgs.lib.concatStringsSep "\n" (pkgs.lib.mapAttrsToList (name: dep: ''
          printf '\n===== ${name} ${dep.version} =====\n'
          cat "$ELM_HOME/${pkgs.elmPackages.elm.version}/packages/${name}/${dep.version}/LICENSE"
        '') elmDeps)}
      } > "$out/LICENSES.txt"
    '';
    passthru = { inherit implementation; };
  };
  check = pkgs.runCommand "table-web-browser-check" {
    nativeBuildInputs = [ pkgs.nodejs ];
    PLAYWRIGHT_MODULE = "${pkgs.playwright-driver}/index.mjs";
    PLAYWRIGHT_BROWSERS_PATH = browsers;
    FONTCONFIG_FILE = fontConfig;
  } ''
    export HOME="$TMPDIR/home" XDG_CONFIG_HOME="$TMPDIR/config" XDG_CACHE_HOME="$TMPDIR/cache" XDG_DATA_HOME="$TMPDIR/data" XDG_STATE_HOME="$TMPDIR/state"
    mkdir -p "$HOME" "$out"
    node ${../tests/web.mjs} ${site} ${nativeCli}/bin/table-rust "$out"
  '';
  benchmark = pkgs.writeShellApplication {
    name = "table-wasm-benchmark";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      export TABLE_WASM_RUST=${wasm.rust}/table-rust.wasm
      export TABLE_WASM_ZIG=${wasm.zig}/table-zig.wasm
      export TABLE_WASM_ORACLE=${nativeCli}/bin/table-rust
      export TABLE_WASM_ENGINE=${./engine.mjs}
      export PLAYWRIGHT_MODULE=${pkgs.playwright-driver}/index.mjs
      export PLAYWRIGHT_BROWSERS_PATH=${browsers}
      export FONTCONFIG_FILE=${fontConfig}
      exec node ${../scripts/wasm-benchmark.mjs} "$@"
    '';
  };
in { inherit site check benchmark; }
