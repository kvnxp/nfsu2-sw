# Next Steps for Building NFSU2 Recompilation on macOS M1

After completing the installations and modifying CMakeLists.txt as described in `PORTING_MACOS_M1.md`, follow these steps to build and run the project:

## 1. Obtain Game Data
You need an extracted copy of the Xbox NTSC-U version of Need for Speed: Underground 2.
- Extract the ISO to a directory containing `default.xbe` and the `NFSUNDER/` folder.
- Example directory structure:
  ```
  /path/to/game/
  ├── default.xbe
  └── NFSUNDER/
      ├── ...
  ```

## 2. Generate Lifted Code
Use the `tools/regen.sh` script to lift the XBE to C code. This step requires the XBE and will generate approximately 100 MB of C source code.

```bash
# Replace /path/to/game with your actual game directory
export NFSU2_XBE=/path/to/game/default.xbe
# Choose a directory for the generated code (will be created if it doesn't exist)
export NFSU2_GEN_DIR=/path/to/gen
tools/regen.sh
```

> **Note**: The generated code is large and not included in the repository. Do not commit it.

## 3. Configure the Build
Run CMake to generate the build system, pointing to the generated code directory and enabling Vulkan.

```bash
cmake -S . -B build -G Ninja \
  -DNFSU2_VULKAN=ON \
  -DNFSU2_GEN_DIR=/path/to/gen
```

## 4. Build the Project
Compile the executable using Ninja (or your chosen generator).

```bash
cmake --build build
```

## 5. Run the Game
Set the Vulkan ICD to point to MoltenVK (installed via Homebrew) and specify the game directory.

```bash
# Point to MoltenVK's ICD JSON
export VK_ICD_FILENAMES=$(brew --prefix moltenvk)/share/vulkan/icd.d/MoltenVK_icd.json

# Run the game (replace /path/to/game with your game directory)
NFSU2_GAME_DIR=/path/to/game ./build/nfsu2_recomp
```

## 6. Optional Settings
Adjust performance and behavior via environment variables or `nfsu2x_env.txt` (on macOS, you can use environment variables). See the [Configuration](#configuration) section in the README for details.

### Common Settings
- `RECOMP_GL_SCALE=1.5`: Increase render resolution (requires more GPU power).
- `RECOMP_WIDESCREEN=0`: Disable widescreen mode (use 4:3).
- `NFSU2_SIM_STEPS=3`: Reduce maximum simulation steps per frame (may slow races but improve consistency).
- `RECOMP_FRAME_LAG=1`: Enable frame lag reduction (may increase FPS at the cost of input lag).

### Example
```bash
RECOMP_GL_SCALE=1.2 NFSU2_SIM_STEPS=3 ./build/nfsu2_recomp
```

## Troubleshooting
- **Vulkan not found**: Ensure MoltenVK is installed (`brew install molten-vk`) and that `VK_ICD_FILENAMES` is set correctly.
- **Generated code missing**: Double-check `NFSU2_GEN_DIR` points to the directory containing `recomp_*.c` and `recomp_funcs.h`.
- **Shader compilation errors**: The Vulkan renderer uses GLSL shaders compiled via glslang. Ensure your system has a working glslang installation (usually provided by the Vulkan SDK).
- **Performance issues**: Initial runs may be slower as the pipeline cache builds. Subsequent runs should be faster.

## Notes
- The Vulkan renderer on macOS uses MoltenVK, which translates Vulkan calls to Metal. This provides excellent compatibility with Apple Silicon and access to Metal's performance and debugging tools.
- OpenGL is not recommended on macOS due to deprecation and lack of optimization from Apple.
- The Switch build uses a similar Vulkan path (with NVK instead of MoltenVK), so much of the Vulkan renderer code is shared.

Enjoy playing NFSU2 on your M1 Mac! 🚀