defmodule Edenflowers.RateLimiter do
  @moduledoc """
  In-memory ETS-backed rate limiter used by `AshRateLimiter` for OTP brute-force
  protection on the `Edenflowers.Accounts.User` resource.
  """
  use Hammer, backend: :ets
end
