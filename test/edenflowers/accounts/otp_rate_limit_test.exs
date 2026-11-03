defmodule Edenflowers.Accounts.OtpRateLimitTest do
  use Edenflowers.DataCase, async: true

  import Generator

  alias Edenflowers.Accounts.User

  # The email is matched case-insensitively, so a fresh allowance per spelling
  # would let anyone guess a code by retyping the address in another case.
  test "wrong sign-in codes count against the account however the email is cased" do
    generate(admin_user(admin: false, email: "otp-limit@example.com"))
    strategy = AshAuthentication.Info.strategy!(User, :otp)

    sign_in = fn email ->
      AshAuthentication.Strategy.action(strategy, :sign_in, %{"email" => email, "otp" => "000000"}, [])
    end

    for _ <- 1..5, do: assert({:error, _} = sign_in.("otp-limit@example.com"))

    for email <- ["OTP-limit@example.com", "Otp-Limit@Example.com"] do
      {:error, error} = sign_in.(email)
      assert inspect(error, limit: :infinity) =~ "LimitExceeded"
    end
  end
end
