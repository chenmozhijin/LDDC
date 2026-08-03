from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path, PurePosixPath
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "tool/test_sensitivity_manifest.json"
DEFAULT_OUTPUT = ROOT / "build/test_sensitivity.json"
PACKAGE_DIRECTORY = ROOT / "packages"
COPY_IGNORE = shutil.ignore_patterns(
    ".dart_tool",
    "build",
    "coverage",
    "reports",
    "*.log",
)


@dataclass(frozen=True)
class Mutation:
    id: str
    packages: tuple[str, ...]
    source: str
    search: str
    replacement: str
    test_package: str
    test_target: str
    failure_needle: str


def _safe_relative_path(value: str, *, field: str) -> PurePosixPath:
    path = PurePosixPath(value)
    if path.is_absolute() or ".." in path.parts or not path.parts:
        raise ValueError(f"{field} 必须是仓库内相对路径: {value!r}")
    return path


def load_manifest(path: Path = DEFAULT_MANIFEST) -> list[Mutation]:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schemaVersion") != 1:
        raise ValueError("test sensitivity manifest schemaVersion 必须为 1")
    raw_mutations = data.get("mutations")
    if not isinstance(raw_mutations, list) or not raw_mutations:
        raise ValueError("test sensitivity manifest 至少需要一个 mutation")

    mutations: list[Mutation] = []
    seen_ids: set[str] = set()
    for raw in raw_mutations:
        if not isinstance(raw, dict):
            raise ValueError("mutation 必须是 JSON object")
        mutation = Mutation(
            id=str(raw["id"]),
            packages=tuple(str(value) for value in raw["packages"]),
            source=str(raw["source"]),
            search=str(raw["search"]),
            replacement=str(raw["replacement"]),
            test_package=str(raw["testPackage"]),
            test_target=str(raw["testTarget"]),
            failure_needle=str(raw["failureNeedle"]),
        )
        if mutation.id in seen_ids:
            raise ValueError(f"mutation id 重复: {mutation.id}")
        seen_ids.add(mutation.id)
        validate_mutation(mutation)
        mutations.append(mutation)
    return mutations


def validate_mutation(mutation: Mutation) -> None:
    if not mutation.id or not mutation.failure_needle:
        raise ValueError("mutation id 和 failureNeedle 不能为空")
    if not mutation.packages or mutation.test_package not in mutation.packages:
        raise ValueError(f"{mutation.id}: testPackage 必须包含在 packages 中")
    if not mutation.search or mutation.search == mutation.replacement:
        raise ValueError(f"{mutation.id}: mutation 必须实际改变源码")

    source_relative = _safe_relative_path(mutation.source, field="source")
    test_relative = _safe_relative_path(mutation.test_target, field="testTarget")
    expected_prefix = PurePosixPath("packages") / mutation.test_package
    if len(source_relative.parts) < 4 or source_relative.parts[0] != "packages":
        raise ValueError(f"{mutation.id}: source 必须位于 packages 目录")
    if source_relative.parts[1] not in mutation.packages:
        raise ValueError(f"{mutation.id}: source package 未包含在 packages 中")
    if test_relative.parts[0] != "test":
        raise ValueError(f"{mutation.id}: testTarget 必须位于 test 目录")

    source_path = ROOT.joinpath(*source_relative.parts)
    test_path = ROOT.joinpath(*expected_prefix.parts, *test_relative.parts)
    if not source_path.is_file() or not test_path.is_file():
        raise ValueError(f"{mutation.id}: source 或 testTarget 不存在")
    source_text = source_path.read_text(encoding="utf-8")
    if source_text.count(mutation.search) != 1:
        raise ValueError(f"{mutation.id}: search 必须在源码中精确出现一次")
    test_text = test_path.read_text(encoding="utf-8")
    if test_text.count(mutation.failure_needle) != 1:
        raise ValueError(f"{mutation.id}: failureNeedle 必须在测试中精确出现一次")


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _prepare_workspace(temp_root: Path, mutation: Mutation) -> None:
    copied_packages: list[str] = []
    for package in mutation.packages:
        source = PACKAGE_DIRECTORY / package
        destination = temp_root / "packages" / package
        if not source.is_dir():
            raise ValueError(f"package 不存在: {package}")
        shutil.copytree(source, destination, ignore=COPY_IGNORE)
        copied_packages.append(package)

    # 临时 workspace 只声明本次测试需要的 package，避免复制应用和其他 Flutter
    # package。依赖解析继续复用当前工作区已经生成的 package_config，因此不会在
    # 本地或 CI 中重新下载依赖。
    workspace_lines = [
        "name: lddc_test_sensitivity_workspace",
        "publish_to: none",
        "environment:",
        "  sdk: ^3.12.0",
        "workspace:",
        *(f"  - packages/{package}" for package in copied_packages),
        "",
    ]
    (temp_root / "pubspec.yaml").write_text(
        "\n".join(workspace_lines),
        encoding="utf-8",
        newline="\n",
    )

    config_path = ROOT / ".dart_tool/package_config.json"
    if not config_path.is_file():
        raise RuntimeError("缺少 .dart_tool/package_config.json，请先运行 flutter pub get")
    package_config = json.loads(config_path.read_text(encoding="utf-8"))
    copied_names = set(copied_packages)
    for package in package_config["packages"]:
        name = package.get("name")
        if name in copied_names:
            package["rootUri"] = (temp_root / "packages" / name).as_uri() + "/"
        elif name == "lddc_workspace":
            package["rootUri"] = temp_root.as_uri() + "/"
    dart_tool = temp_root / ".dart_tool"
    dart_tool.mkdir()
    (dart_tool / "package_config.json").write_text(
        json.dumps(package_config, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _run_test(
    temp_root: Path,
    mutation: Mutation,
    *,
    dart_executable: str,
) -> subprocess.CompletedProcess[str]:
    package_root = temp_root / "packages" / mutation.test_package
    return subprocess.run(
        [dart_executable, "test", "--reporter=compact", mutation.test_target],
        cwd=package_root,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        timeout=180,
    )


def _output_text(result: subprocess.CompletedProcess[str]) -> str:
    return f"{result.stdout}\n{result.stderr}"


def resolve_dart_executable() -> str:
    command = shutil.which("dart")
    if command is None:
        raise RuntimeError("PATH 中找不到 Dart executable")
    candidate = Path(command)
    if candidate.suffix.lower() in {".bat", ".cmd"}:
        # Windows 的 Flutter SDK 向 PATH 暴露 dart.bat，但 Python 的无 shell
        # 子进程不能稳定执行批处理文件。直接调用包装器指向的 dart.exe 能保留相同
        # SDK，又避免 shell 解析参数带来的歧义。
        executable = candidate.parent / "cache" / "dart-sdk" / "bin" / "dart.exe"
        if not executable.is_file():
            raise RuntimeError("Flutter SDK 的 dart.bat 存在，但找不到对应 dart.exe")
        return str(executable)
    return str(candidate)


def verify_mutation(mutation: Mutation, *, dart_executable: str) -> dict[str, Any]:
    source_path = ROOT.joinpath(*PurePosixPath(mutation.source).parts)
    source_hash_before = _sha256(source_path)
    started = time.monotonic()

    with tempfile.TemporaryDirectory(prefix=f"lddc-sensitivity-{mutation.id}-") as temp:
        temp_root = Path(temp)
        _prepare_workspace(temp_root, mutation)

        baseline = _run_test(temp_root, mutation, dart_executable=dart_executable)
        if baseline.returncode != 0:
            tail = _output_text(baseline)[-4000:]
            raise RuntimeError(f"{mutation.id}: 临时副本基线测试失败\n{tail}")

        copied_source = temp_root.joinpath(*PurePosixPath(mutation.source).parts)
        source_text = copied_source.read_text(encoding="utf-8")
        copied_source.write_text(
            source_text.replace(mutation.search, mutation.replacement),
            encoding="utf-8",
            newline="\n",
        )
        mutant = _run_test(temp_root, mutation, dart_executable=dart_executable)
        mutant_output = _output_text(mutant)
        assertion_observed = (
            mutant.returncode != 0 and mutation.failure_needle in mutant_output
        )
        if not assertion_observed:
            tail = mutant_output[-4000:]
            raise RuntimeError(
                f"{mutation.id}: 受控错误未被指定测试断言捕获\n{tail}"
            )

    source_hash_after = _sha256(source_path)
    if source_hash_after != source_hash_before:
        raise RuntimeError(f"{mutation.id}: 原始源码在验证过程中发生变化")
    return {
        "id": mutation.id,
        "baselineExitCode": baseline.returncode,
        "mutantExitCode": mutant.returncode,
        "assertionFailureObserved": assertion_observed,
        "sourceUntouched": True,
        "durationMs": round((time.monotonic() - started) * 1000),
    }


def _write_report(path: Path, results: list[dict[str, Any]], *, success: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "success": success,
                "mutations": results,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
        newline="\n",
    )


def _console_safe(value: object) -> str:
    encoding = sys.stdout.encoding or "utf-8"
    return str(value).encode(encoding, errors="backslashreplace").decode(encoding)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="在临时 package 副本中注入受控错误，验证关键测试会失败。"
    )
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    results: list[dict[str, Any]] = []
    try:
        mutations = load_manifest(args.manifest)
        dart_executable = resolve_dart_executable()
        for mutation in mutations:
            result = verify_mutation(mutation, dart_executable=dart_executable)
            results.append(result)
            print(
                f"test sensitivity passed: {mutation.id} "
                f"({result['durationMs']} ms)"
            )
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
        _write_report(args.output, results, success=False)
        print(f"test sensitivity failed: {_console_safe(error)}")
        return 1

    _write_report(args.output, results, success=True)
    print(f"test sensitivity passed: {len(results)} mutations")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
