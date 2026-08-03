using System.Diagnostics;
using FlaUI.Core.AutomationElements;
using FlaUI.Core.Definitions;
using FlaUI.Core.Tools;
using FlaUI.UIA3;
using Microsoft.VisualStudio.TestTools.UnitTesting;

namespace RunnerPlatformTests;

[TestClass]
[DoNotParallelize]
public sealed class FileDialogPlatformTests
{
    private const string HybridFramework = "integration_test+flaui-uia3";
    private static readonly TimeSpan DialogTimeout = TimeSpan.FromMinutes(5);
    private static readonly TimeSpan ControlUpdateTimeout = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan DialogCloseTimeout = TimeSpan.FromSeconds(15);

    [TestMethod]
    [Timeout(360_000)]
    public void SelectsFixtureFromDialogOpenedByFlutterIntegrationTest()
    {
        RunReported("windows_file_dialog_select", (session, evidence) =>
        {
            var dialog = session.WaitForNextDialog();
            evidence.Trace("file_dialog_discovered");
            evidence.Add("windowHost", "uia3_lddc_owned_i_file_dialog_discovered");
            evidence.Add("desktopProcess", "lddc_process_observed_from_native_dialog");

            var fileName = RequireFileNameTextBox(dialog);
            fileName.Text = session.FixturePath;
            Assert.IsTrue(
                Retry.WhileFalse(
                    () => fileName.Text == session.FixturePath,
                    ControlUpdateTimeout).Result,
                "IFileDialog 文件名编辑框没有接受完整 fixture 路径");
            evidence.Trace("fixture_path_entered");
            RequireElement(
                dialog,
                "1",
                ControlType.Button,
                "IFileDialog 缺少打开按钮").AsButton().Invoke();
            session.WaitForCurrentDialogClosed();
            evidence.Trace("file_dialog_closed_after_select");
            evidence.Add("filePicker", "i_file_dialog_select_lyrics_fixture");
            evidence.AddArtifact(session.FixturePath);
        });
    }

    [TestMethod]
    [Timeout(360_000)]
    public void CancelsAndReopensDialogOpenedByFlutterIntegrationTest()
    {
        RunReported("windows_file_dialog_cancel", (session, evidence) =>
        {
            for (var attempt = 1; attempt <= 2; attempt += 1)
            {
                var dialog = session.WaitForNextDialog();
                evidence.Trace($"file_dialog_{attempt}_discovered");
                evidence.Add("windowHost", "uia3_lddc_owned_i_file_dialog_discovered");
                evidence.Add("desktopProcess", "lddc_process_observed_from_native_dialog");
                RequireElement(
                    dialog,
                    "2",
                    ControlType.Button,
                    "IFileDialog 缺少取消按钮").AsButton().Invoke();
                evidence.Trace($"file_dialog_{attempt}_cancel_invoked");
                session.WaitForCurrentDialogClosed();
                evidence.Trace($"file_dialog_{attempt}_closed_after_cancel");
                evidence.Add("filePicker", "i_file_dialog_cancel");
                session.SignalDialogClosed(attempt);
            }
        });
    }

    private static TextBox RequireFileNameTextBox(AutomationElement root)
    {
        // AutomationId 1148 同时用于外层 ComboBox 和实际 Edit；只有 Edit 的
        // ValuePattern 会成为最终提交文件名，禁止按本地化名称或元素顺序猜测。
        var result = Retry.WhileNull(
            () => root.FindAllDescendants().FirstOrDefault(element =>
                element.Properties.AutomationId.ValueOrDefault == "1148"
                && element.Properties.ControlType.ValueOrDefault == ControlType.Edit),
            DialogCloseTimeout).Result;
        return result?.AsTextBox()
            ?? throw new AssertFailedException("IFileDialog 缺少原生文件名 Edit 控件");
    }

    private static AutomationElement RequireElement(
        AutomationElement root,
        string automationId,
        ControlType controlType,
        string message)
    {
        return Retry.WhileNull(
            () => root.FindAllDescendants().FirstOrDefault(element =>
                element.Properties.AutomationId.ValueOrDefault == automationId
                && element.Properties.ControlType.ValueOrDefault == controlType),
            DialogCloseTimeout).Result ?? throw new AssertFailedException(message);
    }

    private static void RunReported(
        string scenario,
        Action<NativeDialogSession, WindowsNativeEvidenceBuilder> action)
    {
        var evidence = new WindowsNativeEvidenceBuilder(scenario, HybridFramework);
        NativeDialogSession? session = null;
        Exception? failure = null;
        var dialogsClosed = false;
        try
        {
            evidence.Trace("test_start");
            session = new NativeDialogSession();
            evidence.Trace("uia3_initialized");
            action(session, evidence);
            evidence.Trace("native_action_completed");
        }
        catch (Exception error)
        {
            failure = error;
            if (session?.CurrentDialog is not null)
            {
                evidence.WriteAutomationTree(session.CurrentDialog);
            }
        }
        finally
        {
            if (session is not null)
            {
                dialogsClosed = session.AllObservedDialogsClosed;
                session.Dispose();
            }
        }

        if (!dialogsClosed && failure is null)
        {
            failure = new AssertFailedException("FlaUI 结束时仍有本场景 IFileDialog 未关闭");
        }
        if (dialogsClosed)
        {
            evidence.Add("resourceCleanup", "native_file_dialogs_closed");
        }
        evidence.Write(
            "flaui_native_dialog",
            failure,
            dialogsClosed ? 0 : 1,
            "windows_i_file_dialog");
        if (failure is not null)
        {
            throw failure;
        }
    }

    private sealed class NativeDialogSession : IDisposable
    {
        private readonly UIA3Automation _automation = new();
        private readonly HashSet<IntPtr> _observedWindowHandles = [];
        private IntPtr _currentWindowHandle;

        public string FixturePath { get; } = WindowsPlatformTestEnvironment.Required("LDDC_FIXTURE_PATH");
        public string SyncDirectory { get; } = WindowsPlatformTestEnvironment.Required("LDDC_NATIVE_SYNC_DIR");
        public Window? CurrentDialog { get; private set; }

        public bool AllObservedDialogsClosed => _observedWindowHandles.All(handle =>
            !FindFileDialogCandidates().Any(element =>
                element.Properties.NativeWindowHandle.ValueOrDefault == handle));

        public Window WaitForNextDialog()
        {
            var result = Retry.WhileNull(
                () => FindFileDialogCandidates().FirstOrDefault(element =>
                    !_observedWindowHandles.Contains(
                        element.Properties.NativeWindowHandle.ValueOrDefault)),
                DialogTimeout).Result
                ?? throw new AssertFailedException(
                    "integration_test 未在五分钟内打开属于 LDDC 的真实 IFileDialog");
            _currentWindowHandle = result.Properties.NativeWindowHandle.ValueOrDefault;
            _observedWindowHandles.Add(_currentWindowHandle);
            CurrentDialog = result.AsWindow();
            return CurrentDialog;
        }

        public void WaitForCurrentDialogClosed()
        {
            var handle = _currentWindowHandle;
            Assert.AreNotEqual(IntPtr.Zero, handle, "当前 IFileDialog 没有有效 HWND");
            Assert.IsTrue(
                Retry.WhileFalse(
                    () => !FindFileDialogCandidates().Any(element =>
                        element.Properties.NativeWindowHandle.ValueOrDefault == handle),
                    DialogCloseTimeout).Result,
                "IFileDialog 操作后未在超时内关闭");
            // Windows 可能为下一次文件对话框复用同一个 HWND；只有在已确认当前
            // 对话框消失后才移除句柄，使下一轮能够把复用句柄视为新会话。
            _observedWindowHandles.Remove(handle);
            CurrentDialog = null;
            _currentWindowHandle = IntPtr.Zero;
        }

        public void SignalDialogClosed(int attempt)
        {
            Directory.CreateDirectory(SyncDirectory);
            var target = Path.Combine(SyncDirectory, $"dialog_{attempt}_closed.ready");
            var temporary = target + ".tmp";
            File.WriteAllText(temporary, "ready");
            File.Move(temporary, target, true);
        }

        private AutomationElement[] FindFileDialogCandidates()
        {
            // FlaUI 只扫描原生 Window 节点并校验 IFileDialog 的三个稳定控件 ID；
            // Flutter 控件不参与选择。进程名约束可避免误操作桌面上其他应用的对话框。
            return _automation.GetDesktop()
                .FindAllDescendants(condition => condition.ByControlType(ControlType.Window))
                .Where(IsFileDialogRoot)
                .Where(IsLddcProcess)
                .GroupBy(element => element.Properties.NativeWindowHandle.ValueOrDefault)
                .Select(group => group.First())
                .ToArray();
        }

        private static bool IsFileDialogRoot(AutomationElement element)
        {
            try
            {
                var descendants = element.FindAllDescendants();
                return descendants.Any(candidate =>
                           candidate.Properties.AutomationId.ValueOrDefault == "1148"
                           && candidate.Properties.ControlType.ValueOrDefault == ControlType.Edit)
                    && descendants.Any(candidate =>
                           candidate.Properties.AutomationId.ValueOrDefault == "1"
                           && candidate.Properties.ControlType.ValueOrDefault == ControlType.Button)
                    && descendants.Any(candidate =>
                           candidate.Properties.AutomationId.ValueOrDefault == "2"
                           && candidate.Properties.ControlType.ValueOrDefault == ControlType.Button);
            }
            catch
            {
                return false;
            }
        }

        private static bool IsLddcProcess(AutomationElement element)
        {
            try
            {
                using var process = Process.GetProcessById(
                    element.Properties.ProcessId.ValueOrDefault);
                return process.ProcessName.Equals("lddc", StringComparison.OrdinalIgnoreCase);
            }
            catch
            {
                return false;
            }
        }

        public void Dispose()
        {
            _automation.Dispose();
        }
    }

}
