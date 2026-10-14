using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.RegularExpressions;

namespace CodexExtensionFixer;

public sealed record ManifestTarget(string Id, string Name, string Path);

public sealed record FixerEnvironment(
    string CodexVersion,
    string? ResourcesPath,
    string RuntimeRoot,
    string BackupRoot,
    IReadOnlyList<ManifestTarget> Manifests);

public sealed record ManifestStatus(string Name, int Issues, int Fixable, IReadOnlyList<string> Messages);

public sealed record ScanReport(
    string CodexVersion,
    string RuntimeName,
    int TotalIssues,
    int Fixable,
    IReadOnlyList<ManifestStatus> Manifests,
    IReadOnlyList<string> Warnings);

internal sealed record RuntimeInfo(string Name, string Node, string Repl, string Modules);
internal sealed record ManifestPatch(string Id, string Name, string Path, string BeforeHash,
                                     string Json, int Issues, int Fixable, IReadOnlyList<string> Messages);
internal sealed record ScanPlan(ScanReport Summary, IReadOnlyList<ManifestPatch> Patches);
public sealed class BackupInfo
{
    public string Tool { get; set; } = "Codex Extension Fixer";
    public int Schema { get; set; } = 1;
    public string CreatedAt { get; set; } = DateTimeOffset.Now.ToString("O");
    public string Status { get; set; } = "Pending";
    public List<BackupFile> Files { get; set; } = [];
}
public sealed class BackupFile
{
    public string FileId { get; set; } = "";
    public string SourcePath { get; set; } = "";
    public string BackupFile { get; set; } = "";
    public string BeforeHash { get; set; } = "";
    public string? AfterHash { get; set; }
    public bool Modified { get; set; }
}

public sealed class FixerService
{
    private const string ToolId = "Codex Extension Fixer";
    private static readonly JsonSerializerOptions PrettyJson = new() { WriteIndented = true };
    private static readonly UTF8Encoding Utf8NoBom = new(false);
    private readonly FixerEnvironment environment;

    public string BackupRoot => environment.BackupRoot;
    public FixerService(FixerEnvironment environment) => this.environment = environment;

    public static FixerService ForCurrentUser()
    {
        string local = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
        string home = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        var (version, install) = DetectCodexPackage();
        string? resourcePath = install is null ? null : Path.Combine(install, "app", "resources");
        if (resourcePath is not null && !Directory.Exists(resourcePath)) resourcePath = null;
        return new FixerService(new FixerEnvironment(
            version, resourcePath,
            Path.Combine(local, "OpenAI", "Codex", "runtimes", "cua_node"),
            Path.Combine(local, "Codex-Extension-Fixer", "Backups"),
            [
                new("appdata", "AppData 清单",
                    Path.Combine(local, "OpenAI", "Codex", "chrome-native-hosts-v2.json")),
                new("profile", ".codex 清单",
                    Path.Combine(home, ".codex", "chrome-native-hosts-v2.json"))
            ]));
    }

    private static (string version, string? installLocation) DetectCodexPackage()
    {
        try
        {
            using var p = new Process();
            p.StartInfo = new ProcessStartInfo("powershell.exe")
            {
                UseShellExecute = false,
                RedirectStandardOutput = true,
                RedirectStandardError = false,
                CreateNoWindow = true
            };
            p.StartInfo.ArgumentList.Add("-NoProfile");
            p.StartInfo.ArgumentList.Add("-NonInteractive");
            p.StartInfo.ArgumentList.Add("-Command");
            p.StartInfo.ArgumentList.Add(
                "$p=Get-AppxPackage -Name OpenAI.Codex | Sort-Object Version -Descending | Select-Object -First 1; " +
                "if ($p) { Write-Output $p.Version.ToString(); Write-Output $p.InstallLocation }");
            p.Start();
            if (!p.WaitForExit(10000))
            {
                p.Kill(entireProcessTree: true);
                return ("未检测到", null);
            }
            var lines = p.StandardOutput.ReadToEnd()
                .Split(['\r','\n'], StringSplitOptions.RemoveEmptyEntries);
            return lines.Length >= 2 ? (lines[0].Trim(), lines[1].Trim()) : ("未检测到", null);
        }
        catch
        {
            return ("未检测到", null);
        }
    }

    private RuntimeInfo? FindRuntime()
    {
        if (!Directory.Exists(environment.RuntimeRoot)) return null;
        return new DirectoryInfo(environment.RuntimeRoot)
            .EnumerateDirectories()
            .Where(d => Regex.IsMatch(d.Name, "^[0-9a-f]{16}$", RegexOptions.CultureInvariant))
            .OrderByDescending(d => d.LastWriteTimeUtc)
            .Select(d =>
            {
                string bin = Path.Combine(d.FullName, "bin");
                return new RuntimeInfo(
                    d.Name,
                    Path.Combine(bin, "node.exe"),
                    Path.Combine(bin, "node_repl.exe"),
                    Path.Combine(bin, "node_modules"));
            })
            .FirstOrDefault(r => File.Exists(r.Node) && File.Exists(r.Repl) && Directory.Exists(r.Modules));
    }

    public ScanReport Scan() => GetPlan().Summary;

    private ScanPlan GetPlan()
    {
        var runtime = FindRuntime();
        var patches = new List<ManifestPatch>();
        var statuses = new List<ManifestStatus>();
        var warnings = new List<string>();
        if (runtime is null) warnings.Add("未找到完整正式 Node 运行时。不会使用 staging 临时目录。");
        if (environment.ResourcesPath is null) warnings.Add("没有找到 Codex 安装资源目录。此时不会修改资源路径。");

        foreach (var target in environment.Manifests)
        {
            var messages = new List<string>();
            int issues = 0, fixable = 0;
            if (!File.Exists(target.Path))
            {
                statuses.Add(new(target.Name, 1, 0, ["未找到配置清单，已安全跳过"]));
                continue;
            }
            try
            {
                var parsed = JsonNode.Parse(File.ReadAllText(target.Path, Encoding.UTF8)) as JsonObject;
                if (parsed?["entries"] is not JsonArray entries)
                {
                    statuses.Add(new(target.Name, 1, 0, ["配置结构未知：未检测到 entries，拒绝修改"]));
                    continue;
                }
                int browsers = 0;
                foreach (var entry in entries.OfType<JsonObject>())
                {
                    JsonObject? paths = entry["paths"] as JsonObject ?? entry;
                    bool browser = paths.ContainsKey("extensionHostPath")
                                || paths.ContainsKey("browserClientPath")
                                || paths.ContainsKey("browserServicePath");
                    if (!browser) continue;
                    browsers++;
                    CheckField(paths, "nodePath", runtime?.Node, false, false, messages, ref issues, ref fixable);
                    CheckField(paths, "nodeReplPath", runtime?.Repl, false, false, messages, ref issues, ref fixable);
                    CheckModules(paths, runtime?.Modules, messages, ref issues, ref fixable);
                    CheckField(paths, "resourcesPath", environment.ResourcesPath, true, true, messages, ref issues, ref fixable);
                }
                if (browsers == 0) messages.Add("未找到可识别的 Chrome 扩展条目，没有修改配置");
                if (issues == 0 && browsers > 0) messages.Add("所有运行时路径均正常 ✓");
                statuses.Add(new(target.Name, issues, fixable, messages));
                patches.Add(new(target.Id, target.Name, target.Path, HashFile(target.Path),
                    parsed.ToJsonString(PrettyJson), issues, fixable, messages.ToArray()));
            }
            catch (Exception ex)
            {
                statuses.Add(new(target.Name, 1, 0, ["无法安全解析清单：" + ex.Message]));
            }
        }
        var report = new ScanReport(environment.CodexVersion, runtime?.Name ?? "未找到",
            statuses.Sum(x => x.Issues),
            statuses.Sum(x => x.Fixable), statuses, warnings);
        return new ScanPlan(report, patches);
    }

    private static string? StringOf(JsonNode? item)
    {
        try { return item?.GetValue<string>(); }
        catch (InvalidOperationException) { return null; }
    }

    private static bool IsCodexRuntime(string old) =>
        old.Replace('/', '\\').Contains("\\runtimes\\cua_node\\", StringComparison.OrdinalIgnoreCase);

    private static void CheckField(JsonObject obj, string key, string? expected,
        bool directory, bool allowOther, List<string> messages, ref int issues, ref int fixable)
    {
        bool exists = obj.ContainsKey(key);
        string? old = StringOf(obj[key]);
        bool actualExists = old is not null && (directory ? Directory.Exists(old) : File.Exists(old));
        bool stale = key == "resourcesPath"
            ? (expected is not null && !string.Equals(old, expected, StringComparison.OrdinalIgnoreCase))
            : !actualExists || (old is not null && old.Contains(".staging-", StringComparison.OrdinalIgnoreCase));
        if (!stale && exists) return;
        issues++;
        bool canUpdate = expected is not null
            && (directory ? Directory.Exists(expected) : File.Exists(expected))
            && (!exists || string.IsNullOrWhiteSpace(old) || allowOther || IsCodexRuntime(old));
        messages.Add((canUpdate ? "可修复 · " : "需人工处理 · ") + key +
                     (canUpdate ? " 引用了旧版或失效路径" : " 不存在或无法安全识别"));
        if (canUpdate)
        {
            obj[key] = expected;
            fixable++;
        }
    }

    private static void CheckModules(JsonObject obj, string? expected,
        List<string> messages, ref int issues, ref int fixable)
    {
        const string key = "nodeModuleDirs";
        if (obj[key] is JsonArray arr)
        {
            bool anyBroken = false, anyFixed = false;
            for (int i = 0; i < arr.Count; i++)
            {
                string? old = StringOf(arr[i]);
                if (old is not null && Directory.Exists(old) && !old.Contains(".staging-", StringComparison.OrdinalIgnoreCase))
                    continue;
                anyBroken = true;
                if (expected is not null && Directory.Exists(expected)
                    && (string.IsNullOrWhiteSpace(old) || IsCodexRuntime(old)))
                {
                    arr[i] = expected;
                    anyFixed = true;
                }
            }
            if (arr.Count == 0)
            {
                anyBroken = true;
                if (expected is not null && Directory.Exists(expected))
                {
                    arr.Add(expected);
                    anyFixed = true;
                }
            }
            if (anyBroken)
            {
                issues++;
                if (anyFixed) fixable++;
                messages.Add((anyFixed ? "可修复 · " : "需人工处理 · ") + key + " 包含失效目录");
            }
            return;
        }
        CheckField(obj, key, expected, true, false, messages, ref issues, ref fixable);
    }

    private static string HashFile(string path) =>
        Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)));

    private static void WriteMetadata(string folder, BackupInfo info) =>
        File.WriteAllText(Path.Combine(folder, "backup-info.json"),
            JsonSerializer.Serialize(info, PrettyJson), Utf8NoBom);

    private static void ReplaceFromFile(string source, string target)
    {
        string temp = target + ".tmp-" + Guid.NewGuid().ToString("N");
        try
        {
            File.Copy(source, temp, true);
            File.Replace(temp, target, null);
        }
        finally { if (File.Exists(temp)) File.Delete(temp); }
    }

    public string Repair()
    {
        var plan = GetPlan();
        var changed = plan.Patches.Where(p => p.Fixable > 0).ToArray();
        if (changed.Length == 0) return "当前没有可自动修复的路径。";
        foreach (var part in changed)
            if (HashFile(part.Path) != part.BeforeHash)
                throw new IOException("配置已被其他程序更改，请重新检测后再试。");

        var id = DateTime.Now.ToString("yyyyMMdd-HHmmss") + "-" + Guid.NewGuid().ToString("N")[..8];
        string folder = Path.Combine(BackupRoot, id);
        Directory.CreateDirectory(folder);
        var info = new BackupInfo();
        foreach (var part in changed)
        {
            string file = part.Id + ".json";
            File.Copy(part.Path, Path.Combine(folder, file));
            info.Files.Add(new BackupFile { FileId = part.Id, SourcePath = part.Path,
                BackupFile = file, BeforeHash = part.BeforeHash });
        }
        WriteMetadata(folder, info);

        try
        {
            foreach (var part in changed)
            {
                if (HashFile(part.Path) != part.BeforeHash)
                    throw new IOException("Codex 更新程序同时更改了配置，操作已中止。");
                string temp = part.Path + ".tmp-" + Guid.NewGuid().ToString("N");
                try
                {
                    File.WriteAllText(temp, part.Json, Utf8NoBom);
                    JsonNode.Parse(File.ReadAllText(temp, Encoding.UTF8));
                    File.Replace(temp, part.Path, null);
                }
                finally { if (File.Exists(temp)) File.Delete(temp); }
                var record = info.Files.Single(f => f.FileId == part.Id);
                record.AfterHash = HashFile(part.Path);
                record.Modified = true;
                WriteMetadata(folder, info);
            }
            info.Status = "Complete";
            WriteMetadata(folder, info);
            return "修复完成：" + changed.Sum(p => p.Fixable) + " 处字段。备份位于：" + folder;
        }
        catch
        {
            foreach (var file in info.Files.Where(f => f.Modified && f.AfterHash is not null).Reverse())
                try
                {
                    if (HashFile(file.SourcePath) == file.AfterHash)
                        ReplaceFromFile(Path.Combine(folder, file.BackupFile), file.SourcePath);
                }
                catch { /* Keep backup on disk for manual recovery. */ }
            info.Status = "Failed";
            WriteMetadata(folder, info);
            throw;
        }
    }

    public bool HasBackup => FindLatestBackup() is not null;

    private (string folder, BackupInfo info)? FindLatestBackup()
    {
        if (!Directory.Exists(BackupRoot)) return null;
        foreach (var folder in Directory.EnumerateDirectories(BackupRoot).OrderByDescending(s => s))
        {
            try
            {
                string path = Path.Combine(folder, "backup-info.json");
                var meta = JsonSerializer.Deserialize<BackupInfo>(File.ReadAllText(path, Encoding.UTF8));
                if (meta?.Tool == ToolId && meta.Schema == 1 && meta.Status == "Complete")
                    return (folder, meta);
            }
            catch { /* Invalid, partial or unrelated backup. */ }
        }
        return null;
    }

    public string Restore()
    {
        var latest = FindLatestBackup() ?? throw new IOException("没有找到可用的完整备份。");
        var allowed = environment.Manifests.Select(x => Path.GetFullPath(x.Path)).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var rec in latest.info.Files)
        {
            if (!allowed.Contains(Path.GetFullPath(rec.SourcePath))) throw new IOException("备份中的目标路径不受信任。");
            string original = Path.Combine(latest.folder, rec.BackupFile);
            if (!File.Exists(original) || HashFile(original) != rec.BeforeHash)
                throw new IOException("备份文件不完整或校验失败。");
            if (!File.Exists(rec.SourcePath) || rec.AfterHash is null || HashFile(rec.SourcePath) != rec.AfterHash)
                throw new IOException("官方更新已修改配置，为避免覆盖新版设置而拒绝恢复。");
        }
        foreach (var rec in latest.info.Files)
            File.Copy(rec.SourcePath, Path.Combine(latest.folder, "pre-restore-" + rec.FileId + ".json"), true);
        try
        {
            foreach (var rec in latest.info.Files)
                ReplaceFromFile(Path.Combine(latest.folder, rec.BackupFile), rec.SourcePath);
            latest.info.Status = "Restored";
            WriteMetadata(latest.folder, latest.info);
        }
        catch
        {
            foreach (var rec in latest.info.Files)
            {
                string safety = Path.Combine(latest.folder, "pre-restore-" + rec.FileId + ".json");
                try { if (File.Exists(safety)) ReplaceFromFile(safety, rec.SourcePath); }
                catch { /* The safety files stay available. */ }
            }
            throw;
        }
        return "已恢复 " + latest.info.Files.Count + " 份清单。请重新打开 Codex 和 Chrome。";
    }
}
