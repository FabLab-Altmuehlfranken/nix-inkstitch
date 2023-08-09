# Ink/Stitch for nix
This repository is a [nix flake](https://nixos.org/manual/nix/stable/command-ref/new-cli/nix3-flake.html) for the [Ink/Stitch](https://inkstitch.org/) [Inkscape](https://inkscape.org/) extension.
It can be used to create designs for machine embroidery.

The flake provides the binary `inkscape-inkstitch`,
where you can find Ink/Stitch in the *Extensions* menu.
Installing this flake will **not** add Ink/Stitch to you **default** inkscape installation.

Run with:

```bash
nix run git+https://codeberg.org/tropf/nix-inkstitch
```

nix will offer to add `https://nix-serve.hq.c3d2.de` as a binary cache.
Answering **yes** is **recommended**, in order to avoid long builds (30+ min) on your local machine.

> Parts of the software stack of Ink/Stitch are horribly outdated,
> and this flake is *very* hacky.
> I highly recommend to not install it permanently on your system.

Color Palette installation is not supported.

## Notes on Packaging
As user you should use the `inkscape-inkstitch` package.
It is configured as default.
The flake also contains further packages for internal use/debugging.
The following packages are available (see `nix flake show`):

- `inkscape-inkstitch`: inkscape bundled with Ink/Stitch
- `pyembroidery`: python embroidery library, pulled from PyPI (does **not** use the version bundled with Ink/Stitch)
- `pyembroidery-python`: a python environment where `pyembroidery` is available
- `inkstitch`: Ink/Stitch itself (only the inkscape extension)
- `inkstitch-electron`: helper for electron invocation

The packaging follows [the official guide for manual setup](https://inkstitch.org/developers/inkstitch/manual-setup/).
It consists of the following main parts:

1. Prepare Python environment (including the `pyembroidery` library)
2. Build the electron app (in `electron/` upstream)
3. Generate the `.inx` files

For this to properly work on nix, several patches are required.
Please refer to the [`patches/` subdirectory](patches/) of this flake.

- patches applied:
  - some path search includes `/usr`-paths, this is removed
  - `trimesh` include causes deprecation warnings, those are silenced
  - fix JS dependencies: fix reference in `package.json`, update `yarn.lock`
  - silence all warnings as soon as flask is imported, as silencing using `PYTHONWARNINGS` did not work
- Electron is used for some of the GUI, notably color palette installation and simulation/preview.
  This part of the package is thrown together and rather wonky, in particular:
  - The build process of Ink/Stitch is 1) generate `main.js` via vue-electron, then 2) package with `electron-builder`.
    This flake generates `main.js`, but never bundles it into a standalone binary.
    The nix-provided `electron` binary is used to launch the application.
    For that build script and invocation are patched.
  - As the used electron version is replaced by the one from nix which is significantly newer,
    the newer and more secure defaults cause the GUI to break.
    Consequently, these security features are disabled (via a patch).
  - The port is not communicated correctly to the electron application.
    As a dirty fix, the connection port (5000) is hardcoded.
    (Note that it was hardcoded in the python part previously already.)
  - During my tests the vue router ran into an infinite recursion issue.
    This is fixed by removing all routes, which disabled palette installation.

## Troubleshooting
- Is there an Inkstitch in `~/.config/inkscape/extensions/`?
  If yes, remove -- both inkstitches conflict.
- The electron window stays blank.
  Open dev tools (Ctrl-Shift-I), check console output. If in doubt please open an issue.
- Inkscape is unresponsive when Ink/Stitch is open.
  This is known and wont be fixed.

## License
The code in this repository is licensed under [GPLv3 or later](./COPYING).
Please note that the libraries referenced by this flake may use a different license.
