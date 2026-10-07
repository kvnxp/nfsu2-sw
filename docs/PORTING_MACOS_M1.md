# Porting NFSU2 Recompilation to macOS M1

## Analysis

### Why Vulkan + MoltenVK is Preferred Over OpenGL for M1 Mac

1. **OpenGL Deprecation on macOS**:
   - OpenGL has been deprecated since macOS 10.14 (Mojave) and receives no active development or optimization from Apple.
   - Future macOS versions may remove OpenGL support entirely.
   - Apple's OpenGL-over-Metal translation layer is not optimized for complex workloads like this recompiled Xbox game, leading to suboptimal performance and potential compatibility issues.

2. **Advantages of Vulkan + MoltenVK**:
   - **Metal Compatibility**: MoltenVK is a mature, official Vulkan-to-Metal translation layer that translates Vulkan calls directly to efficient Metal commands.
   - **Performance**: Provides near-native Vulkan performance on Apple Silicon by leveraging Metal's optimizations, unlike Apple's OpenGL translation layer.
   - **Future-Proof**: Vulkan is actively supported across platforms (including macOS via MoltenVK), while OpenGL is a dead end on Apple platforms.
   - **Project Readiness**: The project already includes a Vulkan renderer (`xboxrecomp/src/nv2a_vk/`) that has been tested on Linux (lavapipe) and Nintendo Switch (NVK). MoltenVK is another valid Vulkan implementation requiring no code changes.
   - **Tooling**: Benefits from Vulkan debugging tools and Metal's GPU frame capture in Xcode.

3. **OpenGL Attempt Drawbacks**:
   - Would require modifying OpenGL includes (`<GL/gl.h>` → `<OpenGL/gl.h>`) for macOS compatibility.
   - Still reliant on Apple's unoptimized translation layer, risking performance issues and instability.
   - No active maintenance or improvement path from Apple.

**Conclusion**: For M1 Mac, Vulkan + MoltenVK is the only viable long-term solution offering Metal compatibility, performance, and platform support.

---

## Tasks for macOS M1 Port (Vulkan Path)

### 1. Environment Setup
- Install MoltenVK (Vulkan implementation for macOS):
  ```bash
  brew install moltenvk
  ```
- Install SDL2 (required for windowing/audio):
  ```bash
  brew install sdl2
  ```
- (Optional) Install Vulkan validation layers for debugging:
  ```bash
  brew install vulkan-validationlayers
  ```

### 2. CMakeLists.txt Modifications
Add explicit macOS (APPLE) support to handle compiler flags, linker settings, and Vulkan discovery. Insert this block in the `if(WIN32)...elseif()...else()` chain:

```cmake
elseif(APPLE)
    # Optimisation settings (similar to Linux but adjustable for Apple Silicon)
    set(NFSU2_GEN_OPT "-O2" CACHE STRING "Optimisation for the lifted code")
    
    # Handle LTO if enabled (similar to Linux logic)
    if(NFSU2_LTO)
        list(APPEND NFSU2_GEN_FLAGS "-flto=auto")
        set_property(SOURCE src/recomp_manual.c APPEND PROPERTY
            COMPILE_OPTIONS "-flto=auto;-fno-strict-aliasing;-fwrapv")
        target_link_options(${PROJECT_NAME} PRIVATE
            "-flto=${NFSU2_LTO_JOBS}" "-flto-partition=balanced" ${NFSU2_GEN_OPT})
    endif()
    set(NFSU2_GEN_FLAGS "${NFSU2_GEN_OPT};-w;-fno-strict-aliasing;-fwrapv")
    if(NFSU2_LTO)
        list(APPEND NFSU2_GEN_FLAGS "-flto=auto")
    endif()
    set_source_files_properties(${RECOMP_GEN_SOURCES} PROPERTIES
        COMPILE_OPTIONS "${NFSU2_GEN_FLAGS}")
    target_link_libraries(${PROJECT_NAME} PRIVATE m)

    # Vulkan discovery for MoltenVK (when NFSU2_VULKAN=ON)
    if(NFSU2_VULKAN)
        # Homebrew-installed MoltenVK provides Vulkan SDK
        find_package(Vulkan REQUIRED)
        if(Vulkan_FOUND)
            target_include_directories(${PROJECT_NAME} PRIVATE ${Vulkan_INCLUDE_DIRS})
            target_link_libraries(${PROJECT_NAME} PRIVATE ${Vulkan_LIBRARIES})
        else()
            message(FATAL_ERROR "Vulkan not found! Ensure MoltenVK is installed via 'brew install moltenvk'")
        endif()
    endif()
```

### 3. Build Configuration
Configure and build with Vulkan enabled, pointing to MoltenVK's ICD:
```bash
# Set MoltenVK's Vulkan SDK path (Homebrew default)
export VULKAN_SDK=$(brew --prefix moltenvk)/share/vulkan

# Configure CMake
cmake -S . -B build -G Ninja -DNFSU2_VULKAN=ON

# Build
cmake --build build
```

### 4. Execution
Run the game ensuring MoltenVK's ICD is discoverable:
```bash
# Point to MoltenVK's ICD JSON (typically auto-discovered, but explicit is safe)
export VK_ICD_FILENAMES=$(brew --prefix moltenvk)/share/vulkan/icd.d/MoltenVK_icd.json

# Run game (adjust game directory path)
NFSU2_GAME_DIR=/path/to/extracted/game ./build/nfsu2_recomp
```

### 5. Verification & Testing
- Confirm the game launches and reaches the main menu.
- Check for `[perf]` logs showing Vulkan renderer usage and frame rates.
- Validate that car reflections (cube maps) work correctly (a known Vulkan-specific feature).
- Monitor for any MoltenVK-specific warnings in logs (usually benign).

### 6. Troubleshooting Notes
- **MoltenVK ICD Not Found**: Ensure `VK_ICD_FILENAMES` points to the correct `.json` file. Reinstall MoltenVK if needed.
- **Shader Compilation Errors**: The Vulkan renderer uses GLSL shaders compiled via glslang. Ensure the bundled glslang (for Switch) or system glslang works; macOS may require updating the glslang dependency if issues arise.
- **Performance**: Initial frame drops may occur as the pipeline cache builds; subsequent runs should be faster.
- **Audio**: SDL2 audio should work out-of-the-box; check `[AUDIO]` logs for device confirmation.

---

## Notes
- **OpenGL Path Not Recommended**: If attempting OpenGL despite advice, additional changes would be needed in `xboxrecomp/src/nv2a_gl/nv2a_gl.c` to use `<OpenGL/gl.h>` includes, but this path is strongly discouraged.
- **LTO Considerations**: Link-Time Optimization may improve performance but increases build time/memory usage; test with and without `NFSU2_LTO=ON`.
- **Switch Comparison**: The macOS Vulkan build parallels the Switch Vulkan build (both use NVK/MoltenVK as Vulkan implementations), sharing much of the same Vulkan renderer code.

This approach ensures optimal performance, Metal compatibility, and long-term viability on Apple Silicon macOS systems.