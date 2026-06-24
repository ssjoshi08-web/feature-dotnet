namespace UserApi.Models;

/// <summary>
/// Domain entity representing a user.
/// Pure POCO — no framework or infrastructure dependencies.
/// </summary>
public sealed class User
{
    public int Id { get; }
    public string Name { get; }
    public string Email { get; }

    public User(int id, string name, string email)
    {
        if (string.IsNullOrWhiteSpace(name))
        {
            throw new ArgumentException("Name must not be empty.", nameof(name));
        }

        if (string.IsNullOrWhiteSpace(email))
        {
            throw new ArgumentException("Email must not be empty.", nameof(email));
        }

        Id = id;
        Name = name;
        Email = email;
    }
}
