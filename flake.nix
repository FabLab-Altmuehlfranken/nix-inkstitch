{
  description = "inkscape with inkstitch";

  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs {system="x86_64-linux";};
      inkscape_python = let
        is_python_env = drv: (pkgs.lib.strings.hasPrefix "python3-" drv.name &&
                              pkgs.lib.strings.hasSuffix "-env" drv.name);
        inkscape_python = pkgs.lib.lists.findSingle
          is_python_env
          "none"
          "multiple"
          pkgs.inkscape.nativeBuildInputs;
      in assert pkgs.lib.isDerivation inkscape_python; inkscape_python;
      inkstitch_version = "2.2.0";
      inkstitch_src = pkgs.fetchzip {
        url = "https://github.com/inkstitch/inkstitch/archive/refs/tags/v${inkstitch_version}.tar.gz";
        sha256 = "sha256-WitR7WDReDSABlDfzwCrNuqxniv0JWRlkn80zvUuq4U=";
      };
      inkstitch_src_patched_yarn_deps = pkgs.applyPatches {
        src = inkstitch_src;
        patches = [ ./patches/update_js_deps.patch ];
      };
      inkstitch_electron_yarn_modules = pkgs.mkYarnPackage rec {
        pname = "inkstitch-yarn-deps";
        version = "${inkstitch_version}";
        src = "${inkstitch_src_patched_yarn_deps}/electron";
        packageJSON = "${src}/package.json";
        yarnLock = "${src}/yarn.lock";
      };
      inkstitch_python_env = given_pyembroidery: inkscape_python.withPackages (ps: [
        # inkstitch-owned python module -- must be given as argument!!
        given_pyembroidery

        # copied by hand from requirements.txt
        ps.backports_functools_lru_cache
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
        ps.six
      ]);
    in
      {
      packages.x86_64-linux.pyembroidery = with inkscape_python.pkgs; buildPythonPackage rec {
        pname = "pyembroidery";
        version = "1.4.36";
        src = fetchPypi {
          inherit pname version;
          sha256 = "sha256-GkEoxmdhjehd+ECrcJE7vVvRlnvk6qasO3NnCGlB/VQ=";
        };
        doCheck = false;
      };

      packages.x86_64-linux.inkstitch = pkgs.stdenv.mkDerivation rec {
        pname = "inkstitch";
        version = "${inkstitch_version}";
        src = inkstitch_src_patched_yarn_deps;

        patches = [
          # looks for /usr/bin etc., then fails -> remove that section
          ./patches/fix_path_correction.patch

          # includes deprecated feature -> don't care
          ./patches/trimesh_silence_deprecation_warning.patch

          # update requires internet connection -> disable update before build
          ./patches/electron_build_no_update.patch

          # electorn got too many security features for inkstitch to work
          # -> disable security features
          ./patches/fix_electron_isolation.patch

          # vue router causes infinite recursion
          # -> remove all routes but one
          ./patches/sledgehammer_fix_vue_router.patch

          # add error message when trying to install
          # (part of electron application, but route got disabled in patch above)
          ./patches/disable_palette_install.patch

          # vue does not correctly load the port -> hardcode it
          ./patches/hardcode_port.patch
          
          # invocation: do not use yarn develop, but instead pass path to electron
          # (yarn develop also calls vue-electron build, which we called already during installation)
          (pkgs.substituteAll {
            electron_full_path = "${pkgs.electron}/bin/electron";
            src = ./patches/electron_fix_invocation.patch.template;
          })
        ];

        nativeBuildInputs = with pkgs; [
          # for python dependencies, hand-copied requirements.txt
          (inkstitch_python_env self.packages.x86_64-linux.pyembroidery)

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
          electron
        ];

        preBuild = ''
            ln -sf ${inkstitch_electron_yarn_modules}/libexec/inkstitch-gui/node_modules electron/node_modules
          '';

        buildPhase = ''
            runHook preBuild

            # patched version: only builds main.js, does not package into full application
            bash bin/build-electron

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
      packages.x86_64-linux.inkscape-inkstitch = pkgs.symlinkJoin {
        name = "inkscape-inkstitch";
        paths = [
          pkgs.inkscape
          self.packages.x86_64-linux.inkstitch 
        ];
        nativeBuildInputs = with pkgs; [ makeWrapper findutils ];

        postBuild = ''
            export SITE_PACKAGES=$(find "${inkstitch_python_env self.packages.x86_64-linux.pyembroidery}" -type d -name 'site-packages')
            rm -f $out/bin/inkscape
            makeWrapper "${pkgs.inkscape}/bin/inkscape" "$out/bin/inkscape-inkstitch" \
              --set INKSCAPE_DATADIR "$out/share" \
              --prefix PYTHONPATH ":" "$SITE_PACKAGES"
          '';
      };

      defaultPackage.x86_64-linux = self.packages.x86_64-linux.inkscape-inkstitch;
    };
}
