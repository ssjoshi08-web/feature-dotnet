using Microsoft.Extensions.Options;
using Microsoft.OpenApi.Models;
using UserApi.Configuration;
using UserApi.Interfaces;
using UserApi.Middleware;
using UserApi.Repositories;
using UserApi.Services;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// Strongly-typed configuration
// ---------------------------------------------------------------------------
builder.Services
    .Configure<ApplicationOptions>(builder.Configuration.GetSection(ApplicationOptions.SectionName))
    .Configure<SwaggerOptions>(builder.Configuration.GetSection(SwaggerOptions.SectionName));

// ---------------------------------------------------------------------------
// Dependency injection — application & infrastructure layers
// ---------------------------------------------------------------------------
builder.Services.AddSingleton<IUserRepository, InMemoryUserRepository>();
builder.Services.AddScoped<IUserService, UserService>();

// ---------------------------------------------------------------------------
// MVC, Swagger, health checks
// ---------------------------------------------------------------------------
builder.Services
    .AddControllers()
    .ConfigureApiBehaviorOptions(options => options.SuppressModelStateInvalidFilter = false);

builder.Services.AddEndpointsApiExplorer();

builder.Services.AddSwaggerGen(options =>
{
    var swagger = builder.Configuration
        .GetSection(SwaggerOptions.SectionName)
        .Get<SwaggerOptions>() ?? new SwaggerOptions();

    options.SwaggerDoc(swagger.Version, new OpenApiInfo
    {
        Title = swagger.Title,
        Version = swagger.Version,
        Description = swagger.Description,
    });

    options.EnableAnnotations();
});

builder.Services.AddHealthChecks();

var app = builder.Build();

// ---------------------------------------------------------------------------
// Pipeline
// ---------------------------------------------------------------------------
app.UseMiddleware<GlobalExceptionMiddleware>();

var swaggerOptions = app.Services.GetRequiredService<IOptions<SwaggerOptions>>().Value;
if (swaggerOptions.Enabled)
{
    app.UseSwagger(options => options.RouteTemplate = $"{swaggerOptions.RoutePrefix}/{{documentName}}/swagger.json");
    app.UseSwaggerUI(options =>
    {
        options.RoutePrefix = swaggerOptions.RoutePrefix;
        options.SwaggerEndpoint($"/{swaggerOptions.RoutePrefix}/{swaggerOptions.Version}/swagger.json", swaggerOptions.Title);
    });
}

app.MapControllers();
app.MapHealthChecks("/health");

app.Run();

// Exposed for WebApplicationFactory<Program> in the test project.
public partial class Program;
