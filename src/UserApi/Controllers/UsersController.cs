using Microsoft.AspNetCore.Mvc;
using UserApi.DTOs;
using UserApi.Interfaces;

namespace UserApi.Controllers;

/// <summary>
/// REST endpoints for the User resource.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public sealed class UsersController : ControllerBase
{
    private readonly IUserService _userService;

    public UsersController(IUserService userService)
    {
        _userService = userService ?? throw new ArgumentNullException(nameof(userService));
    }

    /// <summary>
    /// Returns every user.
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(IEnumerable<UserDto>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ProblemDetails), StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> GetUsers(CancellationToken cancellationToken)
    {
        var users = await _userService.GetAllAsync(cancellationToken).ConfigureAwait(false);
        return Ok(users);
    }
}
