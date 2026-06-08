defmodule Edenflowers.Geography.Geocoding.Behaviour do
  @callback get_address(query :: String.t(), locale :: String.t()) ::
              {:ok, {String.t(), String.t(), String.t()}} | {:error, atom()}
end

defmodule Edenflowers.Geography.Geocoding do
  @moduledoc """
  Entry point for geocoding addresses into positions.

  Production and development default to the HERE adapter. Tests configure a
  Mox mock (see `Edenflowers.Geography.Geocoding.Mock`).
  """

  @spec get_address(String.t(), String.t()) :: {:ok, {String.t(), String.t(), String.t()}} | {:error, atom()}
  def get_address(query, locale) do
    implementation().get_address(query, locale)
  end

  defp implementation do
    Application.get_env(:edenflowers, :geocoding, Edenflowers.Geography.Geocoding.HERE)
  end
end
