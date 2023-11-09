{
  description = "inkscape with inkstitch";

  inputs = {
    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    nixpkgs = {
      url = "github:nixos/nixpkgs/nixos-22.11";
    };
  };

  outputs = { self, nixpkgs, ... }:
    {
      overlays.default = selfpkgs: pkgs: let
        inkscape_python = let
          is_python_env = drv: (pkgs.lib.strings.hasPrefix "python3-" drv.name &&
                                pkgs.lib.strings.hasSuffix "-env" drv.name);
          inkscape_python = pkgs.lib.lists.findSingle
            is_python_env
            "none"
            "multiple"
            pkgs.inkscape.nativeBuildInputs;
        in assert pkgs.lib.isDerivation inkscape_python; inkscape_python;
        inkstitch_version = "3.0.1";
        pyembroidery_version = "1.4.36";
        inkstitch_src_upstream = pkgs.fetchzip {
          url = "https://github.com/inkstitch/inkstitch/archive/refs/tags/v${inkstitch_version}.tar.gz";
          sha256 = "sha256-AC5D8l8GTg9tw7wVUCVI+WybsL4igpuqsGkCFlxI17s=";
        };

        inkstitch_src = pkgs.applyPatches {
          src = inkstitch_src_upstream;
          patches = [
            ./patches/0001-silence-warnings.patch
            ./patches/0002-always-invoke-plugin-as-in-manual-install.patch
            ./patches/0003-fix-path-search.patch
            ./patches/0004-disable-electron-sandboxing.patch
            ./patches/0005-rework-electron-build-and-invocation.patch
            ./patches/0006-electron-fix-route-detection.patch
            ./patches/0007-re-enable-menu-in-electron.patch
            ./patches/0008-add-flaskserverport.json.patch
            ./patches/0009-add-yarn.lock.patch
          ];
        };

        inkstitch_electron_yarn_modules = pkgs.mkYarnPackage rec {
          pname = "inkstitch-yarn-deps";
          version = "${inkstitch_version}";
          src = "${inkstitch_src}/electron";
          packageJSON = "${src}/package.json";
          yarnLock = "${src}/yarn.lock";
        };

        inkstitch_python_env = given_pyembroidery: inkscape_python.withPackages (ps: [
          # inkstitch-owned python module -- must be given as argument!!
          given_pyembroidery

          # copied by hand from requirements.txt
          ps.inkex
          ps.wxPython_4_1
          ps.networkx
          ps.shapely
          ps.lxml
          ps.appdirs
          ps.numpy
          ps.jinja2
          ps.requests
          ps.colormath
          ps.stringcase
          ps.tinycss2
          ps.flask
          ps.fonttools
          ps.trimesh
          ps.scipy
          ps.diskcache
          ps.flask-cors
        ]);
      in {
        pyembroidery = with inkscape_python.pkgs; buildPythonPackage rec {
          pname = "pyembroidery";
          version = pyembroidery_version;
          src = fetchPypi {
            inherit pname version;
            sha256 = "sha256-GkEoxmdhjehd+ECrcJE7vVvRlnvk6qasO3NnCGlB/VQ=";
          };
          doCheck = false;
        };

        pyembroidery-python = inkstitch_python_env selfpkgs.pyembroidery;

        inkstitch-electron = pkgs.writeShellScriptBin "inkstitch-electron" ''
          ${pkgs.electron}/bin/electron $@
        '';

        inkstitch = pkgs.stdenv.mkDerivation rec {
          pname = "inkstitch";
          version = "${inkstitch_version}";
          src = inkstitch_src;

          # to overwrite version string
          GITHUB_REF = "${inkstitch_version}-nix";
          BUILD = "NixOS";

          nativeBuildInputs = with pkgs; [
            # for python dependencies, hand-copied requirements.txt
            selfpkgs.pyembroidery-python

            # JS stuff
            yarn
            nodejs

            # undocumented build dependencies
            gettext
            which
          ];

          propagatedBuildInputs = with pkgs; [
            # pre-built yarn modules (circumvent required internet access of yarn/npm during build)
            inkstitch_electron_yarn_modules

            # used at runtime (see patches above)
            selfpkgs.inkstitch-electron
          ];

          preBuild = ''
            ln -sf ${inkstitch_electron_yarn_modules}/libexec/inkstitch-gui/node_modules electron/node_modules
          '';

          buildPhase = ''
            runHook preBuild

            # required for openssl 3.0
            export NODE_OPTIONS=--openssl-legacy-provider

            yarn --cwd electron just-build
            make inx

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
          nativeBuildInputs = with pkgs; [ makeWrapper findutils ];

          postBuild = ''
            export SITE_PACKAGES=$(find "${inkstitch_python_env selfpkgs.pyembroidery}" -type d -name 'site-packages')
            rm -f $out/bin/inkscape
            makeWrapper "${pkgs.inkscape}/bin/inkscape" "$out/bin/inkscape-inkstitch" \
              --set INKSCAPE_DATADIR "$out/share" \
              --prefix PYTHONPATH ":" "$SITE_PACKAGES" \
              --prefix PATH ":" "${selfpkgs.inkstitch-electron}/bin"
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
