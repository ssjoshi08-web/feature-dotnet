using System.Diagnostics;
using System.Text.Json;
using Microsoft.AspNetCore.Mvc;

namespace UserApi.Middleware;

/// <summary>
/// Catches every unhandled exception, logs it with full context, and returns
/// a RFC 7807 problem-details response with the activity trace id.
/// </summary>
public sealed class GlobalExceptionMiddleware
{
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    private readonly RequestDelegate _next;
    private readonly ILogger<GlobalExceptionMiddleware> _logger;
    private readonly IHostEnvironment _environment;

    public GlobalExceptionMiddleware(
        RequestDelegate next,
        ILogger<GlobalExceptionMiddleware> logger,
        IHostEnvironment environment)
    {
        _next = next ?? throw new ArgumentNullException(nameof(next));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
        _environment = environment ?? throw new ArgumentNullException(nameof(environment));
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context).ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (context.RequestAborted.IsCancellationRequested)
        {
            // Client disconnected — no need to surface as 500.
            _logger.LogInformation("Request {RequestId} cancelled by client", context.TraceIdentifier);
        }
        catch (Exception ex)
        {
            _logger.LogError(
                ex,
                "Unhandled exception for request {Method} {Path} (traceId={TraceId})",
                context.Request.Method,
                context.Request.Path,
                context.TraceIdentifier);

            await WriteProblemDetailsAsync(context, ex).ConfigureAwait(false);
        }
    }

    private async Task WriteProblemDetailsAsync(HttpContext context, Exception ex)
    {
        if (context.Response.HasStarted)
        {
            return;
        }

        context.Response.Clear();
        context.Response.StatusCode = StatusCodes.Status500InternalServerError;
        context.Response.ContentType = "application/problem+json";

        var problem = new ProblemDetails
        {
            Type = "https://tools.ietf.org/html/rfc7231#section-6.6.1",
            Title = "An unexpected error occurred.",
            Status = StatusCodes.Status500InternalServerError,
            Detail = _environment.IsDevelopment() ? ex.Message : "An internal server error has occurred.",
            Instance = context.Request.Path,
        };

        problem.Extensions["traceId"] = Activity.Current?.Id ?? context.TraceIdentifier;

        await JsonSerializer.SerializeAsync(context.Response.Body, problem, JsonOptions).ConfigureAwait(false);
    }
}
