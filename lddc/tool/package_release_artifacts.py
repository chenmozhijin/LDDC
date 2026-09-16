#!/usr/bin/env python3
"""把各平台 Release 构建打包成与 Python 版同类的发行产物。

背景：CI 过去只编译 Release 却不上传任何构建产物，用户无法下载安装；而 Python 版
（同一仓库的 `main` 分支）提供 dmg / deb / 便携 zip / 单文件 zip。本脚本把 Flutter
构建产物打成同等类型，命名也对齐 Python 版：

    LDDC-<V>-<arch>.dmg                 macOS（Python 版为 LDDC-0.9.2-amd64.dmg）
    LDDC-<V>-windows-amd64.zip          Windows 便携目录
    LDDC-<V>-windows-amd64-onefile.zip  Windows 单文件 exe（best-effort）
    LDDC_<V>_<arch>.deb                 Linux

`<V>` 取 `lddc/pubspec.yaml` 的 version 去掉 `+build`（与 `kLddcVersion` 同源，见
`generate_app_metadata.py`），因此发布包名、应用内显示与系统属性始终一致。

脚本只做"打包 + 产物级静态校验"；运行期 smoke（有界启动）留在各平台 workflow 步骤，
因为那需要对应平台的会话环境。
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_app_metadata import _read_pubspec_version, _split_version  # noqa: E402

APP_ROOT = Path(__file__).resolve().parents[1]
METADATA_PATH = APP_ROOT / "tool" / "release_metadata.json"
ICON_DIR = APP_ROOT / "tool" / "resources" / "app_icon"


def app_version() -> str:
    """发布版本标签：保留预发布段、去掉 +build（例：0.10.0-alpha.1）。"""
    base, prerelease, _build = _split_version(_read_pubspec_version())
    return f"{base}-{prerelease}" if prerelease else base


def _metadata() -> dict[str, str]:
    return json.loads(METADATA_PATH.read_text(encoding="utf-8"))


def _run(command: list[str], *, cwd: Path | None = None) -> None:
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit(
            f"命令失败（{result.returncode}）：{' '.join(command)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _require_dir(path: Path, label: str) -> Path:
    if not path.is_dir():
        raise SystemExit(f"{label} 不存在或不是目录：{path}")
    return path


def _require_file(path: Path, label: str) -> Path:
    if not path.is_file():
        raise SystemExit(f"{label} 不存在：{path}")
    return path


def _verify_non_empty(path: Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        raise SystemExit(f"产物为空或不存在：{path}")


def _verify_zip_members(archive: Path, members: tuple[str, ...]) -> None:
    """校验 zip 内必需条目，避免产出"看似成功但其实缺文件"的包。

    条目按"以给定相对路径结尾"匹配：Windows 自带 bsdtar 生成的条目带 `./` 前缀，
    macOS/Linux 的 zip 不带，用后缀匹配可以同时覆盖，不必为平台写两套。
    """
    _verify_non_empty(archive)
    with zipfile.ZipFile(archive) as handle:
        names = [name.replace("\\", "/").lstrip("./") for name in handle.namelist()]
    missing = [member for member in members if not any(n.endswith(member) for n in names)]
    if missing:
        raise SystemExit(f"{archive.name} 缺少必需条目：{', '.join(missing)}")


def write_build_info(out_dir: Path, platform: str) -> Path:
    """写出与产物并排的 BUILD-INFO.txt，便于日后核对来源提交与版本。"""
    metadata = _metadata()
    lines = [
        f"平台: {platform}",
        f"版本: {app_version()}",
        f"应用显示名: {metadata['displayName']}",
        f"包标识: {metadata['appId']}",
    ]
    for name in ("GITHUB_SHA", "GITHUB_REF_NAME", "GITHUB_RUN_ID"):
        value = os.environ.get(name)
        if value:
            lines.append(f"{name}: {value}")
    target = out_dir / "BUILD-INFO.txt"
    target.write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    return target


# --------------------------------------------------------------------------- macOS


def package_macos_dmg(app_path: Path, arch: str, out_dir: Path) -> Path:
    """用系统自带 hdiutil 生成 dmg，保持 Python 版"拖入 Applications"的安装方式。

    不引入 brew 的 create-dmg：安装语义一致，且少一个外部依赖；卷名取发布元数据，
    卷图标由规范 PNG 现场转 icns。
    """
    app = _require_dir(app_path, "macOS 应用")
    executable = app / "Contents" / "MacOS" / "LDDC"
    _require_file(executable, "macOS 应用可执行文件")

    version = app_version()
    dmg_path = out_dir / f"LDDC-{version}-{arch}.dmg"

    with tempfile.TemporaryDirectory() as staging_raw:
        staging = Path(staging_raw)
        # dmg 内必须有 LDDC.app 与指向 /Applications 的链接，保持拖拽安装体验。
        shutil.copytree(app, staging / app.name, symlinks=True)
        (staging / "Applications").symlink_to("/Applications")

        icon_png = _require_file(ICON_DIR / "logo.png", "规范图标源")
        iconset = staging / "volume.iconset"
        iconset.mkdir()
        for size in (16, 32, 64, 128, 256, 512):
            _run(
                [
                    "sips",
                    "-z",
                    str(size),
                    str(size),
                    str(icon_png),
                    "--out",
                    str(iconset / f"icon_{size}x{size}.png"),
                ]
            )
        _run(["iconutil", "-c", "icns", str(iconset), "-o", str(staging / "volume.icns")])
        shutil.rmtree(iconset)

        _run(
            [
                "hdiutil",
                "create",
                "-volname",
                _metadata()["displayName"],
                "-srcfolder",
                str(staging),
                "-ov",
                "-format",
                "UDZO",
                str(dmg_path),
            ]
        )

    _verify_non_empty(dmg_path)
    return dmg_path


# ----------------------------------------------------------------------- Windows


def package_windows_portable(release_dir: Path, out_dir: Path) -> Path:
    """打包 Windows 便携目录：解压后进入 `LDDC/` 双击 lddc.exe（与 Python 版同形）。

    Python 版把 standalone 目录重命名为 `LDDC` 再压缩，因此解压得到一个干净的顶层目录，
    而不是把 DLL 与 data/ 散落到当前目录；这里保持一致。
    """
    release = _require_dir(release_dir, "Windows Release 目录")
    _require_file(release / "lddc.exe", "Windows 可执行文件")
    _require_dir(release / "data" / "flutter_assets", "Windows 引擎资源目录")

    archive = out_dir / f"LDDC-{app_version()}-windows-amd64.zip"
    with tempfile.TemporaryDirectory() as staging_raw:
        staging = Path(staging_raw)
        shutil.copytree(release, staging / "LDDC", symlinks=True)
        # 用 Windows 自带 bsdtar（tar.exe）按扩展名生成 zip：比 Compress-Archive 快得多，
        # 且不会像它那样在大目录上产生额外内存峰值。
        _run(["tar.exe", "-a", "-c", "-f", str(archive), "-C", str(staging), "LDDC"])
    _verify_zip_members(
        archive,
        (
            "LDDC/lddc.exe",
            "LDDC/flutter_windows.dll",
            "LDDC/data/flutter_assets/AssetManifest.bin",
        ),
    )
    return archive


def package_windows_onefile(release_dir: Path, sfx_module: Path, out_dir: Path) -> Path:
    """打包单文件 exe（best-effort）。

    Python 版用 Enigma Virtual Box 生成同类产物，但那条链路依赖没有 tag 的第三方
    action 与联网下载（本仓库 hygiene 门禁只接受 @vN 引用），因此改用 7-Zip 安装器
    SFX：`copy /b 7zSD.sfx + config.txt + app.7z out.exe` 的等价二进制拼接。

    Flutter 产物含多个 DLL 与 data/，解压后能否正确解析 data/ 必须由真实 Windows
    证据判定，因此调用方对这一步使用 continue-on-error，并在失败时记录缺口而不是
    静默删除该类型。
    """
    release = _require_dir(release_dir, "Windows Release 目录")
    sfx = _require_file(sfx_module, "7-Zip 安装器 SFX 模块（7zSD.sfx）")

    archive = out_dir / f"LDDC-{app_version()}-windows-amd64-onefile.zip"

    with tempfile.TemporaryDirectory() as staging_raw:
        staging = Path(staging_raw)
        payload = staging / "payload.7z"
        # cwd=release + "."：保证归档内是 Release 目录自身的相对布局（含 data/ 与 DLL）。
        _run(["7z", "a", "-t7z", "-mx=9", str(payload), "."], cwd=release)

        config = staging / "config.txt"
        config.write_text(
            ";!@Install@!UTF-8!\n"
            f'Title="{_metadata()["displayName"]}"\n'
            'RunProgram="lddc.exe"\n'
            ";!@InstallEnd@!\n",
            encoding="utf-8",
            newline="\n",
        )

        packed = staging / "packed" / "lddc.exe"
        packed.parent.mkdir()
        # 二进制拼接：SFX 模块 + 配置 + 7z 负载。
        with packed.open("wb") as target:
            for part in (sfx, config, payload):
                target.write(part.read_bytes())

        archive_dir = staging / "zip"
        archive_dir.mkdir()
        shutil.copy2(packed, archive_dir / "lddc.exe")
        _run(["tar.exe", "-a", "-c", "-f", str(archive), "-C", str(archive_dir), "lddc.exe"])

    _verify_zip_members(archive, ("lddc.exe",))
    return archive


# ------------------------------------------------------------------------- Linux


def package_linux_deb(bundle_dir: Path, arch: str, out_dir: Path) -> Path:
    """生成 deb：与 Python 版同样的安装语义（/usr/bin/LDDC 命令 + 应用菜单项）。

    Python 版把 standalone 目录装到 /usr/lib/LDDC 并建 /usr/bin/LDDC 符号链接，
    control 与 .desktop 字段保持同形，因此老用户的安装/升级路径不变。
    """
    bundle = _require_dir(bundle_dir, "Linux bundle 目录")
    _require_file(bundle / "lddc", "Linux 可执行文件")

    metadata = _metadata()
    version = app_version()
    deb_path = out_dir / f"LDDC_{version}_{arch}.deb"

    with tempfile.TemporaryDirectory() as staging_raw:
        staging = Path(staging_raw)
        lib_dir = staging / "usr" / "lib" / "LDDC"
        bin_dir = staging / "usr" / "bin"
        app_dir = staging / "usr" / "share" / "applications"
        icon_dir = staging / "usr" / "share" / "icons" / "hicolor" / "512x512" / "apps"
        control_dir = staging / "DEBIAN"
        for directory in (lib_dir, bin_dir, app_dir, icon_dir, control_dir):
            directory.mkdir(parents=True)

        # bundle 的 lib/ 与 data/ 必须与可执行文件保持相对布局。
        for item in bundle.iterdir():
            target = lib_dir / item.name
            if item.is_dir():
                shutil.copytree(item, target, symlinks=True)
            else:
                shutil.copy2(item, target)
        installed_binary = lib_dir / "lddc"
        installed_binary.chmod(installed_binary.stat().st_mode | 0o755)

        (bin_dir / "LDDC").symlink_to("../lib/LDDC/lddc")

        (app_dir / "LDDC.desktop").write_text(
            "[Desktop Entry]\n"
            f"Name={metadata['displayName']}\n"
            "Comment=Lyrics acquisition tool\n"
            "Exec=/usr/bin/LDDC\n"
            "Icon=/usr/share/icons/hicolor/512x512/apps/LDDC.png\n"
            "Terminal=false\n"
            "Type=Application\n"
            "Categories=Application\n",
            encoding="utf-8",
            newline="\n",
        )
        shutil.copy2(_require_file(ICON_DIR / "logo.png", "规范图标源"), icon_dir / "LDDC.png")

        (control_dir / "control").write_text(
            f"Package: LDDC\n"
            f"Version: {version}\n"
            f"Architecture: {arch}\n"
            f"Maintainer: {metadata['publisher']}\n"
            f"Description: {metadata['description']}\n"
            "Homepage: https://github.com/chenmozhijin/LDDC\n",
            encoding="utf-8",
            newline="\n",
        )

        # --root-owner-group：避免 deb 内文件带上构建机的 uid/gid。
        _run(["dpkg-deb", "--build", "--root-owner-group", str(staging), str(deb_path)])

    _verify_deb(deb_path)
    return deb_path


def _verify_deb(deb_path: Path) -> None:
    _verify_non_empty(deb_path)
    listing = subprocess.run(
        ["dpkg-deb", "--contents", str(deb_path)], capture_output=True, text=True
    )
    if listing.returncode != 0:
        raise SystemExit(f"读取 deb 内容失败：{listing.stderr}")
    for required in ("usr/lib/LDDC/lddc", "usr/bin/LDDC", "usr/share/applications/LDDC.desktop"):
        if required not in listing.stdout:
            raise SystemExit(f"{deb_path.name} 缺少必需条目：{required}")


# ------------------------------------------------------- Android / iOS / Web


def package_android(apk: Path, aab: Path, out_dir: Path) -> list[Path]:
    """归档 Android 产物。

    Python 版没有移动端产物，因此这里是 Flutter 侧新增类型；只做归档与静态检查，
    签名有效性（CI 专用签名）由 workflow 的 apksigner/jarsigner 步骤负责，因为那需要
    Android SDK 的工具路径。
    """
    apk_file = _require_file(apk, "Android APK")
    aab_file = _require_file(aab, "Android AAB")
    version = app_version()

    targets = [
        (apk_file, out_dir / f"LDDC-{version}-android.apk"),
        (aab_file, out_dir / f"LDDC-{version}-android.aab"),
    ]
    for source, target in targets:
        shutil.copy2(source, target)
        _verify_non_empty(target)

    # APK 必须是 zip（否则不可能是有效包）；AAB 同样以 zip 承载。
    for _source, target in targets:
        if not zipfile.is_zipfile(target):
            raise SystemExit(f"{target.name} 不是有效的 zip 容器")
    with zipfile.ZipFile(out_dir / f"LDDC-{version}-android.apk") as handle:
        names = handle.namelist()
    if "AndroidManifest.xml" not in names:
        raise SystemExit("APK 缺少 AndroidManifest.xml")
    return [target for _source, target in targets]


def package_ios(app_path: Path, out_dir: Path) -> Path:
    """归档 iOS 产物。

    无证书时只能提供未签名 app：它不能装到真机，因此这里只归档并在安装说明里明确
    标注，不把它伪装成可安装产物。`ditto` 用于保留 bundle 的符号链接与权限。

    可执行文件名不硬编码：工程的 PRODUCT_NAME 是 LDDC，而产物目录是 Runner.app，
    两者不一致，因此以构建后 Info.plist 的 CFBundleExecutable 为准。
    """
    app = _require_dir(app_path, "iOS 应用")
    plist_path = _require_file(app / "Info.plist", "iOS Info.plist")

    plist = plistlib.loads(plist_path.read_bytes())
    executable_name = plist.get("CFBundleExecutable")
    if not executable_name:
        raise SystemExit("iOS Info.plist 缺少 CFBundleExecutable")
    _require_file(app / executable_name, f"iOS 可执行文件 {executable_name}")

    archive = out_dir / f"LDDC-{app_version()}-ios-arm64-unsigned.zip"
    _run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)])
    _verify_non_empty(archive)
    return archive


def package_web(web_dir: Path, out_dir: Path) -> Path:
    """打包 Web 静态产物。"""
    web = _require_dir(web_dir, "Web 构建目录")
    for required in ("index.html", "main.dart.js", "flutter_service_worker.js"):
        _require_file(web / required, f"Web 入口 {required}")

    archive = out_dir / f"LDDC-{app_version()}-web.zip"
    _run(["tar", "-a", "-c", "-f", str(archive), "-C", str(web), "."])
    _verify_zip_members(archive, ("index.html", "main.dart.js", "flutter_service_worker.js"))
    return archive


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    macos = sub.add_parser("macos-dmg", help="生成 macOS dmg")
    macos.add_argument("--app", type=Path, required=True)
    macos.add_argument("--arch", choices=("amd64", "arm64"), required=True)
    macos.add_argument("--out", type=Path, required=True)

    portable = sub.add_parser("windows-portable", help="生成 Windows 便携 zip")
    portable.add_argument("--release-dir", type=Path, required=True)
    portable.add_argument("--out", type=Path, required=True)

    onefile = sub.add_parser("windows-onefile", help="生成 Windows 单文件 exe zip")
    onefile.add_argument("--release-dir", type=Path, required=True)
    onefile.add_argument("--sfx", type=Path, required=True)
    onefile.add_argument("--out", type=Path, required=True)

    deb = sub.add_parser("linux-deb", help="生成 Linux deb")
    deb.add_argument("--bundle-dir", type=Path, required=True)
    deb.add_argument("--arch", choices=("amd64", "arm64"), required=True)
    deb.add_argument("--out", type=Path, required=True)

    android = sub.add_parser("android", help="归档 Android APK/AAB")
    android.add_argument("--apk", type=Path, required=True)
    android.add_argument("--aab", type=Path, required=True)
    android.add_argument("--out", type=Path, required=True)

    ios = sub.add_parser("ios", help="归档未签名 iOS 应用")
    ios.add_argument("--app", type=Path, required=True)
    ios.add_argument("--out", type=Path, required=True)

    web = sub.add_parser("web", help="打包 Web 静态产物")
    web.add_argument("--web-dir", type=Path, required=True)
    web.add_argument("--out", type=Path, required=True)

    info = sub.add_parser("build-info", help="写出 BUILD-INFO.txt")
    info.add_argument("--platform", required=True)
    info.add_argument("--out", type=Path, required=True)

    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    produced: Path | list[Path]
    if args.command == "macos-dmg":
        produced = package_macos_dmg(args.app, args.arch, args.out)
    elif args.command == "windows-portable":
        produced = package_windows_portable(args.release_dir, args.out)
    elif args.command == "windows-onefile":
        produced = package_windows_onefile(args.release_dir, args.sfx, args.out)
    elif args.command == "linux-deb":
        produced = package_linux_deb(args.bundle_dir, args.arch, args.out)
    elif args.command == "android":
        produced = package_android(args.apk, args.aab, args.out)
    elif args.command == "ios":
        produced = package_ios(args.app, args.out)
    elif args.command == "web":
        produced = package_web(args.web_dir, args.out)
    else:
        produced = write_build_info(args.out, args.platform)

    for artifact in produced if isinstance(produced, list) else [produced]:
        print(f"{artifact}  sha256={_sha256(artifact)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
