using Jellyfin.Plugin.CleanStream.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.CleanStream;

/// <summary>
/// CleanStream: picks the right version and bitrate for each viewer and keeps playback smooth.
/// </summary>
public class Plugin : BasePlugin<PluginConfiguration>, IHasWebPages
{
    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        // Outside the versioned install folder, so logs survive updates.
        DataFolder = Path.Combine(applicationPaths.PluginConfigurationsPath, "CleanStream");
        MigrateFromBetterPlay(applicationPaths);
        Instance = this;
    }

    public static Plugin? Instance { get; private set; }

    /// <summary>CleanStream's own files (probe logs), kept across updates.</summary>
    public string DataFolder { get; }

    public override string Name => "CleanStream";

    public override Guid Id => Guid.Parse("575fdaea-52dd-4363-a84b-69c5c52daded");

    public override string Description => "Picks the best version and bitrate for each viewer's connection and keeps playback from freezing.";

    public IEnumerable<PluginPageInfo> GetPages()
    {
        yield return new PluginPageInfo
        {
            Name = Name,
            DisplayName = "CleanStream",
            EmbeddedResourcePath = $"{GetType().Namespace}.Configuration.configPage.html",
            EnableInMainMenu = true,
            MenuSection = "server",
            MenuIcon = "smart_display"
        };
    }

    // The probe releases (0.1–0.2) were called BetterPlay: same plugin id, but the settings file is named after the
    // DLL and the logs sat in the install folder. Carry both over once; never fail startup over it.
    private void MigrateFromBetterPlay(IApplicationPaths paths)
    {
        try
        {
            var oldConfig = Path.Combine(paths.PluginConfigurationsPath, "Jellyfin.Plugin.BetterPlay.xml");
            var newConfig = Path.Combine(paths.PluginConfigurationsPath, "Jellyfin.Plugin.CleanStream.xml");
            if (File.Exists(oldConfig) && !File.Exists(newConfig))
            {
                File.Copy(oldConfig, newConfig);
            }

            var probe = Path.Combine(DataFolder, "probe");
            foreach (var dir in Directory.EnumerateDirectories(paths.PluginsPath, "BetterPlay*"))
            {
                var oldProbe = Path.Combine(dir, "probe");
                if (!Directory.Exists(oldProbe))
                {
                    continue;
                }

                Directory.CreateDirectory(probe);
                foreach (var f in Directory.EnumerateFiles(oldProbe, "*.jsonl"))
                {
                    var target = Path.Combine(probe, Path.GetFileName(f));
                    if (!File.Exists(target))
                    {
                        File.Copy(f, target);
                    }
                }
            }
        }
        catch (Exception)
        {
            // Best effort: a fresh start is fine.
        }
    }
}
