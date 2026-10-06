defmodule Edenflowers.Orders.Changes.NormalizePhoneNumber do
  @moduledoc """
  Stores the phone number in a consistent format, so the admin's SMS and
  WhatsApp links can rely on it. A blank number is left to `present/1`.

  Normalises `recipient_phone_number` unless given another `attribute:`.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.PhoneNumber

  @impl true
  def change(changeset, opts, _context) do
    attribute = Keyword.get(opts, :attribute, :recipient_phone_number)

    case Ash.Changeset.get_attribute(changeset, attribute) do
      nil -> changeset
      input -> normalize(changeset, attribute, input)
    end
  end

  defp normalize(changeset, attribute, input) do
    case PhoneNumber.format(input) do
      {:ok, formatted} ->
        Ash.Changeset.force_change_attribute(changeset, attribute, formatted)

      :error ->
        Ash.Changeset.add_error(changeset,
          field: attribute,
          message: ~t"Enter a valid phone number. For non-Finnish numbers, start with the country code, e.g. +44."
        )
    end
  end
end
