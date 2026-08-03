#!/usr/bin/env python3
"""从仓库内的规范图标源生成 Flutter 各平台发布图标。"""

from __future__ import annotations

import json
import shutil
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
# 规范图标必须随 Flutter 仓库保存。旧实现通过相对路径访问外层 Python 仓库，
# 独立检出 Flutter 仓库时会立即失效，也会把维护者的目录布局写入候选文件。
# 将源文件固定在 tool/resources 下不会打入应用 assets，同时仍能完整再生成平台产物。
SOURCE_ICON_DIR = ROOT / "tool" / "resources" / "app_icon"


def _resolve_source_dir() -> Path:
    source_dir = SOURCE_ICON_DIR.resolve()
    if not source_dir.is_relative_to(ROOT.resolve()):
        raise ValueError("规范图标源必须位于 Flutter 仓库内部")
    required = ["logo.png", "logo.ico"]
    missing = [name for name in required if not (source_dir / name).is_file()]
    if missing:
        raise FileNotFoundError(f"缺少规范图标源文件：{', '.join(missing)}")
    return source_dir


def _save_png(source: Image.Image, target: Path, size: int) -> None:
    target.parent.mkdir(parents=True, exist_ok=True)
    # 使用透明背景的高质量缩放，避免平台图标继续沿用 Flutter 模板资源。
    icon = source.resize((size, size), Image.Resampling.LANCZOS)
    icon.save(target, "PNG")


def _generate_android(source: Image.Image) -> None:
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for folder, size in sizes.items():
        _save_png(
            source,
            ROOT / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png",
            size,
        )


def _generate_ios(source: Image.Image) -> None:
    app_icon_dir = ROOT / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((app_icon_dir / "Contents.json").read_text(encoding="utf-8"))
    for image in contents["images"]:
        filename = image.get("filename")
        if not filename:
            continue
        logical_size = float(str(image["size"]).split("x", maxsplit=1)[0])
        scale = int(str(image["scale"]).removesuffix("x"))
        _save_png(source, app_icon_dir / filename, int(logical_size * scale))


def _generate_macos(source: Image.Image) -> None:
    app_icon_dir = ROOT / "macos" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    contents = json.loads((app_icon_dir / "Contents.json").read_text(encoding="utf-8"))
    for image in contents["images"]:
        filename = image.get("filename")
        if not filename:
            continue
        logical_size = float(str(image["size"]).split("x", maxsplit=1)[0])
        scale = int(str(image["scale"]).removesuffix("x"))
        _save_png(source, app_icon_dir / filename, int(logical_size * scale))


def _generate_web(source: Image.Image) -> None:
    web_root = ROOT / "web"
    _save_png(source, web_root / "favicon.png", 32)
    _save_png(source, web_root / "icons" / "Icon-192.png", 192)
    _save_png(source, web_root / "icons" / "Icon-512.png", 512)
    _save_png(source, web_root / "icons" / "Icon-maskable-192.png", 192)
    _save_png(source, web_root / "icons" / "Icon-maskable-512.png", 512)


def _copy_platform_specific_sources(source_dir: Path, source: Image.Image) -> None:
    shutil.copyfile(
        source_dir / "logo.ico",
        ROOT / "windows" / "runner" / "resources" / "app_icon.ico",
    )
    _save_png(source, ROOT / "assets" / "tray_icon.png", 256)


def main() -> None:
    source_dir = _resolve_source_dir()
    with Image.open(source_dir / "logo.png") as image:
        source = image.convert("RGBA")
        _generate_android(source)
        _generate_ios(source)
        _generate_macos(source)
        _generate_web(source)
        _copy_platform_specific_sources(source_dir, source)
    print("平台图标生成完成。")


if __name__ == "__main__":
    main()
