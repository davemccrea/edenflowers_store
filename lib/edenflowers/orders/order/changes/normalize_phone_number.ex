defmodule Edenflowers.Orders.Order.Changes.NormalizePhoneNumber do
  @moduledoc """
  Stores the phone number in a consistent format, so the admin's SMS and
  WhatsApp links can rely on it. A blank number is left to `present/1`.
  """
  use Ash.Resource.Change
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.PhoneNumber

  @impl true
  def change(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :recipient_phone_number) do
      nil -> changeset
      input -> normalize(changeset, input)
    end
  end

  defp normalize(changeset, input) do
    case PhoneNumber.format(input) do
      {:ok, formatted} ->
        Ash.Changeset.force_change_attribute(changeset, :recipient_phone_number, formatted)

      :error ->
        Ash.Changeset.add_error(changeset,
          field: :recipient_phone_number,
          message: ~t"Enter a valid phone number. For non-Finnish numbers, start with the country code, e.g. +44."
        )
    end
  end
end
