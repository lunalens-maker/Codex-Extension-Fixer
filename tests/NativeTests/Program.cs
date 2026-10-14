using System.Text;
using System.Text.Json;
using CodexExtensionFixer;

static void Check(bool condition, string message)
{
    if (!condition) throw new Exception("FAILED: " + message);
    Console.WriteLine("PASS: " + message);
}
string root = Path.Combine(Path.GetTempPath(), "CodexFixerNativeTest-" + Guid.NewGuid().ToString("N"));
try
{
    string runRoot = Path.Combine(root, "runtimes", "cua_node");
    string goodBin = Path.Combine(runRoot, "a9ba6825a525118c", "bin");
    string stageBin = Path.Combine(runRoot, ".staging-incomplete", "bin");
    string resources = Path.Combine(root, "current", "app", "resources");
    foreach (string dir in new[] { goodBin, stageBin, Path.Combine(goodBin, "node_modules"), Path.Combine(stageBin, "node_modules"), resources })
        Directory.CreateDirectory(dir);
    foreach (string bin in new[] { goodBin, stageBin })
    {
        File.WriteAllText(Path.Combine(bin, "node.exe"), "test");
        File.WriteAllText(Path.Combine(bin, "node_repl.exe"), "test");
    }
    string brokenBin = Path.Combine(runRoot, "deadbeefdeadbeef", "bin");
    string oldResource = Path.Combine(root, "obsolete", "app", "resources");
    string profile = Path.Combine(root, "profile.json");
    string appData = Path.Combine(root, "appdata.json");
    var fixture = new
    {
        entries = new object[]
        {
            new {
                paths = new {
                    nodePath = Path.Combine(brokenBin, "node.exe"),
                    nodeReplPath = Path.Combine(brokenBin, "node_repl.exe"),
                    nodeModuleDirs = new [] { Path.Combine(brokenBin, "node_modules") },
                    resourcesPath = oldResource,
                    extensionHostPath = Path.Combine(root, "plugin", "extension-host.exe"),
                    untouched = "KEEP_ME"
                }
            },
            new { paths = new { nodePath = "DO_NOT_TOUCH" } }
        }
    };
    string original = JsonSerializer.Serialize(fixture);
    File.WriteAllText(profile, original);
    File.WriteAllText(appData, original);
    var environment = new FixerEnvironment(
        "26.1007.9446.0", resources, runRoot, Path.Combine(root, "backups"),
        new [] { new ManifestTarget("profile", "Profile", profile), new ManifestTarget("appdata", "AppData", appData) });
    var svc = new FixerService(environment);

    var scan = svc.Scan();
    Check(scan.RuntimeName == "a9ba6825a525118c", "selects stable runtime instead of staging");
    Check(scan.Fixable == 8, "detects eight broken fields");
    Check(File.ReadAllText(profile) == original, "scan is read-only");

    svc.Repair();
    var fixedJson = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(profile))!;
    var paths = fixedJson["entries"]![0]!["paths"]!;
    Check(paths["nodePath"]!.ToString() == Path.Combine(goodBin,"node.exe"), "repairs nodePath");
    Check(paths["nodeReplPath"]!.ToString() == Path.Combine(goodBin,"node_repl.exe"), "repairs nodeReplPath");
    Check(paths["nodeModuleDirs"]![0]!.ToString() == Path.Combine(goodBin,"node_modules"), "repairs module directory array");
    Check(paths["resourcesPath"]!.ToString() == resources, "repairs resourcesPath");
    Check(paths["untouched"]!.ToString() == "KEEP_ME", "preserves unrecognized keys");
    Check(fixedJson["entries"]![1]!["paths"]!["nodePath"]!.ToString() == "DO_NOT_TOUCH", "does not touch unrelated entries");

    Check(svc.HasBackup, "writes a complete backup");
    Check(svc.Scan().Fixable == 0, "repair is idempotent");
    svc.Restore();
    Check(File.ReadAllText(profile) == original && File.ReadAllText(appData) == original, "restore produces exact original bytes");

    svc.Repair();
    File.AppendAllText(profile, " ");
    bool blocked = false;
    try { svc.Restore(); } catch (IOException) { blocked = true; }
    Check(blocked, "restore refuses to overwrite externally changed manifests");

    Console.WriteLine("All native C# tests passed.");
}
finally
{
    if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
}