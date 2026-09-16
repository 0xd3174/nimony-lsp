{
  description = "Nimony LSP & Zed Extension Workspace";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      rust-overlay,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs supportedSystems (system: f system);
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };

          parserNim = pkgs.fetchurl {
            url = "https://raw.githubusercontent.com/nim-lang/Nim/7171e6f01f846a511a5fad8d1ab24baaee66e308/compiler/parser.nim";
            sha256 = "0lxzg1gv21sn5fhyql1nn2c4w6aviq1jgiqp5w80dn0nrzr890ma";
          };

          mimallocSrc = pkgs.fetchFromGitHub {
            owner = "nim-lang";
            repo = "mimalloc";
            rev = "a2b9ee6a3261fd357b83a70712a577da57f926ae";
            sha256 = "1mcivmrab00yfj0jfvr1xw9pi9p9bvf82hjw3rdpr6ps7j88zmn4";
          };

          nimonySrc = pkgs.fetchFromGitHub {
            owner = "nim-lang";
            repo = "nimony";
            rev = "8b368be0eaee24f0c431d1b0d2d3856b6be4bf7a";
            hash = "sha256-iwmdowB5iK5QITf4BMt3S6Toez82nxhZ14GO4u7oULE=";
          };

          nimony = pkgs.stdenv.mkDerivation {
            pname = "nimony";
            version = "0.6.3";
            src = nimonySrc;

            nativeBuildInputs = [
              pkgs.nim
              pkgs.gcc
              pkgs.which
            ];

            buildPhase = ''
              export HOME=$TMPDIR
              mkdir -p vendor/mimalloc
              cp -r ${mimallocSrc}/* vendor/mimalloc/
              chmod -R u+w vendor/mimalloc

              mkdir -p src/nifler/nimparser
              cp ${parserNim} src/nifler/nimparser/parser.nim
              echo "7171e6f01f846a511a5fad8d1ab24baaee66e308" > src/nifler/nimparser/parser.fetched

              nim c -d:release src/hastur/hastur.nim
              ./bin/hastur build all
            '';

            installPhase = ''
              mkdir -p $out/bin $out/lib
              cp -r bin/* $out/bin/
              cp -r lib/* $out/lib/
            '';
          };
        in
        {
          inherit nimony;
          default = nimony;
        }
      );

      devShells = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import rust-overlay) ];
          };
          nimony = self.packages.${system}.nimony;
          rustToolchain = pkgs.rust-bin.stable.latest.default.override {
            targets = [ "wasm32-wasip1" ];
          };
        in
        {
          default = pkgs.mkShell {
            packages = [
              nimony
              pkgs.nim
              pkgs.gcc
              rustToolchain
              pkgs.zed-editor
              pkgs.nixfmt
            ];

            shellHook = ''
              export CC=gcc
            '';
          };
        }
      );

      formatter = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        pkgs.nixfmt
      );
    };
}
