# LibAeonSettings

LibAeonSettings-1.0 is the settings window and edit mode library used by the Aeon addons for World of Warcraft: Forever (Hearthline first, then Levelbound, AeonUI and Aeon Essentials).

It is a LibStub library. An addon ships LibStub and CallbackHandler-1.0, then includes `LibAeonSettings.xml`:

```xml
<Include file="Libs\LibAeonSettings\LibAeonSettings.xml" />
```

and reaches it with `LibStub("LibAeonSettings-1.0")`.

The library is in development and has no public interface yet.
