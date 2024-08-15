{
  description = "Basic haskell cabal template";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs = { self, nixpkgs }:
    let
      forAllSystems = nixpkgs.lib.genAttrs nixpkgs.lib.systems.flakeExposed;
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        overlays = [ self.overlay ];
      });
    in
    {
      overlay = final: prev: {
        hsPkgs = prev.haskell.packages.ghc965.override {
          overrides = hfinal: hprev: { 
            hledger-lib = hprev.hledger-lib.overrideAttrs (oldAttrs: {
              pname = "hledger-lib";
              version = "1.34.99";
              src = hprev.callCabal2nix "hledger-lib" ./hledger-lib/. {};
            });
          };
        };
        hledger = final.hsPkgs.callCabal2nix "hledger" ./hledger/. {};
      };

      packages = forAllSystems(system: 
      let 
        pkgs = nixpkgsFor.${system};
      in {
        default = pkgs.hledger;
      });

      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          libs = with pkgs; [
            zlib
          ];
        in
        {
          default = pkgs.hsPkgs.shellFor {
            packages = hsPkgs: [ ];
            buildInputs = with pkgs; [
              hsPkgs.cabal-install
              hsPkgs.cabal-fmt
              hsPkgs.ghc
              ormolu
              treefmt
              nixpkgs-fmt
              hsPkgs.cabal-fmt
            ] ++ libs;
            shellHook = "export PS1='[$PWD]\n❄ '";
            LD_LIBRARY_PATH = pkgs.lib.makeLibraryPath libs;
          };
        });
    };
}
