defmodule Edenflowers.ChildEnv do
  @moduledoc """
  The `env:` option for `System.cmd/3`. A child process inherits every
  environment variable of the app, so this clears the ones holding credentials.
  """

  @secret_name ~r/KEY|SECRET|TOKEN|PASSWORD|DATABASE_URL/

  @spec without_secrets(%{String.t() => String.t()}) :: [{String.t(), nil}]
  def without_secrets(env \\ System.get_env()) do
    for {name, _value} <- env, name =~ @secret_name, do: {name, nil}
  end
end
