namespace UserApi.DTOs;

/// <summary>
/// Data transfer object returned by the Users API.
/// Decoupled from the domain <see cref="Models.User"/> so the wire format
/// can evolve independently of the persistence model.
/// </summary>
public sealed record UserDto(int Id, string Name, string Email);
