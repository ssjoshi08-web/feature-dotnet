namespace UserApi.Configuration;

/// <summary>
/// Strongly-typed binding for the "Swagger" configuration section.
/// </summary>
public sealed class SwaggerOptions
{
    public const string SectionName = "Swagger";

    public bool Enabled { get; set; } = true;

    public string Title { get; set; } = "UserApi";

    public string Version { get; set; } = "v1";

    public string Description { get; set; } = "REST API for the UserApi service.";

    public string RoutePrefix { get; set; } = "swagger";
}
