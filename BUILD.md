# Build and Run (macOS)

```bash
clang -fobjc-arc -framework Cocoa -framework OpenGL -framework GLKit main.m -o SceneViewer
./SceneViewer scene.txt
```

## `scene.txt` format

- `camera=x,y,z`
- `textureRoot=/path/to/shared/textures`
- `skybox=skybox_name` (optional; uses `skybox_name01` to `skybox_name06`)
- `showLoops=true|false`
- `model=/path/to/model.pof,x,y,z[,ovalpath=true,radius=30,speed=40,offset=0]`

## Notes

- Camera always looks at world origin `(0,0,0)`.
- Intended behavior includes loading POF detail level 0 only.
- Missing `.pof` files fall back to a red cube placeholder.
- Texture support target: `.dds`, `.png`, `.pcx` loaded from `textureRoot`.
- If no skybox is configured, a black space background with stars should be generated.
