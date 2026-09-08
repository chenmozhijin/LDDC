#!/usr/bin/env python3
"""解析并校验按 profile、平台、场景和框架分层的能力契约。"""

from __future__ import annotations

import argparse
import base64
import copy
import json
from pathlib import Path
from typing import Any


MATRIX_PATH = Path(__file__).with_name("platform_capability_matrix.json")
STATE_KEYS = {"mode", "required", "applicable", "reason"}
GATES = {"required", "observation"}


class CapabilityMatrixError(ValueError):
    """矩阵内容不完整或无法唯一解析时抛出的确定性错误。"""


def load_matrix(path: Path = MATRIX_PATH) -> dict[str, Any]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schemaVersion") != 3:
        raise CapabilityMatrixError("能力矩阵 schemaVersion 必须为 3")
    profiles = payload.get("profiles")
    contracts = payload.get("contracts")
    if not isinstance(profiles, dict) or not profiles:
        raise CapabilityMatrixError("能力矩阵缺少 profiles")
    if not isinstance(contracts, list):
        raise CapabilityMatrixError("能力矩阵 contracts 必须为数组")
    for profile, capabilities in profiles.items():
        if not isinstance(profile, str) or not isinstance(capabilities, dict):
            raise CapabilityMatrixError("profile 名称或能力集合无效")
        _validate_capabilities(capabilities, f"profiles.{profile}")
    for index, contract in enumerate(contracts):
        if not isinstance(contract, dict):
            raise CapabilityMatrixError(f"contracts[{index}] 必须为对象")
        for key in ("profile", "platform", "scenario", "framework"):
            if not isinstance(contract.get(key), str) or not contract[key].strip():
                raise CapabilityMatrixError(f"contracts[{index}].{key} 无效")
        capabilities = contract.get("capabilities")
        if not isinstance(capabilities, dict):
            raise CapabilityMatrixError(f"contracts[{index}].capabilities 无效")
        _validate_capabilities(capabilities, f"contracts[{index}].capabilities")
        gate = contract.get("gate", "required")
        if gate not in GATES:
            raise CapabilityMatrixError(
                f"contracts[{index}].gate 必须为 required 或 observation"
            )
    return payload


def resolve_contract(
    matrix: dict[str, Any],
    *,
    profile: str,
    platform: str,
    scenario: str,
    framework: str,
) -> dict[str, dict[str, Any]]:
    profiles = matrix["profiles"]
    base = profiles.get(profile)
    if not isinstance(base, dict):
        raise CapabilityMatrixError(f"未知 profile={profile}")

    matches: list[tuple[int, dict[str, Any]]] = []
    for contract in matrix["contracts"]:
        if contract["profile"] != profile:
            continue
        selectors = {
            "platform": platform,
            "scenario": scenario,
            "framework": framework,
        }
        if any(contract[key] not in {"*", value} for key, value in selectors.items()):
            continue
        specificity = sum(contract[key] != "*" for key in selectors)
        matches.append((specificity, contract))

    if profile != "offline" and not matches:
        raise CapabilityMatrixError(
            "能力矩阵没有匹配契约："
            f"profile={profile}, platform={platform}, scenario={scenario}, "
            f"framework={framework}"
        )

    resolved: dict[str, dict[str, Any]] = copy.deepcopy(base)
    for _, contract in sorted(matches, key=lambda item: item[0]):
        for name, state in contract["capabilities"].items():
            resolved[name] = copy.deepcopy(state)
    _validate_capabilities(resolved, "resolved")
    return resolved


def resolve_gate(
    matrix: dict[str, Any],
    *,
    profile: str,
    platform: str,
    scenario: str,
    framework: str,
) -> str:
    """按契约特异性解析场景门禁，未声明时保持 required。"""
    matches: list[tuple[int, dict[str, Any]]] = []
    for contract in matrix["contracts"]:
        if contract["profile"] != profile:
            continue
        selectors = {
            "platform": platform,
            "scenario": scenario,
            "framework": framework,
        }
        if any(contract[key] not in {"*", value} for key, value in selectors.items()):
            continue
        specificity = sum(contract[key] != "*" for key in selectors)
        matches.append((specificity, contract))

    if profile != "offline" and not matches:
        raise CapabilityMatrixError(
            "能力矩阵没有匹配 gate 契约："
            f"profile={profile}, platform={platform}, scenario={scenario}, "
            f"framework={framework}"
        )
    gate = "required"
    for _, contract in sorted(matches, key=lambda item: item[0]):
        gate = contract.get("gate", gate)
    if gate not in GATES:
        raise CapabilityMatrixError(f"解析得到无效 gate={gate}")
    return gate


def _validate_capabilities(capabilities: dict[str, Any], location: str) -> None:
    for name, state in capabilities.items():
        if not isinstance(name, str) or not name.strip():
            raise CapabilityMatrixError(f"{location} 包含无效能力名称")
        if not isinstance(state, dict) or set(state) != STATE_KEYS:
            raise CapabilityMatrixError(
                f"{location}.{name} 必须且只能包含 {sorted(STATE_KEYS)}"
            )
        mode = state["mode"]
        required = state["required"]
        applicable = state["applicable"]
        reason = state["reason"]
        if not isinstance(mode, str) or not mode.strip():
            raise CapabilityMatrixError(f"{location}.{name}.mode 无效")
        if not isinstance(required, bool) or not isinstance(applicable, bool):
            raise CapabilityMatrixError(f"{location}.{name} 的布尔字段无效")
        if not isinstance(reason, str) or not reason.strip():
            raise CapabilityMatrixError(f"{location}.{name}.reason 不能为空")
        if required and not applicable:
            raise CapabilityMatrixError(f"{location}.{name} 不适用时不能设为 required")
        if not applicable and mode != "notApplicable":
            raise CapabilityMatrixError(
                f"{location}.{name} 不适用时 mode 必须为 notApplicable"
            )
        if applicable and mode == "notApplicable":
            raise CapabilityMatrixError(
                f"{location}.{name} 适用时不能使用 notApplicable"
            )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix", type=Path, default=MATRIX_PATH)
    parser.add_argument("--profile", required=True)
    parser.add_argument("--platform", required=True)
    parser.add_argument("--scenario", required=True)
    parser.add_argument("--framework", required=True)
    parser.add_argument("--base64", action="store_true")
    parser.add_argument("--gate", action="store_true")
    args = parser.parse_args()

    matrix = load_matrix(args.matrix)
    if args.gate:
        print(
            resolve_gate(
                matrix,
                profile=args.profile,
                platform=args.platform,
                scenario=args.scenario,
                framework=args.framework,
            )
        )
        return 0
    contract = resolve_contract(
        matrix,
        profile=args.profile,
        platform=args.platform,
        scenario=args.scenario,
        framework=args.framework,
    )
    encoded = json.dumps(contract, ensure_ascii=False, separators=(",", ":"))
    if args.base64:
        print(base64.b64encode(encoded.encode("utf-8")).decode("ascii"))
    else:
        print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
