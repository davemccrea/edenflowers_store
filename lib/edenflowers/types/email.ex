defmodule Edenflowers.Types.Email do
  @moduledoc """
  A trimmed string that looks like an email address. Ash's `match` constraint
  can't carry a custom message, so the check lives in `apply_constraints/2`.
  """
  use Ash.Type.NewType, subtype_of: :string, constraints: [trim?: true]

  @format ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @impl Ash.Type
  def apply_constraints(nil, _constraints), do: {:ok, nil}

  def apply_constraints(value, constraints) do
    with {:ok, value} <- Ash.Type.apply_constraints(:string, value, subtype_constraints(constraints)) do
      if Regex.match?(@format, value), do: {:ok, value}, else: {:error, message: "Must be a valid email address"}
    end
  end
end
