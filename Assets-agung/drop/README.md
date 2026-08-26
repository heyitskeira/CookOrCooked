# Drop folder

Figma PNG exports land here, named per `Docs/ArtPipeline.md`, then:

```bash
Tools/import-art.sh
```

The importer moves them into `Cooked/Assets.xcassets`, so this folder should be
empty again afterwards. Anything left behind either failed the name check or has
not been imported yet.
