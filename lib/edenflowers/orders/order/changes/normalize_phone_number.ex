defmodule Edenflowers.Orders.Order.Changes.NormalizePhoneNumber do
  @moduledoc """
  Stores the phone number in a consistent format, so the admin's SMS and
  WhatsApp links can rely on it. A blank number is left to `present/1`.

  Normalises the `attribute:` given, or the `argument:` given, so an error
  lands on the field the form shows.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.PhoneNumber

  @impl true
  def change(changeset, opts, _context) do
    {field, get, set} =
      case Keyword.fetch(opts, :argument) do
        {:ok, argument} ->
          {argument, &Ash.Changeset.get_argument/2, &Ash.Changeset.set_argument/3}

        :error ->
          {Keyword.fetch!(opts, :attribute), &Ash.Changeset.get_attribute/2, &Ash.Changeset.force_change_attribute/3}
      end

    case get.(changeset, field) do
      nil -> changeset
      input -> normalize(changeset, field, input, set)
    end
  end

  defp normalize(changeset, field, input, set) do
    case PhoneNumber.format(input) do
      {:ok, formatted} ->
        set.(changeset, field, formatted)

      :error ->
        Ash.Changeset.add_error(changeset,
          field: field,
          message: ~t"Enter a valid phone number. For non-Finnish numbers, start with the country code, e.g. +44."
        )
    end
  end
end
