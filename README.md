# LibAeonSettings

LibAeonSettings-1.0 is the settings window and edit mode library used by the Aeon addons for World of Warcraft: Forever and Retail (Hearthline first, then Levelbound, AeonUI and Aeon Essentials).

It is a LibStub library. An addon ships LibStub and CallbackHandler-1.0, then includes `LibAeonSettings.xml`:

```xml
<Include file="Libs\LibAeonSettings\LibAeonSettings.xml" />
```

and reaches it with `LibStub("LibAeonSettings-1.0")`.

Releases are plain version tags (`1.0.0`, `1.1.0`, `1.2.0`). Adopting addons fetch the library as a `.pkgmeta` external pinned to a tag:

```yaml
externals:
  Libs/LibAeonSettings:
    url: https://github.com/Aeon234/LibAeonSettings.git
    tag: 1.2.0
```

The interface is still evolving; each tag that changes the code raises the LibStub `MINOR`.
