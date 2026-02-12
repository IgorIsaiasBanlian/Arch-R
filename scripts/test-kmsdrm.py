#!/usr/bin/env python3
"""
Arch R — SDL2 KMSDRM + GL Context diagnostic
Tests SDL_CreateRenderer AND SDL_GL_CreateContext in a SINGLE SDL session.
Test 3 forces eglBindAPI(EGL_OPENGL_ES_API) before context creation.
Run manually: python3 /usr/bin/emulationstation/test-kmsdrm.py
"""
import ctypes
import ctypes.util
import os
import sys
import time

# Force KMSDRM + GLES (not Desktop GL)
os.environ['SDL_VIDEODRIVER'] = 'KMSDRM'
os.environ['SDL_VIDEO_DRIVER'] = 'KMSDRM'
os.environ['SDL_OPENGL_ES_DRIVER'] = '1'
os.environ['SDL_LOGGING'] = '*=verbose'
# DO NOT set MESA_LOADER_DRIVER_OVERRIDE — it breaks kmsro render-offload!
# Mesa auto-detects: card0 (rockchip) → kmsro → finds renderD129 (panfrost)
os.environ.pop('MESA_LOADER_DRIVER_OVERRIDE', None)

print("=" * 60)
print("Arch R KMSDRM + GL Context Diagnostic")
print("=" * 60)

# Load SDL2
try:
    sdl = ctypes.CDLL('libSDL2-2.0.so.0')
except OSError as e:
    print(f"FATAL: Cannot load libSDL2: {e}")
    sys.exit(1)

# Load EGL for direct API binding
try:
    egl = ctypes.CDLL('libEGL.so')
    HAS_EGL = True
    print("libEGL loaded OK")
except OSError as e:
    print(f"WARNING: Cannot load libEGL: {e}")
    HAS_EGL = False

# Set return types
sdl.SDL_CreateWindow.restype = ctypes.c_void_p
sdl.SDL_CreateRenderer.restype = ctypes.c_void_p
sdl.SDL_GL_CreateContext.restype = ctypes.c_void_p
sdl.SDL_GetError.restype = ctypes.c_char_p

# SDL Constants
SDL_INIT_VIDEO = 0x20
SDL_WINDOW_FULLSCREEN = 0x01
SDL_WINDOW_OPENGL = 0x02
SDL_WINDOW_SHOWN = 0x04
SDL_WINDOW_ALLOW_HIGHDPI = 0x2000

# GL attributes (from SDL2 headers)
SDL_GL_RED_SIZE = 0
SDL_GL_GREEN_SIZE = 1
SDL_GL_BLUE_SIZE = 2
SDL_GL_DEPTH_SIZE = 6
SDL_GL_DOUBLEBUFFER = 5
SDL_GL_CONTEXT_MAJOR_VERSION = 17
SDL_GL_CONTEXT_MINOR_VERSION = 18
SDL_GL_CONTEXT_PROFILE_MASK = 21
SDL_GL_CONTEXT_PROFILE_ES = 0x0004

# EGL Constants
EGL_OPENGL_ES_API = 0x30A0
EGL_OPENGL_API = 0x30A2

# Single SDL_Init for ALL tests
ret = sdl.SDL_Init(SDL_INIT_VIDEO)
if ret != 0:
    print(f"FATAL: SDL_Init failed: {sdl.SDL_GetError()}")
    sys.exit(1)
print("SDL_Init OK")

# ---- TEST 1: SDL_CreateRenderer (known working) ----
print("\n--- TEST 1: SDL_CreateRenderer (indirect GL) ---")

win1 = sdl.SDL_CreateWindow(
    b"Test1-Renderer",
    0x1FFF0000, 0x1FFF0000,
    640, 480,
    SDL_WINDOW_FULLSCREEN | SDL_WINDOW_OPENGL | SDL_WINDOW_SHOWN
)
if not win1:
    print(f"FATAL: CreateWindow failed: {sdl.SDL_GetError()}")
    sdl.SDL_Quit()
    sys.exit(1)
print(f"  Window: {win1:#x}")

renderer = sdl.SDL_CreateRenderer(ctypes.c_void_p(win1), -1, 0)
if not renderer:
    print(f"FATAL: CreateRenderer failed: {sdl.SDL_GetError()}")
else:
    print(f"  Renderer: {renderer:#x}")

    # Query renderer info
    class SDL_RendererInfo(ctypes.Structure):
        _fields_ = [
            ("name", ctypes.c_char_p),
            ("flags", ctypes.c_uint32),
            ("num_texture_formats", ctypes.c_uint32),
            ("texture_formats", ctypes.c_uint32 * 16),
            ("max_texture_width", ctypes.c_int),
            ("max_texture_height", ctypes.c_int),
        ]

    info = SDL_RendererInfo()
    sdl.SDL_GetRendererInfo.argtypes = [ctypes.c_void_p, ctypes.POINTER(SDL_RendererInfo)]
    ret = sdl.SDL_GetRendererInfo(ctypes.c_void_p(renderer), ctypes.byref(info))
    if ret == 0:
        print(f"  Renderer name: {info.name}")

    sdl.SDL_SetRenderDrawColor(ctypes.c_void_p(renderer), 0, 64, 200, 255)
    sdl.SDL_RenderClear(ctypes.c_void_p(renderer))
    sdl.SDL_RenderPresent(ctypes.c_void_p(renderer))
    print("  Blue screen — TEST 1 PASSED")
    time.sleep(1)
    sdl.SDL_DestroyRenderer(ctypes.c_void_p(renderer))

sdl.SDL_DestroyWindow(ctypes.c_void_p(win1))


def query_gl_info(label):
    """Query and print GL context info using libGLESv1_CM"""
    try:
        gles = ctypes.CDLL('libGLESv1_CM.so')
        gles.glGetString.restype = ctypes.c_char_p
        vendor = gles.glGetString(0x1F00)
        renderer_str = gles.glGetString(0x1F01)
        version = gles.glGetString(0x1F02)
        exts = gles.glGetString(0x1F03)
        print(f"    GL_VENDOR: {vendor}")
        print(f"    GL_RENDERER: {renderer_str}")
        print(f"    GL_VERSION: {version}")
        if exts:
            print(f"    GL_EXTENSIONS: {len(exts)} bytes")
        else:
            print(f"    GL_EXTENSIONS: NULL!")

        # Check if it's Panfrost (hardware) or llvmpipe (software)
        if renderer_str and b'panfrost' in renderer_str.lower():
            print(f"    >>> PANFROST HARDWARE GPU — {label} WORKS!")
            return True
        elif renderer_str and b'llvmpipe' in renderer_str.lower():
            print(f"    >>> LLVMPIPE SOFTWARE — {label} FAILED (wrong API)")
            return False
        elif renderer_str and b'mali' in renderer_str.lower():
            print(f"    >>> MALI GPU — {label} WORKS!")
            return True
        else:
            print(f"    >>> UNKNOWN RENDERER")
            return False
    except Exception as e:
        print(f"    GL query error: {e}")
        return False


def draw_green(sdl_lib, window):
    """Draw a green screen to confirm rendering works"""
    try:
        gles = ctypes.CDLL('libGLESv1_CM.so')
        gles.glClearColor(ctypes.c_float(0.0), ctypes.c_float(0.8), ctypes.c_float(0.2), ctypes.c_float(1.0))
        gles.glClear(0x4000)  # GL_COLOR_BUFFER_BIT
        sdl_lib.SDL_GL_SwapWindow(ctypes.c_void_p(window))
        print(f"    Green screen drawn!")
        time.sleep(2)
    except Exception as e:
        print(f"    Draw error: {e}")


# ---- TEST 2: SDL_GL_CreateContext WITHOUT eglBindAPI (baseline — expect llvmpipe) ----
print("\n--- TEST 2: SDL_GL_CreateContext (SDL2 attrs only — NO eglBindAPI) ---")

sdl.SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8)
sdl.SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8)
sdl.SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8)
sdl.SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24)
sdl.SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES)
sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 1)
sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0)

win2 = sdl.SDL_CreateWindow(
    b"Test2-NoEglBind",
    0x1FFF0000, 0x1FFF0000,
    640, 480,
    SDL_WINDOW_FULLSCREEN | SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI
)
if not win2:
    print(f"  Window FAILED: {sdl.SDL_GetError()}")
else:
    ctx2 = sdl.SDL_GL_CreateContext(ctypes.c_void_p(win2))
    if not ctx2:
        print(f"  GL Context FAILED: {sdl.SDL_GetError()}")
    else:
        print(f"  GL Context OK: {ctx2:#x}")
        sdl.SDL_GL_MakeCurrent(ctypes.c_void_p(win2), ctypes.c_void_p(ctx2))
        test2_ok = query_gl_info("Test2")
        sdl.SDL_GL_DeleteContext(ctypes.c_void_p(ctx2))
    sdl.SDL_DestroyWindow(ctypes.c_void_p(win2))


# ---- TEST 3: eglBindAPI(EGL_OPENGL_ES_API) BEFORE SDL_GL_CreateContext ----
print("\n--- TEST 3: eglBindAPI(EGL_OPENGL_ES_API) + SDL_GL_CreateContext ---")
print("  This is the proposed fix for EmulationStation!")

if not HAS_EGL:
    print("  SKIPPED — libEGL not available")
else:
    # Force EGL to use OpenGL ES API — this should make SDL3 create a GLES context
    ret = egl.eglBindAPI(EGL_OPENGL_ES_API)
    print(f"  eglBindAPI(EGL_OPENGL_ES_API) = {ret} (1=OK)")

    sdl.SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8)
    sdl.SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8)
    sdl.SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8)
    sdl.SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24)
    sdl.SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
    sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES)
    sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 1)
    sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0)

    win3 = sdl.SDL_CreateWindow(
        b"Test3-EglBind",
        0x1FFF0000, 0x1FFF0000,
        640, 480,
        SDL_WINDOW_FULLSCREEN | SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI
    )
    if not win3:
        print(f"  Window FAILED: {sdl.SDL_GetError()}")
    else:
        ctx3 = sdl.SDL_GL_CreateContext(ctypes.c_void_p(win3))
        if not ctx3:
            print(f"  GL Context FAILED: {sdl.SDL_GetError()}")
        else:
            print(f"  GL Context OK: {ctx3:#x}")
            sdl.SDL_GL_MakeCurrent(ctypes.c_void_p(win3), ctypes.c_void_p(ctx3))
            test3_ok = query_gl_info("Test3")
            if test3_ok:
                draw_green(sdl, win3)
                print("  >>> TEST 3 PASSED — eglBindAPI fix works!")
                print("  >>> This fix should be applied to EmulationStation!")
            sdl.SDL_GL_DeleteContext(ctypes.c_void_p(ctx3))
        sdl.SDL_DestroyWindow(ctypes.c_void_p(win3))


# ---- TEST 4: eglBindAPI + GLES 2.0 (fallback) ----
print("\n--- TEST 4: eglBindAPI + GLES 2.0 (fallback if GLES 1.0 fails) ---")

if not HAS_EGL:
    print("  SKIPPED — libEGL not available")
else:
    ret = egl.eglBindAPI(EGL_OPENGL_ES_API)
    print(f"  eglBindAPI(EGL_OPENGL_ES_API) = {ret} (1=OK)")

    sdl.SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8)
    sdl.SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8)
    sdl.SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8)
    sdl.SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 0)
    sdl.SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1)
    sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES)
    sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2)
    sdl.SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0)

    win4 = sdl.SDL_CreateWindow(
        b"Test4-GLES20",
        0x1FFF0000, 0x1FFF0000,
        640, 480,
        SDL_WINDOW_FULLSCREEN | SDL_WINDOW_OPENGL | SDL_WINDOW_ALLOW_HIGHDPI
    )
    if not win4:
        print(f"  Window FAILED: {sdl.SDL_GetError()}")
    else:
        ctx4 = sdl.SDL_GL_CreateContext(ctypes.c_void_p(win4))
        if not ctx4:
            print(f"  GL Context FAILED: {sdl.SDL_GetError()}")
        else:
            print(f"  GL Context OK: {ctx4:#x}")
            sdl.SDL_GL_MakeCurrent(ctypes.c_void_p(win4), ctypes.c_void_p(ctx4))
            test4_ok = query_gl_info("Test4")
            if test4_ok:
                draw_green(sdl, win4)
                print("  >>> TEST 4 PASSED — GLES 2.0 + eglBindAPI works!")
            sdl.SDL_GL_DeleteContext(ctypes.c_void_p(ctx4))
        sdl.SDL_DestroyWindow(ctypes.c_void_p(win4))


sdl.SDL_Quit()
print("\n" + "=" * 60)
print("Diagnostic complete")
print("=" * 60)
print("\nSummary:")
print("  Test 1: SDL_CreateRenderer → should always work")
print("  Test 2: SDL_GL_CreateContext (no eglBindAPI) → expect llvmpipe")
print("  Test 3: eglBindAPI(ES) + SDL_GL_CreateContext GLES1.0 → THE FIX")
print("  Test 4: eglBindAPI(ES) + SDL_GL_CreateContext GLES2.0 → fallback")
print("  If Test 3 or 4 shows Panfrost → apply eglBindAPI patch to ES!")
