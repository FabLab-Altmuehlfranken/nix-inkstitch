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
4. Combine everything through symlinking, add a wrapper to inject required binaries/python dependencies.

For this to properly work on nix, several patches are required.
Please refer to the [`patches/` subdirectory](patches/) of this flake.

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
