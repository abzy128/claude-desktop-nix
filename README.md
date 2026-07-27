# claude-desktop-nix

Nix flake for the [Claude desktop app on Linux](https://code.claude.com/docs/en/desktop-linux)
(Chat, Cowork and Claude Code), repackaged from Anthropic's official `.deb`.

Supports `x86_64-linux` and `aarch64-linux`.

## Try it

```sh
nix run github:<you>/claude-desktop-nix
```

## Use it in your flake

```nix
{
  inputs.claude-desktop.url = "github:<you>/claude-desktop-nix";

  # ...

  # Either take the package directly:
  environment.systemPackages = [
    inputs.claude-desktop.packages.${pkgs.system}.default
  ];

  # ...or add the overlay and use pkgs.claude-desktop:
  nixpkgs.overlays = [ inputs.claude-desktop.overlays.default ];
}
```

`nix flake update` in your own flake picks up new app versions, so the desktop
app tracks its releases the same way the rest of your system does.

## How updates work

The app does not self-update on Linux, and Anthropic ships it through an apt
repository that NixOS cannot consume. Instead, a
[scheduled workflow](.github/workflows/update.yml) checks the repository index
hourly and opens an auto-merging PR when a new version appears.

That index publishes a SHA256 for every package, so `scripts/update.sh` reads
hashes straight out of it rather than downloading ~160 MB per architecture to
prefetch them.

Run it by hand with:

```sh
./scripts/update.sh            # update to the newest version
./scripts/update.sh --check    # exit 1 if an update is available
./scripts/update.sh --version 1.24012.9
```

## Notes

- **Unfree.** The app is redistributed under Anthropic's terms, so set
  `nixpkgs.config.allowUnfree = true` (the flake's own `packages` output already
  does).
- **Sandbox.** The bundled `chrome-sandbox` helper needs to be setuid, which is
  impossible inside the Nix store, so it is dropped and the wrapper passes
  `--disable-setuid-sandbox`. Chromium then uses its user-namespace sandbox,
  which works on NixOS as long as `security.allowUserNamespaces` is left at its
  default of `true`.
- **Not in nixpkgs.** As of nixpkgs unstable there is no `claude-desktop`
  attribute, which is why this flake exists.
- **Beta.** Linux support for the desktop app is in beta upstream; Computer Use
  and dictation are not available, and the Quick Entry hotkey needs a
  GlobalShortcuts portal on Wayland.
