defmodule Edenflowers.ChildEnvTest do
  use ExUnit.Case, async: true

  alias Edenflowers.ChildEnv

  test "clears credentials and leaves the rest of the environment alone" do
    env = %{
      "DATABASE_URL" => "ecto://user:pass@host/db",
      "STRIPE_SECRET_KEY" => "sk_live",
      "FASTMAIL_API_TOKEN" => "token",
      "PATH" => "/usr/bin",
      "PHX_HOST" => "example.com"
    }

    assert Enum.sort(ChildEnv.without_secrets(env)) == [
             {"DATABASE_URL", nil},
             {"FASTMAIL_API_TOKEN", nil},
             {"STRIPE_SECRET_KEY", nil}
           ]
  end

  test "a child process doesn't see a cleared variable" do
    env = ChildEnv.without_secrets(%{"EDENFLOWERS_TEST_SECRET" => "hidden"})

    assert {"", 0} = System.cmd("sh", ["-c", "printf '%s' \"$EDENFLOWERS_TEST_SECRET\""], env: env)
  end
end
