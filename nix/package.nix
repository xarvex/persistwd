{
  glibc,
  lib,
  rustPlatform,
}:

let
  manifest = (lib.importTOML ../Cargo.toml).package;
in
rustPlatform.buildRustPackage rec {
  pname = manifest.name;
  inherit (manifest) version;

  src = lib.fileset.toSource {
    root = ../.;
    fileset = lib.fileset.unions [
      ../Cargo.lock
      ../Cargo.toml
      (lib.fileset.fileFilter (
        file:
        builtins.any (ext: lib.strings.hasSuffix ".${ext}" file.name) [
          "h"
          "rs"
        ]
      ) ../.)
    ];
  };
  cargoLock.lockFile = ../Cargo.lock;

  nativeBuildInputs = [ rustPlatform.bindgenHook ];
  buildInputs = [ glibc.dev ];

  meta = {
    inherit (manifest) description;
    homepage = manifest.repository;
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ xarvex ];
    mainProgram = pname;
    platforms = lib.platforms.linux;
  };
}
