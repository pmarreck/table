{ pkgs, renderer, rust-overlay, system, unicodeSource, nativeCli }:
let
  source = pkgs.lib.fileset.toSource {
    root = ../.;
    fileset = pkgs.lib.fileset.unions [ ../Cargo.toml ../Cargo.lock ../src ../zig ../native ../wasm-renderer.zig ../wasm-zig.zig ./protocol.zig ./rust/Cargo.toml ./rust/Cargo.lock ./rust/src ];
  };
  setup = ''
    export ZIG_GLOBAL_CACHE_DIR="$TMPDIR/zig-global" ZIG_LOCAL_CACHE_DIR="$TMPDIR/zig-local"
    unset NIX_CFLAGS_COMPILE NIX_LDFLAGS
  '';
  renderObject = pkgs.stdenvNoCC.mkDerivation {
    pname = "table-wasm-renderer"; version = "0.1.0";
    src = source;
    nativeBuildInputs = [ pkgs.zig_0_16 ];
    buildPhase = setup + ''
      cp -r ${renderer}/zig web-renderer
      mkdir -p "$out/lib"
      zig build-obj wasm-renderer.zig -target wasm32-wasi -O ReleaseFast -lc -I${unicodeSource} -femit-bin="$out/lib/table-renderer.o"
    '';
    dontInstall = true;
  };
  zig = pkgs.stdenvNoCC.mkDerivation {
    pname = "table-wasm-zig"; version = "0.1.0";
    src = source;
    nativeBuildInputs = [ pkgs.zig_0_16 ];
    buildPhase = setup + ''
      mkdir -p "$out"
      zig build-exe wasm-zig.zig ${renderObject}/lib/table-renderer.o native/io.c ${unicodeSource}/utf8proc.c \
        -target wasm32-wasi -O ReleaseFast -lc -fno-entry -rdynamic \
        -DTABLE_UNICODE_ONLY -DUTF8PROC_STATIC -I${unicodeSource} \
        --max-memory=268435456 -femit-bin="$out/table-zig.wasm"
    '';
    dontInstall = true;
  };
  rust-bin = rust-overlay.lib.mkRustBin {} pkgs;
  toolchain = rust-bin.stable."1.97.1".minimal.override { targets = [ "wasm32-wasip1" ]; };
  rustPlatform = pkgs.makeRustPlatform { rustc = toolchain; cargo = toolchain; };
  cc = pkgs.writeShellScript "table-wasm-cc" ''
    args=()
    for arg in "$@"; do
      case "$arg" in
        --target=wasm32-wasip1) ;;
        *) args+=("$arg") ;;
      esac
    done
    exec ${pkgs.zig_0_16}/bin/zig cc -target wasm32-wasi "''${args[@]}"
  '';
  ar = pkgs.writeShellScript "table-wasm-ar" ''exec ${pkgs.zig_0_16}/bin/zig ar "$@"'';
  rust = rustPlatform.buildRustPackage {
    pname = "table-wasm-rust"; version = "0.1.0";
    src = source;
    cargoRoot = "wasm/rust";
    cargoLock.lockFile = ./rust/Cargo.lock;
    nativeBuildInputs = [ pkgs.zig_0_16 pkgs.nodejs ];
    CC_wasm32_wasip1 = cc;
    AR_wasm32_wasip1 = ar;
    buildPhase = setup + ''
      cargo rustc --manifest-path wasm/rust/Cargo.toml --frozen --offline --release --target wasm32-wasip1 -- \
        -C link-arg=${renderObject}/lib/table-renderer.o -C link-arg=--max-memory=268435456
    '';
    doCheck = false; # Executed against the same independent oracle by checks.wasm.
    installPhase = ''mkdir -p "$out"; cp wasm/rust/target/wasm32-wasip1/release/table_web_rust.wasm "$out/table-rust.wasm"'';
    doInstallCheck = true;
    installCheckPhase = ''
      export HOME="$TMPDIR/wasm-home"
      mkdir -p "$HOME"
      node ${pkgs.lib.fileset.toSource { root = ../.; fileset = pkgs.lib.fileset.unions [ ../tests/wasm.mjs ../web/engine.mjs ]; }}/tests/wasm.mjs \
        "$out/table-rust.wasm" ${zig}/table-zig.wasm ${nativeCli}/bin/table-rust
    '';
  };
in { inherit zig rust renderObject; }
