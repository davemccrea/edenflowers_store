defmodule Edenflowers.Payments.Validations.NotAlreadyPaid do
  @moduledoc """
  Fails with `AlreadyPaid` when the record's `attribute` already holds its
  `paid` value, e.g. `attribute: :payment_status, paid: :paid`.
  """
  use Ash.Resource.Validation

  alias Edenflowers.Payments.Errors.AlreadyPaid

  # Ash 3.33's streamed bulk updates pass the cached options wrapper through.
  @impl true
  def atomic(changeset, {:templated, opts}, context), do: atomic(changeset, opts, context)

  def atomic(_changeset, opts, _context) do
    {:atomic, :*, expr(^ref(opts[:attribute]) == ^opts[:paid]), expr(error(^AlreadyPaid, %{}))}
  end
end
