defmodule Edenflowers.Store.Order.Validations.ValidateCustomerEmail do
  @moduledoc """
  Validates that `customer_email` looks like an email address.
  """
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @email_regex ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :customer_email) do
      nil ->
        :ok

      email when is_binary(email) ->
        if Regex.match?(@email_regex, email) do
          :ok
        else
          {:error, field: :customer_email, message: ~t"Must be a valid email address"}
        end
    end
  end
end
