defmodule Edenflowers.Accounts.EmailChangeTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Accounts
  alias Edenflowers.Accounts.Changes.RequestEmailChange
  alias Edenflowers.Accounts.User
  alias Edenflowers.Accounts.Workers.SendEmailChangeCode

  setup do
    %{user: generate(admin_user(admin: false))}
  end

  defp request!(user, email \\ "new@example.com") do
    user = Accounts.request_email_change!(user, email, actor: user)
    [job] = all_enqueued(worker: SendEmailChangeCode)
    assert job.args["email"] == email
    {user, job.args["code"]}
  end

  defp email_of(user), do: to_string(Ash.get!(User, user.id, authorize?: false).email)

  test "the email changes only once the code sent to the new address is given back", %{user: user} do
    {user, code} = request!(user)
    assert email_of(user) == to_string(user.email)

    assert {:ok, user} = Accounts.confirm_email_change(user, code, actor: user)
    assert to_string(user.email) == "new@example.com"
    assert email_of(user) == "new@example.com"
  end

  test "a confirmed code can't be used again", %{user: user} do
    {user, code} = request!(user)
    user = Accounts.confirm_email_change!(user, code, actor: user)

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :pending_email}]}} =
             Accounts.confirm_email_change(user, code, actor: user)
  end

  test "a new request replaces the address and code of the last one", %{user: user} do
    {_user, first_code} = request!(user, "first@example.com")
    user = Accounts.request_email_change!(user, "second@example.com", actor: user)

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :code}]}} =
             Accounts.confirm_email_change(user, first_code, actor: user)
  end

  test "rejects a wrong code", %{user: user} do
    {user, _code} = request!(user)

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :code}]}} =
             Accounts.confirm_email_change(user, "000000x", actor: user)

    assert email_of(user) == to_string(user.email)
  end

  test "checks the stored pending change, not the one on the record passed in", %{user: user} do
    forged = %{
      user
      | pending_email: "attacker@example.com",
        pending_email_code_hash: RequestEmailChange.hash_code("123456"),
        pending_email_expires_at: DateTime.add(DateTime.utc_now(), 10, :minute)
    }

    assert {:error, %Ash.Error.Invalid{}} = Accounts.confirm_email_change(forged, "123456", actor: user)
    assert email_of(user) == to_string(user.email)
  end

  test "rejects a code without a pending change", %{user: user} do
    assert {:error, %Ash.Error.Invalid{errors: [%{field: :pending_email}]}} =
             Accounts.confirm_email_change(user, "123456", actor: user)
  end

  test "rejects an expired code", %{user: user} do
    {user, code} = request!(user)
    user = Ash.Seed.update!(user, %{pending_email_expires_at: DateTime.add(DateTime.utc_now(), -1, :second)})

    assert {:error, %Ash.Error.Invalid{errors: [%{field: :pending_email}]}} =
             Accounts.confirm_email_change(user, code, actor: user)

    assert email_of(user) == to_string(user.email)
  end

  test "stops taking codes after five wrong ones, even the right one", %{user: user} do
    {user, code} = request!(user)

    for _ <- 1..5 do
      assert {:error, %Ash.Error.Invalid{}} = Accounts.confirm_email_change(user, "wrong", actor: user)
    end

    assert {:error, %Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{}]}} =
             Accounts.confirm_email_change(user, code, actor: user)
  end

  test "limits how many codes can be requested", %{user: user} do
    for _ <- 1..5, do: Accounts.request_email_change!(user, "new@example.com", actor: user)

    assert {:error, %Ash.Error.Forbidden{errors: [%AshRateLimiter.LimitExceeded{}]}} =
             Accounts.request_email_change(user, "new@example.com", actor: user)
  end

  test "rejects an invalid or unchanged address", %{user: user} do
    assert {:error, %Ash.Error.Invalid{}} = Accounts.request_email_change(user, "not-an-email", actor: user)

    assert {:error, %Ash.Error.Invalid{}} =
             Accounts.request_email_change(user, String.upcase(to_string(user.email)), actor: user)

    assert all_enqueued(worker: SendEmailChangeCode) == []
  end

  test "another user can neither request nor confirm a change", %{user: user} do
    other = generate(admin_user(admin: false))

    assert {:error, %Ash.Error.Forbidden{}} = Accounts.request_email_change(user, "new@example.com", actor: other)

    {user, code} = request!(user)
    assert {:error, %Ash.Error.Forbidden{}} = Accounts.confirm_email_change(user, code, actor: other)
    assert email_of(user) == to_string(user.email)
  end

  test "an address already on another account is refused at confirmation", %{user: user} do
    taken = generate(admin_user(admin: false))
    {user, code} = request!(user, to_string(taken.email))

    assert {:error, %Ash.Error.Invalid{}} = Accounts.confirm_email_change(user, code, actor: user)
  end
end
