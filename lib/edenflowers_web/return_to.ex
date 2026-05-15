defmodule EdenflowersWeb.ReturnTo do
  @moduledoc """
  Validates and normalises post-sign-in return targets.

  Only same-origin, path-only URLs are allowed. The sign-in page itself and
  auth callbacks are filtered out so the user never lands back inside the
  login flow.
  """

  @disallowed_prefixes ["/sign-in", "/sign-out", "/auth", "/password-reset"]

  @doc """
  Returns the candidate if it's a safe path to redirect to after sign-in,
  otherwise `nil`. A safe path:

    * is a binary
    * starts with `/` but not `//` (which `URI.parse/1` treats as host-relative)
    * does not start with any auth-related prefix

  Query strings and fragments are preserved.
  """
  def safe_path(path) when is_binary(path) do
    cond do
      not String.starts_with?(path, "/") -> nil
      String.starts_with?(path, "//") -> nil
      disallowed?(path) -> nil
      true -> path
    end
  end

  def safe_path(_), do: nil

  defp disallowed?(path) do
    Enum.any?(@disallowed_prefixes, fn prefix ->
      path == prefix or String.starts_with?(path, prefix <> "/") or
        String.starts_with?(path, prefix <> "?")
    end)
  end
end
