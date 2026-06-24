using UserApi.Models;

namespace UserApi.Interfaces;

/// <summary>
/// Infrastructure-layer contract for user persistence.
/// Application layer depends on this abstraction only.
/// </summary>
public interface IUserRepository
{
    /// <summary>
    /// Returns every persisted user.
    /// </summary>
    /// <param name="cancellationToken">Cancellation token from the caller.</param>
    Task<IReadOnlyList<User>> GetAllAsync(CancellationToken cancellationToken);
}
