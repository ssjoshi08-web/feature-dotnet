namespace UserApi.Configuration;

/// <summary>
/// Strongly-typed binding for the "Application" configuration section.
/// </summary>
public sealed class ApplicationOptions
{
    public const string SectionName = "Application";

    public string Name { get; set; } = "UserApi";

    public string Version { get; set; } = "1.0.0";

    public string Environment { get; set; } = "Production";
}
