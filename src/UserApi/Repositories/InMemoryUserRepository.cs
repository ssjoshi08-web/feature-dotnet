using UserApi.Interfaces;
using UserApi.Models;

namespace UserApi.Repositories;

/// <summary>
/// In-memory implementation of <see cref="IUserRepository"/>.
/// Singleton lifetime — seeded once at startup.
/// Replace with an EF Core / Dapper implementation without touching
/// the application layer.
/// </summary>
public sealed class InMemoryUserRepository : IUserRepository
{
    private readonly IReadOnlyList<User> _users;

    public InMemoryUserRepository()
    {
        _users = new List<User>
        {
            new(id: 1, name: "Sachin", email: "sachin@example.com"),
            new(id: 2, name: "John",   email: "john@example.com"),
        };
    }

    public Task<IReadOnlyList<User>> GetAllAsync(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(_users);
    }
}
