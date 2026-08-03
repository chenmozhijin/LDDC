using System.Security.Cryptography;
using System.Text.Json;
using FlaUI.Core.AutomationElements;

namespace RunnerPlatformTests;

internal static class WindowsPlatformTestEnvironment
{
    public static string Required(string name)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrWhiteSpace(value)
            ? throw new InvalidOperationException($"缺少环境变量 {name}")
            : value;
    }
}

/// <summary>
/// 将 FlaUI 侧的真实原生动作统一写成可与 Flutter 场景报告合并的 evidence。
/// 这里只保存稳定动作名、摘要和有界 UIA 诊断，不保存本机绝对路径。
/// </summary>
internal sealed class WindowsNativeEvidenceBuilder
{
    private readonly Dictionary<string, List<Dictionary<string, object?>>> _actions = [];
    private readonly List<Dictionary<string, object?>> _artifacts = [];
    private readonly string _framework;
    private readonly string _scenario;
    private readonly string _tracePath;

    public WindowsNativeEvidenceBuilder(string scenario, string framework)
    {
        _scenario = scenario;
        _framework = framework;
        var directory = WindowsPlatformTestEnvironment.Required("LDDC_NATIVE_EVIDENCE_DIR");
        Directory.CreateDirectory(directory);
        _tracePath = Path.Combine(directory, $"{scenario}.progress.log");
        File.WriteAllText(_tracePath, string.Empty);
    }

    public void Trace(string stage)
    {
        File.AppendAllText(
            _tracePath,
            $"{DateTimeOffset.UtcNow:O}\t{stage}{Environment.NewLine}");
    }

    public void WriteAutomationTree(AutomationElement root)
    {
        try
        {
            // 失败诊断仅遍历当前原生窗口的有界子树，避免扫描或记录桌面其他应用。
            var nodes = new List<Dictionary<string, object?>>();
            foreach (var element in new[] { root }.Concat(root.FindAllDescendants()).Take(300))
            {
                nodes.Add(new Dictionary<string, object?>
                {
                    ["automationId"] = element.Properties.AutomationId.ValueOrDefault ?? string.Empty,
                    ["name"] = element.Properties.Name.ValueOrDefault ?? string.Empty,
                    ["controlType"] = element.Properties.ControlType.ValueOrDefault.ToString(),
                    ["supportsInvoke"] = element.Patterns.Invoke.IsSupported,
                });
            }
            File.WriteAllText(
                Path.ChangeExtension(_tracePath, ".uia.json"),
                JsonSerializer.Serialize(nodes, new JsonSerializerOptions { WriteIndented = true }));
            Trace("uia_tree_written");
        }
        catch (Exception error)
        {
            Trace($"uia_tree_failed:{error.GetType().Name}");
        }
    }

    public void Add(string capability, string action)
    {
        if (!_actions.TryGetValue(capability, out var entries))
        {
            entries = [];
            _actions[capability] = entries;
        }
        entries.Add(new Dictionary<string, object?> { ["action"] = action });
    }

    public void AddArtifact(string path)
    {
        var bytes = File.ReadAllBytes(path);
        _artifacts.Add(new Dictionary<string, object?>
        {
            ["name"] = Path.GetFileName(path),
            ["size"] = bytes.Length,
            ["sha256"] = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(),
        });
    }

    public void Write(
        string step,
        Exception? failure,
        int finalNativeWindowCount,
        string nativeBoundary)
    {
        var directory = WindowsPlatformTestEnvironment.Required("LDDC_NATIVE_EVIDENCE_DIR");
        var payload = new Dictionary<string, object?>
        {
            ["runId"] = WindowsPlatformTestEnvironment.Required("LDDC_IT_RUN_ID"),
            ["scenario"] = _scenario,
            ["profile"] = "platform",
            ["platform"] = "windows",
            ["framework"] = _framework,
            ["steps"] = new[]
            {
                new Dictionary<string, object?>
                {
                    ["step"] = step,
                    ["success"] = failure is null,
                    ["error"] = failure?.ToString(),
                },
            },
            ["capabilityEvidence"] = _actions,
            ["resources"] = new Dictionary<string, object?>
            {
                ["baseline"] = new Dictionary<string, object?> { ["nativeWindowCount"] = 0 },
                ["final"] = new Dictionary<string, object?>
                {
                    ["nativeWindowCount"] = finalNativeWindowCount,
                },
                ["thresholds"] = new Dictionary<string, object?> { ["nativeWindowCount"] = 0 },
            },
            ["artifacts"] = _artifacts,
            ["extra"] = new Dictionary<string, object?>
            {
                ["nativeFramework"] = "flaui-uia3",
                ["nativeBoundary"] = nativeBoundary,
            },
        };
        var target = Path.Combine(directory, $"{_scenario}.json");
        var temporary = target + ".tmp";
        File.WriteAllText(
            temporary,
            JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
        File.Move(temporary, target, true);
    }
}
