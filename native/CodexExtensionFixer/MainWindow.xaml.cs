using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;

namespace CodexExtensionFixer;

public partial class MainWindow : Window
{
    private FixerService? fixer;
    private bool busy;

    public MainWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => TryEnableWindowsBackdrop();
        Loaded += async (_, _) => await ScanAsync();
    }

    [DllImport("dwmapi.dll", PreserveSig = true)]
    private static extern int DwmSetWindowAttribute(
        IntPtr hwnd, int attribute, ref int value, int valueSize);

    private void TryEnableWindowsBackdrop()
    {
        if (!OperatingSystem.IsWindowsVersionAtLeast(10)) return;
        try
        {
            var hwnd = new WindowInteropHelper(this).Handle;
            int dark = 1, round = 2, mica = 2;
            _ = DwmSetWindowAttribute(hwnd, 20, ref dark, sizeof(int));
            _ = DwmSetWindowAttribute(hwnd, 33, ref round, sizeof(int));
            if (OperatingSystem.IsWindowsVersionAtLeast(10, 0, 22621))
                _ = DwmSetWindowAttribute(hwnd, 38, ref mica, sizeof(int));
        }
        catch { /* Gradient fallback works on unsupported Windows versions. */ }
    }

    private void Caption_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ChangedButton != MouseButton.Left) return;
        if (e.ClickCount == 2)
            WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
        else
            DragMove();
    }

    private void Minimize_Click(object sender, RoutedEventArgs e) => WindowState = WindowState.Minimized;
    private void Close_Click(object sender, RoutedEventArgs e) => Close();

    private void SetBusy(bool value)
    {
        busy = value;
        ScanButton.IsEnabled = !value;
        RepairButton.IsEnabled = !value && currentReport?.Fixable > 0;
        RestoreButton.IsEnabled = !value && fixer?.HasBackup == true;
        OpenBackupsButton.IsEnabled = !value;
        BusyProgress.Visibility = value ? Visibility.Visible : Visibility.Collapsed;
    }

    private ScanReport? currentReport;

    private void UpdateReport(ScanReport report)
    {
        currentReport = report;
        VersionValue.Text = report.CodexVersion;
        RuntimeValue.Text = report.RuntimeName;
        IssuesValue.Text = report.TotalIssues.ToString();

        if (report.Fixable > 0)
        {
            StatusText.Text = "发现可修复项目";
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(255, 198, 118));
            IssuesValue.Foreground = new SolidColorBrush(Color.FromRgb(255, 198, 118));
        }
        else if (report.TotalIssues > 0 || report.Warnings.Count > 0)
        {
            StatusText.Text = "需要检查";
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(255, 198, 118));
            IssuesValue.Foreground = new SolidColorBrush(Color.FromRgb(255, 198, 118));
        }
        else
        {
            StatusText.Text = "运行状态良好";
            StatusDot.Fill = new SolidColorBrush(Color.FromRgb(119, 243, 199));
            IssuesValue.Foreground = new SolidColorBrush(Color.FromRgb(119, 243, 199));
        }

        var entries = new List<string>();
        foreach (var manifest in report.Manifests)
        {
            string summary = manifest.Fixable > 0
                ? $"✦ {manifest.Name}  ·  可修复 {manifest.Fixable} 处"
                : $"✓ {manifest.Name}  ·  {manifest.Issues} 处待关注";
            entries.Add(summary + Environment.NewLine + string.Join(Environment.NewLine, manifest.Messages));
        }
        entries.AddRange(report.Warnings.Select(w => "⚠ " + w));
        if (entries.Count == 0) entries.Add("没有发现可检测的清单。");
        DiagnosticsList.ItemsSource = entries;
        RepairButton.IsEnabled = !busy && report.Fixable > 0;
        RestoreButton.IsEnabled = !busy && fixer?.HasBackup == true;
    }

    private async Task ScanAsync()
    {
        if (busy) return;
        SetBusy(true);
        StatusText.Text = "正在检查...";
        try
        {
            var result = await Task.Run(() =>
            {
                var service = FixerService.ForCurrentUser();
                return (service, report: service.Scan());
            });
            fixer = result.service;
            UpdateReport(result.report);
        }
        catch (Exception ex)
        {
            StatusText.Text = "检测失败";
            StatusDot.Fill = Brushes.OrangeRed;
            DiagnosticsList.ItemsSource = new[] { "检测过程中发生错误：" + ex.Message };
        }
        finally { SetBusy(false); }
    }

    private async void Scan_Click(object sender, RoutedEventArgs e) => await ScanAsync();

    private async void Repair_Click(object sender, RoutedEventArgs e)
    {
        if (busy || fixer is null || currentReport?.Fixable is not > 0) return;
        var answer = MessageBox.Show(this,
            "将备份原始配置，再修复检测到的失效路径。请先退出 Chrome 和 Codex（包括后台进程），并确保更新程序没有运行。是否继续？",
            "确认安全修复", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (answer != MessageBoxResult.Yes) return;

        SetBusy(true);
        try
        {
            string result = await Task.Run(fixer.Repair);
            MessageBox.Show(this, result, "修复完成", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, "修复失败，原始备份将保留。\n" + ex.Message,
                "修复失败", MessageBoxButton.OK, MessageBoxImage.Error);
        }
        finally
        {
            SetBusy(false);
            await ScanAsync();
        }
    }

    private async void Restore_Click(object sender, RoutedEventArgs e)
    {
        if (busy || fixer is null) return;
        var answer = MessageBox.Show(this,
            "恢复最近一次成功备份的旧配置。若 Codex 已更新清单，将自动拒绝覆盖。请先退出 Chrome 和 Codex。是否继续？",
            "确认恢复", MessageBoxButton.YesNo, MessageBoxImage.Warning);
        if (answer != MessageBoxResult.Yes) return;

        SetBusy(true);
        try
        {
            string result = await Task.Run(fixer.Restore);
            MessageBox.Show(this, result, "恢复完成", MessageBoxButton.OK, MessageBoxImage.Information);
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "安全恢复已停止", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            SetBusy(false);
            await ScanAsync();
        }
    }

    private void OpenBackups_Click(object sender, RoutedEventArgs e)
    {
        if (fixer is null) return;
        try
        {
            Directory.CreateDirectory(fixer.BackupRoot);
            Process.Start(new ProcessStartInfo("explorer.exe", fixer.BackupRoot)
            {
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            MessageBox.Show(this, ex.Message, "无法打开目录",
                MessageBoxButton.OK, MessageBoxImage.Warning);
        }
    }
}
