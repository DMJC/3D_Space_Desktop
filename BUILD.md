# GNUstep Build and Run

## Linux / GNUstep

```bash
source /usr/share/GNUstep/Makefiles/GNUstep.sh
make
./obj/SceneViewer.app/SceneViewer scene.txt
```

## scene.txt format

- `camera=x,y,z`
- `textureRoot=/path/to/shared/textures`
- `skybox=skybox_name` (optional; uses `skybox_name01` to `skybox_name06`)
- `showLoops=true|false`
- `model=/path/to/model.pof,x,y,z[,ovalpath=true,radius=30,speed=40,offset=0]`

## Behavior

- Camera is defined in scene file and should point toward scene center.
- Missing POF file path uses a red placeholder cube position.
- `showLoops=true` enables 3px red orbital path overlays.
- Target texture formats are `.dds`, `.png`, and `.pcx` from the shared `textureRoot`.
