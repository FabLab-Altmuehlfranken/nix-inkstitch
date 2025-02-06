{
  description = "inkscape with inkstitch";

  inputs = {
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-unstable";
    };
  };

  outputs = { self, nixpkgs, ... }:
    {
      overlays.default = selfpkgs: pkgs: let
        inkstitch_version = "3.1.0";
        inkstitch_src_upstream = pkgs.fetchFromGitHub {
          owner = "inkstitch";
          repo = "inkstitch";
          rev = "v${inkstitch_version}";
          fetchSubmodules = true; # required to get the embedded pyembroidery
          sha256 = "sha256-rfDkAA3xDiL3TQDLGBpxXstIG6xRVxOdMZDfpyMbhik=";
        };

        inkstitch_src = pkgs.applyPatches {
          src = inkstitch_src_upstream;
          patches = [
            ./patches/0001-force-frozen-true.patch
            ./patches/0002-plugin-invocation-use-python-script-as-entrypoint.patch
          ];
        };

      in {
        pyembroidery = pkgs.python3Packages.buildPythonPackage {
          pname = "pyembroidery";
          version = "bundled-inkstitch-${inkstitch_version}";
          src = "${inkstitch_src}/pyembroidery";
          doCheck = false;
        };

        inkstitch-python-env = pkgs.python3.withPackages (ps: [
          # inkstitch-owned python module
          selfpkgs.pyembroidery

          # copied by hand from requirements.txt

          ps.inkex

          ps.wxpython
          ps.networkx
          ps.shapely
          ps.lxml
          ps.appdirs
          ps.numpy
          ps.jinja2
          ps.requests
          ps.colormath
          ps.flask
          ps.fonttools
          ps.trimesh
          ps.scipy
          ps.diskcache
          ps.flask-cors
        ]);

        inkstitch = pkgs.stdenv.mkDerivation rec {
          pname = "inkstitch";
          version = "${inkstitch_version}";
          src = inkstitch_src;

          env = {
            # to overwrite version string
            GITHUB_REF = "${inkstitch_version}-nix";
            BUILD = "NixOS";
          };

          nativeBuildInputs = with pkgs; [
            # for python dependencies, hand-copied requirements.txt
            selfpkgs.inkstitch-python-env

            # undocumented build dependencies
            gettext
            which

            # for patching the invocation
            gnused
          ];
 
          postPatch = ''
            # The invocation uses the inkscape-bundled python interpreter by default.
            # To supply custom dependencies, one could touch the `$PYTHONPATH` environment variable.
            # This takes a different approach and makes the invoked `inkstitch.py` a "stand-alone" executable.
            # It will get executed just as any other script.
            # The call to sed will then inject a shebang to a python binary will all dependencies available.
            # Finally, the executable bit is set, so this is respected.
            substituteInPlace lib/inx/utils.py --replace-fail ' interpreter="python"' ""
            sed -i -e '1i#!${selfpkgs.inkstitch-python-env}/bin/python' inkstitch.py
            chmod a+x inkstitch.py
          '';

          buildPhase = ''
            runHook preBuild

            make manual

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            export INKSCAPE_PLUGIN_PATH="$out/share/inkscape/extensions"
            mkdir -p $INKSCAPE_PLUGIN_PATH
            cp -r . $INKSCAPE_PLUGIN_PATH/inkstitch
            
            runHook postInstall
          '';
        };


        inkscape-inkstitch = pkgs.symlinkJoin {
          name = "inkscape-inkstitch";
          paths = [
            pkgs.inkscape
            selfpkgs.inkstitch
          ];
          nativeBuildInputs = with pkgs; [ makeWrapper ];

          postBuild = ''
            rm -f $out/bin/inkscape
            makeWrapper "${pkgs.inkscape}/bin/inkscape" "$out/bin/inkscape-inkstitch" \
              --set INKSCAPE_DATADIR "$out/share"
          '';
        };
      };

      packages.x86_64-linux = let
        pkgs = import nixpkgs { system="x86_64-linux"; };
        selfpkgs = self.packages.x86_64-linux;
      in
        (self.overlays.default selfpkgs pkgs) //
        { default = selfpkgs.inkscape-inkstitch; };

      hydraJobs.inkscape-inkstitch.x86_64-linux = self.packages.x86_64-linux.inkscape-inkstitch;
    };
}
