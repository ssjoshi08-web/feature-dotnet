using UserApi.DTOs;

namespace UserApi.Interfaces;

/// <summary>
/// Application-layer contract for user use cases.
/// </summary>
public interface IUserService
{
    /// <summary>
    /// Returns all users, projected to DTOs.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token from the caller.</param>
    Task<IReadOnlyList<UserDto>> GetAllAsync(CancellationToken cancellationToken);
}
