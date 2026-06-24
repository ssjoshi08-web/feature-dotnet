using System.Net;
using System.Net.Http.Json;
using Microsoft.AspNetCore.Mvc.Testing;
using UserApi.DTOs;

namespace UserApi.Tests;

/// <summary>
/// End-to-end controller tests executed through the full ASP.NET Core
/// pipeline (middleware + DI + routing), which is what the 85% coverage
/// requirement is measured against.
/// </summary>
public sealed class UserControllerTests : IClassFixture<WebApplicationFactory<Program>>
{
    private readonly HttpClient _client;

    public UserControllerTests(WebApplicationFactory<Program> factory)
    {
        _client = factory.CreateClient();
    }

    [Fact]
    public async Task GetUsers_ReturnsOk()
    {
        // Act
        var response = await _client.GetAsync("/api/users");

        // Assert
        response.StatusCode.Should().Be(HttpStatusCode.OK);
    }

    [Fact]
    public async Task GetUsers_ReturnsCorrectResponse()
    {
        // Act
        var users = await _client.GetFromJsonAsync<List<UserDto>>("/api/users");

        // Assert
        users.Should().NotBeNull();
        users.Should().HaveCount(2);
        users![0].Should().BeEquivalentTo(new UserDto(1, "Sachin", "sachin@example.com"));
        users[1].Should().BeEquivalentTo(new UserDto(2, "John",   "john@example.com"));
    }

    [Fact]
    public async Task GetUsers_ReturnsStatusCode200()
    {
        // Act
        var response = await _client.GetAsync("/api/users");

        // Assert — explicit numeric assertion
        ((int)response.StatusCode).Should().Be(200);
    }
}
