using Microsoft.Extensions.Logging;
using UserApi.DTOs;
using UserApi.Interfaces;

namespace UserApi.Services;

/// <summary>
/// Application service that orchestrates user use cases.
/// </summary>
public sealed class UserService : IUserService
{
    private readonly IUserRepository _userRepository;
    private readonly ILogger<UserService> _logger;

    public UserService(IUserRepository userRepository, ILogger<UserService> logger)
    {
        _userRepository = userRepository ?? throw new ArgumentNullException(nameof(userRepository));
        _logger = logger ?? throw new ArgumentNullException(nameof(logger));
    }

    public async Task<IReadOnlyList<UserDto>> GetAllAsync(CancellationToken cancellationToken)
    {
        _logger.LogInformation("Loading all users");

        var users = await _userRepository.GetAllAsync(cancellationToken).ConfigureAwait(false);

        _logger.LogInformation("Loaded {UserCount} users", users.Count);

        return users
            .Select(u => new UserDto(u.Id, u.Name, u.Email))
            .ToList();
    }
}
