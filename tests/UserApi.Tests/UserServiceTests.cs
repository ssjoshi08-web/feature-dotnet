using Microsoft.Extensions.Logging.Abstractions;
using Moq;
using UserApi.DTOs;
using UserApi.Interfaces;
using UserApi.Models;
using UserApi.Services;

namespace UserApi.Tests;

public sealed class UserServiceTests
{
    private readonly Mock<IUserRepository> _repositoryMock = new(MockBehavior.Strict);
    private readonly UserService _sut;

    public UserServiceTests()
    {
        _sut = new UserService(_repositoryMock.Object, NullLogger<UserService>.Instance);
    }

    [Fact]
    public async Task GetAllUsers_ReturnsUsers()
    {
        // Arrange
        var seed = new List<User>
        {
            new(id: 1, name: "Sachin", email: "sachin@example.com"),
            new(id: 2, name: "John",   email: "john@example.com"),
        };
        _repositoryMock
            .Setup(r => r.GetAllAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(seed);

        // Act
        var result = await _sut.GetAllAsync(CancellationToken.None);

        // Assert
        result.Should().HaveCount(2);
        result[0].Should().BeEquivalentTo(new UserDto(1, "Sachin", "sachin@example.com"));
        result[1].Should().BeEquivalentTo(new UserDto(2, "John",   "john@example.com"));
        _repositoryMock.Verify(r => r.GetAllAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetAllUsers_ReturnsEmptyList()
    {
        // Arrange
        _repositoryMock
            .Setup(r => r.GetAllAsync(It.IsAny<CancellationToken>()))
            .ReturnsAsync(Array.Empty<User>());

        // Act
        var result = await _sut.GetAllAsync(CancellationToken.None);

        // Assert
        result.Should().NotBeNull().And.BeEmpty();
        _repositoryMock.Verify(r => r.GetAllAsync(It.IsAny<CancellationToken>()), Times.Once);
    }

    [Fact]
    public async Task GetAllUsers_HandlesException()
    {
        // Arrange
        var boom = new InvalidOperationException("repository down");
        _repositoryMock
            .Setup(r => r.GetAllAsync(It.IsAny<CancellationToken>()))
            .ThrowsAsync(boom);

        // Act
        Func<Task> act = async () => await _sut.GetAllAsync(CancellationToken.None);

        // Assert — the service is a thin orchestrator, so it must propagate
        // repository failures to the caller; the global middleware logs them.
        await act.Should().ThrowAsync<InvalidOperationException>().WithMessage("repository down");
        _repositoryMock.Verify(r => r.GetAllAsync(It.IsAny<CancellationToken>()), Times.Once);
    }
}
