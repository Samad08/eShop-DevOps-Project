using Microsoft.AspNetCore.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.AspNetCore.Routing;
using Prometheus;

namespace Microsoft.AspNetCore.Hosting;

public static class MonitoringExtensions
{
    /// <summary>
    /// Registers Prometheus metrics collection.
    /// Call this in Program.cs → builder.Services.AddMonitoring()
    /// </summary>
    public static IServiceCollection AddPrometheusMonitoring(this IServiceCollection services)
    {
        // Enables HTTP request duration/count metrics automatically
        services.AddHttpClient(); // ensures HttpClient factory metrics work too
        return services;
    }

    /// <summary>
    /// Maps the /metrics endpoint and enables HTTP middleware instrumentation.
    /// Call this in Program.cs after app.UseRouting()
    /// </summary>
    public static IApplicationBuilder UsePrometheusMonitoring(this IApplicationBuilder app)
    {
        // Instruments every HTTP request automatically
        app.UseHttpMetrics(options =>
        {
            options.AddCustomLabel("service", context =>
                context.Request.Host.Host); // tag metrics per service
        });

        return app;
    }

    /// <summary>
    /// Maps the /metrics scrape endpoint.
    /// Call this in Program.cs after app.MapControllers()
    /// </summary>
    public static IEndpointRouteBuilder MapPrometheusMonitoring(this IEndpointRouteBuilder endpoints)
    {
        endpoints.MapMetrics("/metrics"); // Prometheus scrapes this
        return endpoints;
    }
}